output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "workstation_host" {
  value = google_workstations_workstation.workstation.host
}

output "firewall_policy_name" {
  value = google_compute_network_firewall_policy.fqdn_policy.name
}

output "gcw_vm_service_account" {
  value = local.gcw_vm_sa
}

output "parsed_fqdn_entries" {
  description = "FQDN entries parsed from allowed-hosts.txt, grouped by the firewall rule they produce."
  value       = local.fqdn_groups
}

output "parsed_cidr_allow_entries" {
  description = "CIDR allow entries parsed from allowed-cidrs.txt, grouped by the firewall rule they produce."
  value       = local.cidr_allow_groups
}

output "parsed_cidr_deny_entries" {
  description = "CIDR exclusion entries parsed from allowed-cidrs.txt (the - prefixed lines)."
  value       = local.cidr_deny_groups
}

output "firewall_rule_count" {
  description = "Total firewall rules that will be created (user + infrastructure)."
  value       = local.total_rule_count
}
