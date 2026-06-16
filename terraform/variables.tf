variable "host_project_id" {
  description = "GCP project ID for the Shared VPC host project"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.host_project_id))
    error_message = "host_project_id must be 6-30 chars, lowercase letters, digits, hyphens."
  }
}

variable "service_project_id" {
  description = "GCP project ID for the Cloud Workstations service project"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_project_id))
    error_message = "service_project_id must be 6-30 chars, lowercase letters, digits, hyphens."
  }
}

variable "service_project_num" {
  description = "Project number of the service project (needed for service account IAM)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{6,}", var.service_project_num))
    error_message = "service_project_num must be numeric."
  }
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west2"
}

variable "firewall_mode" {
  description = "Firewall mode: 'enforce' (default deny active, unmatched traffic blocked) or 'audit' (all traffic allowed with logging, use to preview what would be blocked)."
  type        = string
  default     = "enforce"

  validation {
    condition     = contains(["enforce", "audit"], var.firewall_mode)
    error_message = "firewall_mode must be 'enforce' or 'audit'."
  }
}

variable "allowed_fqdns" {
  description = "List of FQDNs to allow for egress (all ports). Defaults to reading from allowed-hosts.txt, which supports per-entry port specs."
  type        = list(string)
  default     = null
}

variable "allowed_cidrs" {
  description = "List of IP CIDR ranges to allow for egress (all ports). Defaults to reading from allowed-cidrs.txt, which supports per-entry port specs."
  type        = list(string)
  default     = null
}

variable "allowlist_dir" {
  description = "Directory containing allowed-hosts.txt and allowed-cidrs.txt. Defaults to the repository root (built-in files). Set to read lists from an external source — e.g. a git submodule checkout, an absolute path, or a directory relative to the terraform/ module."
  type        = string
  default     = null
}

locals {
  # Resolve the base directory for allow list files.
  # null  → repo root (backwards compatible)
  # /abs  → absolute path
  # rel   → relative to the terraform/ module directory
  allowlist_base = var.allowlist_dir != null ? (
    startswith(var.allowlist_dir, "/") ? var.allowlist_dir : "${path.module}/../${var.allowlist_dir}"
  ) : "${path.module}/.."

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
  #   (see check blocks in firewall.tf).
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

  # List of offending lines for error messages (empty if all valid)
  fqdn_invalid_lines = [for line in local.fqdn_raw_lines : line if length(compact(split(" ", line))) < 2]
  cidr_invalid_lines = [for line in local.cidr_raw_lines : line if length(compact(split(" ", line))) < 2]

  # Group entries by port spec so each unique spec becomes one firewall rule.
  # "*" expands to all TCP ports (0-65535).
  fqdn_groups = {
    for idx, spec in distinct([for e in local.fqdn_entries : e.ports]) :
    spec => {
      priority = 1200 + idx
      fqdns   = [for e in local.fqdn_entries : e.value if e.ports == spec]
      ports   = spec == "*" ? ["0-65535"] : split(",", spec)
    }
  }

  # CIDR exclusions (- prefix): deny rules at lower priority numbers so they
  # evaluate before the allow rules. Wide gap from FQDN range (1200+) avoids
  # collisions even with many unique port specs.
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

  gcw_vm_sa = "service-${var.service_project_num}@gcp-sa-workstationsvm.iam.gserviceaccount.com"
  gcw_agent_sa = "service-${var.service_project_num}@gcp-sa-workstations.iam.gserviceaccount.com"
  gcw_control_plane_ip = try(google_workstations_workstation_cluster.cluster.control_plane_ip, "10.0.0.7")

  # GCP allows max 256 rules per network firewall policy. Fail at plan time
  # if the allow lists would exceed that after grouping + infra rules.
  # 7 infra rules: container_registry, googleapis, dns, restricted_vip,
  # gcw_control_plane, gcw_control_plane_ip, default_deny.
  # +1 for audit_allow_all when in audit mode.
  total_rule_count = length(local.fqdn_groups) + length(local.cidr_deny_groups) + length(local.cidr_allow_groups) + 7 + (var.firewall_mode == "audit" ? 1 : 0)
}
