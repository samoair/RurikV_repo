terraform {
  required_version = ">= 1.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.191"
    }
  }

  backend "local" {}
}

provider "yandex" {
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.zone
}

# ─── VPC ─────────────────────────────────────────────────────────────────────

resource "yandex_vpc_network" "this" {
  name = var.network_name
}

resource "yandex_vpc_subnet" "this" {
  name           = var.subnet_name
  network_id     = yandex_vpc_network.this.id
  zone           = var.zone
  v4_cidr_blocks = [var.subnet_cidr]
}

# ─── Service Account ─────────────────────────────────────────────────────────

resource "yandex_iam_service_account" "this" {
  name = var.sa_name
}

resource "yandex_resourcemanager_folder_iam_member" "sa_editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.this.id}"
}

# ─── Master Node ─────────────────────────────────────────────────────────────

resource "yandex_compute_instance" "master" {
  name        = "${var.cluster_name}-master"
  hostname    = "master"
  platform_id = var.platform_id
  zone        = var.zone

  resources {
    cores  = var.master_cores
    memory = var.master_memory
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      size     = var.disk_size
      type     = var.disk_type
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.this.id
    nat                = true
    security_group_ids = []
  }

  metadata = {
    ssh-keys  = "ubuntu:${file(var.ssh_public_key_path)}"
    user-data = file("${path.module}/cloud-init-master.yaml")
  }
}

# ─── Worker Nodes ────────────────────────────────────────────────────────────

resource "yandex_compute_instance" "worker" {
  count       = var.worker_count
  name        = "${var.cluster_name}-worker-${count.index + 1}"
  hostname    = "worker${count.index + 1}"
  platform_id = var.platform_id
  zone        = var.zone

  resources {
    cores  = var.worker_cores
    memory = var.worker_memory
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      size     = var.disk_size
      type     = var.disk_type
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.this.id
    nat                = true
    security_group_ids = []
  }

  metadata = {
    ssh-keys  = "ubuntu:${file(var.ssh_public_key_path)}"
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
