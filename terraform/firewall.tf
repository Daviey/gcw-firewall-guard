resource "google_compute_network_firewall_policy" "fqdn_policy" {
  provider    = google.host
  name        = "fqdn-allow-policy"
  description = "FQDN/CIDR egress allow list with per-entry ports, CIDR exclusions, and default deny"

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.host_compute]
}

# GCP caps network firewall policies at 256 rules. Fail at plan time before
# hitting the API limit.
check "rule_limit" {
  assert {
    condition     = local.total_rule_count <= 256
    error_message = "Firewall policy would have ${local.total_rule_count} rules (GCP max 256). Reduce unique port specs to consolidate."
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_fqdns" {
  for_each                = local.fqdn_groups
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = each.value.priority
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow egress to user-specified FQDNs (${each.key == "*" ? "all ports" : each.key})"
  target_service_accounts = [local.gcw_vm_sa]

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
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = each.value.priority
  action                  = "deny"
  direction               = "EGRESS"
  description             = "Deny egress to excluded IP ranges (${each.key == "*" ? "all ports" : each.key})"
  target_service_accounts = [local.gcw_vm_sa]

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
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = each.value.priority
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow egress to user-specified IP ranges (${each.key == "*" ? "all ports" : each.key})"
  target_service_accounts = [local.gcw_vm_sa]

  match {
    dest_ip_ranges = each.value.cidrs

    layer4_configs {
      ip_protocol = "tcp"
      ports       = each.value.ports
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_googleapis" {
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = 999
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow HTTPS to googleapis.com (GCW dependency)"
  target_service_accounts = [local.gcw_vm_sa]

  match {
    dest_fqdns = ["googleapis.com"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_dns" {
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = 1001
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow DNS resolution"
  target_service_accounts = [local.gcw_vm_sa]

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
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = 1050
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow Google restricted and private API IPs"
  target_service_accounts = [local.gcw_vm_sa]

  match {
    dest_ip_ranges = ["199.36.153.4/30", "199.36.153.8/30"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443", "80"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_container_registry" {
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = 998
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow container image pulls (Artifact Registry / GCR)"
  target_service_accounts = [local.gcw_vm_sa]

  match {
    dest_fqdns = [
      "pkg.dev",
      "gcr.io",
    ]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443", "80"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_gcw_control_plane" {
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = 1100
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow GCW control plane"
  target_service_accounts = [local.gcw_vm_sa]

  match {
    dest_fqdns = ["cloudworkstations.dev"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443", "980"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_gcw_control_plane_ip" {
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = 1101
  action                  = "allow"
  direction               = "EGRESS"
  description             = "Allow GCW control plane (cluster-internal IP)"
  target_service_accounts = [local.gcw_vm_sa]

  match {
    dest_ip_ranges = [local.gcw_control_plane_ip]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443", "980", "80"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "default_deny_egress" {
  provider                = google.host
  firewall_policy         = google_compute_network_firewall_policy.fqdn_policy.name
  priority                = 65534
  action                  = "deny"
  direction               = "EGRESS"
  description             = "Default deny all egress"
  target_service_accounts = [local.gcw_vm_sa]

  match {
    dest_ip_ranges = ["0.0.0.0/0"]

    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_association" "vpc_association" {
  provider         = google.host
  name             = "network-ngfw-test-vpc"
  firewall_policy  = google_compute_network_firewall_policy.fqdn_policy.name
  attachment_target = google_compute_network.vpc.id
}
