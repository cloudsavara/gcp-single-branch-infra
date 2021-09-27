provider "google" {
    credentials = "${file("C:\\Users\\nkolli\\Documents\\Terraform\\GCP\\credentials.json")}"
    project     = "lyrical-bolt-318719"
}
resource "google_compute_network" "myvpc" {
  project                 = "lyrical-bolt-318719"
  name                    = "myvpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_firewall" "myrules" {
  name        = "tf-fw-rules"
  network     = google_compute_network.myvpc.name
  description = "Creates firewall rule targeting tagged instances"

  allow {
    protocol  = "tcp"
    ports     = ["22"]
  }

  allow {
      protocol = "tcp"
      ports = ["0-65535"]
  }
}

resource "google_compute_subnetwork" "tf-subnet-1" {
    name = "tf-subnet-1"
    ip_cidr_range = "10.2.0.0/16"
    region        = "us-west1"
    network       = google_compute_network.myvpc.id
}

data "google_compute_image" "mysbpimage" {
    name = "mysbpimage"
}

resource "google_compute_address" "static" {
  name = "vm-public-address"
  project = "lyrical-bolt-318719"
  region = "us-west1"
  depends_on = [ google_compute_firewall.myrules]
}

resource "google_compute_instance" "tf-vm" {
    name = "tf-vm"
    machine_type = "e2-medium"
    zone = "us-west1-b"

    boot_disk {
    initialize_params {
      image = data.google_compute_image.mysbpimage.name
        }
    }
network_interface {
    subnetwork = google_compute_subnetwork.tf-subnet-1.name
    access_config {
        nat_ip = google_compute_address.static.address      
    }
}
metadata = {
  ssh-keys = "nkolli:${file("C:\\Users\\nkolli\\.ssh\\id_rsa.pub")}"
}

provisioner "remote-exec" {
        inline = [
            "echo 'jenkins ALL=(ALL) NOPASSWD: ALL' | sudo EDITOR='tee -a' visudo",
            "wget -O /tmp/pre_install.yml https://raw.githubusercontent.com/kodekolli/gcp-single-branch-infra/main/pre_install.yml",
            "ansible-playbook -u centos /tmp/pre_install.yml",
            "wget -O /tmp/installvault.sh https://raw.githubusercontent.com/kodekolli/gcp-single-branch-infra/main/vault_install.sh",
            "sudo chmod +x /tmp/installvault.sh",
            "sudo sh /tmp/installvault.sh"
        ]
        connection {
            host = self.network_interface[0].access_config[0].nat_ip
            type = "ssh"
            user = "nkolli"
            private_key = "${file("C:\\Users\\nkolli\\.ssh\\id_rsa")}"
        }
    }
}

output "public_ip_address" {
    value = "${google_compute_instance.tf-vm.network_interface.0.access_config.0.nat_ip}"
}
