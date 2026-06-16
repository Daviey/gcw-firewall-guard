variable "project_id" {
  description = "GCP project ID where the firewall policy is created (host project)."
  type        = string
}

variable "vpc_id" {
  description = "Self-link of the VPC to associate the firewall policy with."
  type        = string
}

variable "vpc_name" {
  description = "Name of the VPC. Used for the policy association name."
  type        = string
}

variable "target_service_accounts" {
  description = "Service account(s) the firewall rules apply to."
  type        = list(string)
}

variable "gcw_control_plane_ip" {
  description = "Internal IP of the Cloud Workstations control plane (for GCW dependency rules)."
  type        = string
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

variable "allowlist_dir" {
  description = "Directory containing allowed-hosts.txt and allowed-cidrs.txt. Must be an absolute or module-relative path."
  type        = string
}

variable "allowed_fqdns" {
  description = "Override: list of FQDNs to allow on all ports. Takes precedence over allowed-hosts.txt."
  type        = list(string)
  default     = null
}

variable "allowed_cidrs" {
  description = "Override: list of CIDRs to allow on all ports. Takes precedence over allowed-cidrs.txt."
  type        = list(string)
  default     = null
}

variable "policy_name" {
  description = "Name for the network firewall policy."
  type        = string
  default     = "egress-allow-policy"
}
