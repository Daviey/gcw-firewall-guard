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
