terraform {
  backend "gcs" {
    bucket = "main-project-402906-tfstate"
    prefix = "terraform/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
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
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_firestore_database" "default" {
  name        = "(default)"
  location_id = "us-central1"
  type        = "FIRESTORE_NATIVE"
}

resource "google_cloud_run_v2_service" "portfolio_tracker_api" {
  name     = "portfolio-tracker-api"
  location = "us-central1"

  template {
    service_account = "github-actions-deployer@main-project-402906.iam.gserviceaccount.com"
    containers {
      image = var.tracker_image_tag
      resources {
        limits = {
          cpu    = "1000m"
          memory = "128Mi"
        }
      }
    }
    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "tracker_public_access" {
  project  = google_cloud_run_v2_service.portfolio_tracker_api.project
  location = google_cloud_run_v2_service.portfolio_tracker_api.location
  name     = google_cloud_run_v2_service.portfolio_tracker_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_project_iam_member" "deployer_datastore_user" {
  project = "main-project-402906"
  role    = "roles/datastore.user"
  member  = "serviceAccount:github-actions-deployer@main-project-402906.iam.gserviceaccount.com"
}