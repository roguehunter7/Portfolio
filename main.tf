terraform {
  backend "gcs" {
    bucket = "main-project-402906-tfstate"
    prefix = "terraform/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "main-project-402906"
  region  = "us-central1"
}

resource "google_cloud_run_v2_service" "portfolio_app" {
  name     = "portfolio-app"
  location = "us-central1"

  template {
    containers {
      image = var.container_image_tag
      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    }
    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = google_cloud_run_v2_service.portfolio_app.project
  location = google_cloud_run_v2_service.portfolio_app.location
  name     = google_cloud_run_v2_service.portfolio_app.name
  role     = "roles/run.viewer"
  member   = "allUsers"
}