terraform {
  required_version = ">= 1.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.191"
    }
  }
}

# Credentials are picked up from YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID env vars
provider "yandex" {}

# ─── VPC ─────────────────────────────────────────────────────────────────────

resource "yandex_vpc_network" "this" {
  name = "prod-network"
}

resource "yandex_vpc_subnet" "this" {
  name           = "prod-subnet"
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

# ─── Service Account ─────────────────────────────────────────────────────────

resource "yandex_iam_service_account" "this" {
  name = "k8s-prod-sa"
}

# ─── Master Node ─────────────────────────────────────────────────────────────

resource "yandex_compute_instance" "master" {
  name        = "prod-master"
  hostname    = "master"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 8
  }

  boot_disk {
    initialize_params {
      image_id = "fd81radk00nmm2jpqh94" # Ubuntu 22.04 LTS v20251229
      size     = 64
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.this.id
    nat       = true
  }

  metadata = {
    ssh-keys  = "ubuntu:${file(pathexpand(var.ssh_public_key_path))}"
    user-data = file("${path.module}/cloud-init-master.yaml")
  }
}

# ─── Worker Nodes ────────────────────────────────────────────────────────────

resource "yandex_compute_instance" "worker" {
  count       = 3
  name        = "prod-worker-${count.index + 1}"
  hostname    = "worker${count.index + 1}"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 8
  }

  boot_disk {
    initialize_params {
      image_id = "fd81radk00nmm2jpqh94"
      size     = 64
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.this.id
    nat       = true
  }

  metadata = {
    ssh-keys  = "ubuntu:${file(pathexpand(var.ssh_public_key_path))}"
    user-data = file("${path.module}/cloud-init-worker.yaml")
  }
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "master_public_ip" {
  value = yandex_compute_instance.master.network_interface[0].nat_ip_address
}

output "master_internal_ip" {
  value = yandex_compute_instance.master.network_interface[0].ip_address
}

output "worker_public_ips" {
  value = yandex_compute_instance.worker[*].network_interface[0].nat_ip_address
}

output "worker_internal_ips" {
  value = yandex_compute_instance.worker[*].network_interface[0].ip_address
}
