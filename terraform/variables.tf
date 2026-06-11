variable "host_project_id" {
  description = "GCP project ID for the Shared VPC host project"
  type        = string
}

variable "service_project_id" {
  description = "GCP project ID for the Cloud Workstations service project"
  type        = string
}

variable "service_project_num" {
  description = "Project number of the service project (needed for service account IAM)"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west2"
}

variable "allowed_fqdns" {
  description = "List of FQDNs to allow for egress. Defaults to reading from allowed-hosts.txt."
  type        = list(string)
  default     = null
}

variable "allowed_cidrs" {
  description = "List of IP CIDR ranges to allow for egress. Defaults to reading from allowed-cidrs.txt."
  type        = list(string)
  default     = null
}

locals {
  allowed_fqdns = var.allowed_fqdns != null ? var.allowed_fqdns : [for h in split("\n", trimspace(file("${path.module}/../allowed-hosts.txt"))) : trimspace(h) if trimspace(h) != "" && !startswith(trimspace(h), "#")]
  allowed_cidrs = var.allowed_cidrs != null ? var.allowed_cidrs : [for c in split("\n", trimspace(file("${path.module}/../allowed-cidrs.txt"))) : trimspace(c) if trimspace(c) != "" && !startswith(trimspace(c), "#")]
  gcw_vm_sa = "service-${var.service_project_num}@gcp-sa-workstationsvm.iam.gserviceaccount.com"
  gcw_agent_sa = "service-${var.service_project_num}@gcp-sa-workstations.iam.gserviceaccount.com"
  gcw_control_plane_ip = try(google_workstations_workstation_cluster.cluster.control_plane_ip, "10.0.0.7")
}
