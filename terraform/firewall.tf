module "firewall" {
  source  = "../modules/firewall"
  providers = {
    google = google.host
  }

  project_id              = var.host_project_id
  vpc_id                  = google_compute_network.vpc.id
  vpc_name                = google_compute_network.vpc.name
  target_service_accounts = [local.gcw_vm_sa]
  gcw_control_plane_ip    = local.gcw_control_plane_ip
  firewall_mode           = var.firewall_mode
  allowlist_dir           = local.resolved_allowlist_dir
  allowed_fqdns           = var.allowed_fqdns
  allowed_cidrs           = var.allowed_cidrs

  depends_on = [google_project_service.host_compute]
}
