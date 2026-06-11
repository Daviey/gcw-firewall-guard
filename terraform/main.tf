resource "google_project_service" "host_compute" {
  provider            = google.host
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "host_servicenetworking" {
  provider            = google.host
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "svc_compute" {
  provider            = google.svc
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "svc_workstations" {
  provider            = google.svc
  service            = "workstations.googleapis.com"
  disable_on_destroy = false
}
