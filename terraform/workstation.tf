resource "google_workstations_workstation_cluster" "cluster" {
  provider                = google-beta.svc
  workstation_cluster_id = "ngfw-test-cluster"
  location               = var.region
  network                = "projects/${var.host_project_id}/global/networks/${google_compute_network.vpc.name}"
  subnetwork             = "projects/${var.host_project_id}/regions/${var.region}/subnetworks/${google_compute_subnetwork.subnet.name}"

  depends_on = [
    google_project_service.svc_workstations,
    google_compute_shared_vpc_service_project.svc,
    google_service_networking_connection.private_vpc_connection,
  ]
}

resource "google_workstations_workstation_config" "config" {
  provider               = google-beta.svc
  workstation_config_id  = "ngfw-test-config"
  workstation_cluster_id = google_workstations_workstation_cluster.cluster.workstation_cluster_id
  location               = var.region

  host {
    gce_instance {
      machine_type      = "e2-standard-4"
      boot_disk_size_gb = 50
    }
  }

  container {
    image = "${var.region}-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
  }

  persistent_directories {
    mount_path = "/home"
    gce_pd {
      size_gb        = 200
      fs_type        = "ext4"
      disk_type      = "pd-standard"
      reclaim_policy = "DELETE"
    }
  }

  idle_timeout    = "7200s"
  running_timeout = "7200s"
}

resource "google_workstations_workstation" "workstation" {
  provider                = google-beta.svc
  workstation_id          = "ngfw-test-ws"
  workstation_cluster_id  = google_workstations_workstation_cluster.cluster.workstation_cluster_id
  workstation_config_id   = google_workstations_workstation_config.config.workstation_config_id
  location                = var.region
}
