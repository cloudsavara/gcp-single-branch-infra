provider "google" {
  credentials = "${file("/var/lib/jenkins/credentials.json")}"
}

# VPC
resource "google_compute_network" "vpc" {
  name                    = "gke-vpc"
  project                 = "lyrical-bolt-318719"
  auto_create_subnetworks = "false"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "gke-subnet"
  project       = "lyrical-bolt-318719"
  region        = "us-west1"
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"
}
