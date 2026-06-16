output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "workstation_host" {
  value = google_workstations_workstation.workstation.host
}

output "firewall_policy_name" {
  value = module.firewall.firewall_policy_name
}

output "gcw_vm_service_account" {
  value = local.gcw_vm_sa
}

output "firewall_mode" {
  value = module.firewall.firewall_mode
}

output "firewall_rule_count" {
  value = module.firewall.firewall_rule_count
}

output "parsed_fqdn_entries" {
  value = module.firewall.parsed_fqdn_entries
}

output "parsed_cidr_allow_entries" {
  value = module.firewall.parsed_cidr_allow_entries
}

output "parsed_cidr_deny_entries" {
  value = module.firewall.parsed_cidr_deny_entries
}
