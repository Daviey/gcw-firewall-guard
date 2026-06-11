resource "google_compute_network" "vpc" {
  provider                = google.host
  name                    = "ngfw-test-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.host_compute]
}

resource "google_compute_subnetwork" "subnet" {
  provider                 = google.host
  name                     = "ngfw-test-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.0.0.0/24"
  private_ip_google_access = true
}

resource "google_compute_shared_vpc_host_project" "host" {
  provider = google.host
  project  = var.host_project_id

  depends_on = [google_project_service.host_compute]
}

resource "google_compute_shared_vpc_service_project" "svc" {
  provider        = google.host
  host_project    = var.host_project_id
  service_project = var.service_project_id

  depends_on = [google_compute_shared_vpc_host_project.host]
}

resource "google_compute_subnetwork_iam_member" "gcw_agent_network_user" {
  provider   = google.host
  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.subnet.name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${local.gcw_agent_sa}"
}

resource "google_compute_subnetwork_iam_member" "gcw_vm_network_user" {
  provider   = google.host
  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.subnet.name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${local.gcw_vm_sa}"
}

resource "google_project_iam_binding" "gcw_agent_service_agent_host" {
  project = var.host_project_id
  role    = "roles/workstations.serviceAgent"
  members = ["serviceAccount:${local.gcw_agent_sa}"]
}

resource "google_project_iam_binding" "gcw_agent_service_agent_svc" {
  project = var.service_project_id
  role    = "roles/workstations.serviceAgent"
  members = ["serviceAccount:${local.gcw_agent_sa}"]
}

resource "google_compute_global_address" "private_service_access" {
  provider       = google.host
  name          = "google-managed-services-ngfw-test-subnet"
  address_type  = "INTERNAL"
  purpose       = "VPC_PEERING"
  prefix_length = 24
  network       = google_compute_network.vpc.id

  depends_on = [google_project_service.host_servicenetworking]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]

  depends_on = [google_project_service.host_servicenetworking]
}
