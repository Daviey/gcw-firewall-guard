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

# Three provider configs for the Shared VPC split:
#   google.host       → host project (VPC, firewall policy, IAM on subnets)
#   google.svc        → service project (API enablement, workstation IAM)
#   google-beta.svc   → service project (Workstations API needs google-beta)

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
