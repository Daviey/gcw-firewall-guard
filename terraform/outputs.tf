output "vpc_name" {
  description = "Name of the Shared VPC network."
  value       = google_compute_network.vpc.name
}

output "workstation_host" {
  description = "URL of the Cloud Workstation instance."
  value       = google_workstations_workstation.workstation.host
}

output "firewall_policy_name" {
  description = "Name of the network firewall policy."
  value       = module.firewall.firewall_policy_name
}

output "gcw_vm_service_account" {
  description = "Email of the GCW VM default service account (target of firewall rules)."
  value       = local.gcw_vm_sa
}

output "firewall_mode" {
  description = "Current firewall mode: enforce or audit."
  value       = module.firewall.firewall_mode
}

output "firewall_rule_count" {
  description = "Total firewall rules created (user + infrastructure)."
  value       = module.firewall.firewall_rule_count
}

output "parsed_fqdn_entries" {
  description = "FQDN entries parsed from the allow list, grouped by firewall rule."
  value       = module.firewall.parsed_fqdn_entries
}

output "parsed_cidr_allow_entries" {
  description = "CIDR allow entries parsed from the allow list, grouped by firewall rule."
  value       = module.firewall.parsed_cidr_allow_entries
}

output "parsed_cidr_deny_entries" {
  description = "CIDR exclusion entries (- prefix) parsed from the allow list."
  value       = module.firewall.parsed_cidr_deny_entries
}
