locals {
  allowlist_base = var.allowlist_dir

  # Parse allow list files into structured entries: { value, ports }
  # Line format:  <value> <ports> [# comment]
  #   value  = FQDN or CIDR (first whitespace-delimited token)
  #            CIDR files only: prefix with - to create a deny (exclusion) rule,
  #            e.g.  -10.1.0.0/16  *   denies all traffic to that subnet.
  #            Deny rules get lower priority numbers so they win over allows.
  #   ports  = required. "*", "443", "80,443", "8000-9000"
  #            * = all TCP ports
  #            comma-separated for discrete ports, dash for ranges
  #   text after # is stripped as an inline comment
  #   Lines with content but no port spec cause a plan-time error
  #   (see check blocks below).
  fqdn_raw_lines = var.allowed_fqdns != null ? [] : [
    for line in split("\n", trimspace(file("${local.allowlist_base}/allowed-hosts.txt"))) :
    trimspace(split("#", line)[0])
    if trimspace(split("#", line)[0]) != ""
  ]

  fqdn_entries = var.allowed_fqdns != null ? [for v in var.allowed_fqdns : { value = v, ports = "*" }] : [
    for parts in [for line in local.fqdn_raw_lines : compact(split(" ", line))] :
    { value = parts[0], ports = parts[1] }
    if length(parts) > 1
  ]

  cidr_raw_lines = var.allowed_cidrs != null ? [] : [
    for line in split("\n", trimspace(file("${local.allowlist_base}/allowed-cidrs.txt"))) :
    trimspace(split("#", line)[0])
    if trimspace(split("#", line)[0]) != ""
  ]

  cidr_entries = var.allowed_cidrs != null ? [for v in var.allowed_cidrs : { value = v, ports = "*", deny = false }] : [
    for parts in [for line in local.cidr_raw_lines : compact(split(" ", line))] :
    { value = startswith(parts[0], "-") ? substr(parts[0], 1, -1) : parts[0], ports = parts[1], deny = startswith(parts[0], "-") }
    if length(parts) > 1
  ]

  fqdn_invalid_lines = [for line in local.fqdn_raw_lines : line if length(compact(split(" ", line))) < 2]
  cidr_invalid_lines = [for line in local.cidr_raw_lines : line if length(compact(split(" ", line))) < 2]

  # Group entries by port spec so each unique spec becomes one firewall rule.
  # Priority scheme:
  #   900-1101   hardcoded GCW infrastructure dependencies
  #   1200+      user FQDN allow rules (one per unique port spec)
  #   2000+      user CIDR deny/exclusion rules (must be lower than allows)
  #   2100+      user CIDR allow rules
  #   65533      audit-mode catch-all (only when firewall_mode=audit)
  #   65534      default deny (must always be the highest number)
  fqdn_groups = {
    for idx, spec in distinct([for e in local.fqdn_entries : e.ports]) :
    spec => {
      priority = 1200 + idx
      fqdns   = [for e in local.fqdn_entries : e.value if e.ports == spec]
      ports   = spec == "*" ? ["0-65535"] : split(",", spec)
    }
  }

  cidr_deny_groups = {
    for idx, spec in distinct([for e in local.cidr_entries : e.ports if e.deny]) :
    spec => {
      priority = 2000 + idx
      cidrs   = [for e in local.cidr_entries : e.value if e.deny && e.ports == spec]
      ports   = spec == "*" ? ["0-65535"] : split(",", spec)
    }
  }

  cidr_allow_groups = {
    for idx, spec in distinct([for e in local.cidr_entries : e.ports if !e.deny]) :
    spec => {
      priority = 2100 + idx
      cidrs   = [for e in local.cidr_entries : e.value if !e.deny && e.ports == spec]
      ports   = spec == "*" ? ["0-65535"] : split(",", spec)
    }
  }

  # 7 infra rules: container_registry, googleapis, dns, restricted_vip,
  # gcw_control_plane, gcw_control_plane_ip, default_deny.
  # +1 for audit_allow_all when in audit mode.
  total_rule_count = length(local.fqdn_groups) + length(local.cidr_deny_groups) + length(local.cidr_allow_groups) + 7 + (var.firewall_mode == "audit" ? 1 : 0)
}

resource "google_compute_network_firewall_policy" "this" {
  provider    = google
  name        = var.policy_name
  description = "FQDN/CIDR egress allow list with per-entry ports, CIDR exclusions, and default deny"

  lifecycle {
    prevent_destroy = true
  }
}

check "rule_limit" {
  assert {
    condition     = local.total_rule_count <= 256
    error_message = "Firewall policy would have ${local.total_rule_count} rules (GCP max 256). Reduce unique port specs to consolidate."
  }
}

check "fqdn_lines_have_ports" {
  assert {
    condition     = length(local.fqdn_invalid_lines) == 0
    error_message = "allowed-hosts.txt has ${length(local.fqdn_invalid_lines)} line(s) missing a port spec. Format: <domain> <ports> [# comment]. Invalid line(s): ${join(" | ", local.fqdn_invalid_lines)}"
  }
}

check "cidr_lines_have_ports" {
  assert {
    condition     = length(local.cidr_invalid_lines) == 0
    error_message = "allowed-cidrs.txt has ${length(local.cidr_invalid_lines)} line(s) missing a port spec. Format: <cidr> <ports> [# comment]. Invalid line(s): ${join(" | ", local.cidr_invalid_lines)}"
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_fqdns" {
  for_each                = local.fqdn_groups
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = each.value.priority
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow egress to user-specified FQDNs (${each.key == "*" ? "all ports" : each.key})"
  target_service_accounts = var.target_service_accounts
  enable_logging          = var.firewall_mode == "audit"

  match {
    dest_fqdns = each.value.fqdns

    layer4_configs {
      ip_protocol = "tcp"
      ports       = each.value.ports
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "deny_cidrs" {
  for_each                = local.cidr_deny_groups
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = each.value.priority
  action                  = "deny"
  direction               = "EGRESS"
  description             = "Deny egress to excluded IP ranges (${each.key == "*" ? "all ports" : each.key})"
  target_service_accounts = var.target_service_accounts
  enable_logging          = var.firewall_mode == "audit"

  match {
    dest_ip_ranges = each.value.cidrs

    layer4_configs {
      ip_protocol = "tcp"
      ports       = each.value.ports
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_cidrs" {
  for_each                = local.cidr_allow_groups
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = each.value.priority
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow egress to user-specified IP ranges (${each.key == "*" ? "all ports" : each.key})"
  target_service_accounts = var.target_service_accounts
  enable_logging          = var.firewall_mode == "audit"

  match {
    dest_ip_ranges = each.value.cidrs

    layer4_configs {
      ip_protocol = "tcp"
      ports       = each.value.ports
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_googleapis" {
  # Required regardless of user allow list — GCW needs Google APIs to function.
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = 999
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow HTTPS to googleapis.com (GCW dependency)"
  target_service_accounts = var.target_service_accounts

  match {
    dest_fqdns = ["googleapis.com"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_dns" {
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = 1001
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow DNS resolution"
  target_service_accounts = var.target_service_accounts

  match {
    dest_ip_ranges = ["0.0.0.0/0"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["53"]
    }

    layer4_configs {
      ip_protocol = "udp"
      ports       = ["53"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_google_restricted_vip" {
  # Google restricted VIP ranges for Private Google Access.
  # https://cloud.google.com/vpc/docs/configure-private-google-access
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = 1050
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow Google restricted and private API IPs"
  target_service_accounts = var.target_service_accounts

  match {
    dest_ip_ranges = ["199.36.153.4/30", "199.36.153.8/30"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443", "80"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_container_registry" {
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = 998
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow container image pulls (Artifact Registry / GCR)"
  target_service_accounts = var.target_service_accounts

  match {
    dest_fqdns = ["pkg.dev", "gcr.io"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443", "80"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_gcw_control_plane" {
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = 1100
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow GCW control plane"
  target_service_accounts = var.target_service_accounts

  match {
    dest_fqdns = ["cloudworkstations.dev"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443", "980"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_gcw_control_plane_ip" {
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = 1101
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow GCW control plane (cluster-internal IP)"
  target_service_accounts = var.target_service_accounts

  match {
    dest_ip_ranges = [var.gcw_control_plane_ip]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443", "980", "80"]
    }
  }
}

# In audit mode, this catch-all allow at 65533 sits just above the default
# deny (65534). It matches everything the allow rules didn't catch, logs it,
# and lets it through — so you can see what WOULD be blocked without blocking.
resource "google_compute_network_firewall_policy_rule" "audit_allow_all" {
  count                   = var.firewall_mode == "audit" ? 1 : 0
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = 65533
  action                  = "allow"
  direction               = "EGRESS"
  description             = "AUDIT MODE: allowing unmatched traffic with logging. Set firewall_mode=enforce to block."
  target_service_accounts = var.target_service_accounts
  enable_logging          = true

  match {
    dest_ip_ranges = ["0.0.0.0/0"]

    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "default_deny_egress" {
  provider                = google
  firewall_policy         = google_compute_network_firewall_policy.this.name
  priority                = 65534
  action                  = "deny"
  direction               = "EGRESS"
  description             = "Default deny all egress"
  target_service_accounts = var.target_service_accounts
  enable_logging          = var.firewall_mode == "audit"

  match {
    dest_ip_ranges = ["0.0.0.0/0"]

    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_association" "vpc_association" {
  provider         = google
  name             = "network-${var.vpc_name}"
  firewall_policy  = google_compute_network_firewall_policy.this.name
  attachment_target = var.vpc_id
}
