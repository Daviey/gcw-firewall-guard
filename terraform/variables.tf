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
  description = "Firewall mode: 'enforce' (default deny active) or 'audit' (all traffic allowed with logging)."
  type        = string
  default     = "enforce"

  validation {
    condition     = contains(["enforce", "audit"], var.firewall_mode)
    error_message = "firewall_mode must be 'enforce' or 'audit'."
  }
}

variable "allowed_fqdns" {
  description = "List of FQDNs to allow for egress (all ports). Defaults to reading from allowed-hosts.txt."
  type        = list(string)
  default     = null
}

variable "allowed_cidrs" {
  description = "List of IP CIDR ranges to allow for egress (all ports). Defaults to reading from allowed-cidrs.txt."
  type        = list(string)
  default     = null
}

variable "allowlist_dir" {
  description = "Directory containing allowed-hosts.txt and allowed-cidrs.txt. Defaults to the repository root. Set to read lists from an external source."
  type        = string
  default     = null
}

locals {
  gcw_vm_sa = "service-${var.service_project_num}@gcp-sa-workstationsvm.iam.gserviceaccount.com"
  gcw_agent_sa = "service-${var.service_project_num}@gcp-sa-workstations.iam.gserviceaccount.com"
  gcw_control_plane_ip = try(google_workstations_workstation_cluster.cluster.control_plane_ip, "10.0.0.7")

  # Resolve allowlist path for the module.
  # null  → repo root (backwards compatible)
  # /abs  → absolute path
  # rel   → relative to the terraform/ directory
  resolved_allowlist_dir = var.allowlist_dir != null ? (
    startswith(var.allowlist_dir, "/") ? var.allowlist_dir : "${path.module}/../${var.allowlist_dir}"
  ) : "${path.module}/.."
}
