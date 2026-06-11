terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  alias   = "host"
  project = var.host_project_id
  region  = var.region
}

provider "google" {
  alias   = "svc"
  project = var.service_project_id
  region  = var.region
}

provider "google-beta" {
  alias   = "svc"
  project = var.service_project_id
  region  = var.region
}
