# Parser test module — intentionally duplicates the parsing logic from
# ../../modules/firewall/main.tf to test it in isolation without GCP provider
# dependencies. If the module's parsing logic changes, update this to match.

locals {
  allowlist_base = "${path.module}/fixtures"

  fqdn_raw_lines = [
    for line in split("\n", trimspace(file("${local.allowlist_base}/hosts.txt"))) :
    trimspace(split("#", line)[0])
    if trimspace(split("#", line)[0]) != ""
  ]

  fqdn_entries = [
    for parts in [for line in local.fqdn_raw_lines : compact(split(" ", line))] :
    { value = parts[0], ports = parts[1] }
    if length(parts) > 1
  ]

  cidr_raw_lines = [
    for line in split("\n", trimspace(file("${local.allowlist_base}/cidrs.txt"))) :
    trimspace(split("#", line)[0])
    if trimspace(split("#", line)[0]) != ""
  ]

  cidr_entries = [
    for parts in [for line in local.cidr_raw_lines : compact(split(" ", line))] :
    { value = startswith(parts[0], "-") ? substr(parts[0], 1, -1) : parts[0], ports = parts[1], deny = startswith(parts[0], "-") }
    if length(parts) > 1
  ]

  fqdn_invalid_lines = [for line in local.fqdn_raw_lines : line if length(compact(split(" ", line))) < 2]
  cidr_invalid_lines = [for line in local.cidr_raw_lines : line if length(compact(split(" ", line))) < 2]

  fqdn_groups = {
    for idx, spec in distinct([for e in local.fqdn_entries : e.ports]) :
    spec => {
      priority = 1200 + idx
      fqdns   = [for e in local.fqdn_entries : e.value if e.ports == spec]
      ports   = spec == "*" ? ["0-65535"] : split(",", spec)
    }
  }

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

  total_rule_count = length(local.fqdn_groups) + length(local.cidr_deny_groups) + length(local.cidr_allow_groups) + 7
}

check "fqdn_lines_have_ports" {
  assert {
    condition     = length(local.fqdn_invalid_lines) == 0
    error_message = "hosts.txt has invalid line(s): ${join(" | ", local.fqdn_invalid_lines)}"
  }
}

check "cidr_lines_have_ports" {
  assert {
    condition     = length(local.cidr_invalid_lines) == 0
    error_message = "cidrs.txt has invalid line(s): ${join(" | ", local.cidr_invalid_lines)}"
  }
}

output "fqdn_entry_count" { value = length(local.fqdn_entries) }
output "fqdn_group_count" { value = length(local.fqdn_groups) }
output "cidr_entry_count" { value = length(local.cidr_entries) }
output "cidr_deny_group_count" { value = length(local.cidr_deny_groups) }
output "cidr_allow_group_count" { value = length(local.cidr_allow_groups) }
output "total_rule_count" { value = local.total_rule_count }
output "fqdn_invalid_lines" { value = local.fqdn_invalid_lines }
output "cidr_invalid_lines" { value = local.cidr_invalid_lines }

output "fqdn_groups" { value = local.fqdn_groups }
output "cidr_allow_groups" { value = local.cidr_allow_groups }
output "cidr_deny_groups" { value = local.cidr_deny_groups }
output "fqdn_entries" { value = local.fqdn_entries }
output "cidr_entries" { value = local.cidr_entries }
