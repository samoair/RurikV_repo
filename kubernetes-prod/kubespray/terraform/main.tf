terraform {
  required_version = ">= 1.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.191"
    }
  }
}

provider "yandex" {}

# ─── VPC ─────────────────────────────────────────────────────────────────────

resource "yandex_vpc_network" "this" {
  name = "ha-network"
}

resource "yandex_vpc_subnet" "this" {
  name           = "ha-subnet"
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = ["192.168.20.0/24"]
}

# ─── Master Nodes ────────────────────────────────────────────────────────────

resource "yandex_compute_instance" "master" {
  count       = 3
  name        = "ha-master-${count.index + 1}"
  hostname    = "master${count.index + 1}"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 8
  }

  boot_disk {
    initialize_params {
      image_id = "fd833ivvmqp6cuq7shpc" # Ubuntu 24.04 LTS v20250106
      size     = 64
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.this.id
    nat       = true
  }

  metadata = {
    ssh-keys  = "ubuntu:${file(pathexpand(var.ssh_public_key_path))}"
  }
}

# ─── Worker Nodes ────────────────────────────────────────────────────────────

resource "yandex_compute_instance" "worker" {
  count       = 2
  name        = "ha-worker-${count.index + 1}"
  hostname    = "worker${count.index + 1}"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 8
  }

  boot_disk {
    initialize_params {
      image_id = "fd833ivvmqp6cuq7shpc" # Ubuntu 24.04 LTS v20250106
      size     = 64
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.this.id
    nat       = true
  }

  metadata = {
    ssh-keys  = "ubuntu:${file(pathexpand(var.ssh_public_key_path))}"
  }
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "master_public_ips" {
  value = yandex_compute_instance.master[*].network_interface[0].nat_ip_address
}

output "master_internal_ips" {
  value = yandex_compute_instance.master[*].network_interface[0].ip_address
}

output "worker_public_ips" {
  value = yandex_compute_instance.worker[*].network_interface[0].nat_ip_address
}

output "worker_internal_ips" {
  value = yandex_compute_instance.worker[*].network_interface[0].ip_address
}
