output "firewall_policy_name" {
  description = "Name of the created firewall policy."
  value       = google_compute_network_firewall_policy.this.name
}

output "firewall_mode" {
  description = "Current firewall mode."
  value       = var.firewall_mode
}

output "firewall_rule_count" {
  description = "Total firewall rules (user + infrastructure)."
  value       = local.total_rule_count
}

output "parsed_fqdn_entries" {
  description = "FQDN entries grouped by firewall rule."
  value       = local.fqdn_groups
}

output "parsed_cidr_allow_entries" {
  description = "CIDR allow entries grouped by firewall rule."
  value       = local.cidr_allow_groups
}

output "parsed_cidr_deny_entries" {
  description = "CIDR exclusion entries grouped by firewall rule."
  value       = local.cidr_deny_groups
}
