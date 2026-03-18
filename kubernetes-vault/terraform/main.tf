# ============================================================================
# Terraform configuration for Yandex Cloud Kubernetes Cluster with Vault
# ============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.191.0"
    }
  }

  backend "k8s" {
    secret_name     = "tf-state-vault-cluster"
    namespace       = "default"
    in_cluster_config  = true
  }
}

# ============================================================================
# Yandex Cloud Provider
# ============================================================================
provider "yandex" {
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
}

# ============================================================================
# Data Sources
# ============================================================================
data "yandex_client_config" "client" {}

# ============================================================================
# Network Resources
# ============================================================================
resource "yandex_vpc_network" "this" {
  name = var.network_name

  labels = {
    project     = "otus-k8s-vault"
    environment = "homework"
  }
}

resource "yandex_vpc_subnet" "this" {
  name           = var.subnet_name
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.subnet_cidr]

  labels = {
    project     = "otus-k8s-vault"
    environment = "homework"
  }
}

# ============================================================================
# Service Accounts
# ============================================================================
resource "yandex_iam_service_account" "k8s" {
  name        = var.k8s_sa_name
  description = "Service account for Kubernetes cluster ${var.cluster_name}"

  labels = {
    project     = "otus-k8s-vault"
    environment = "homework"
  }
}

# Assign necessary roles to the K8s service account
resource "yandex_resourcemanager_folder_iam_member" "k8s_editor" {
  folder_id      = var.yc_folder_id
  role           = "editor"
  member         = "serviceAccount:${yandex_iam_service_account.k8s.id}"
  sleep_after    = 30
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_images_puller" {
  for_each      = toset(["container-registry.images.puller", "container-registry.images.puller"])
  folder_id      = var.yc_folder_id
  role           = each.value
  member         = "serviceAccount:${yandex_iam_service_account.k8s.id}"
}

# ============================================================================
# KMS Symmetric Key for Kubernetes Secrets
# ============================================================================
resource "yandex_kms_symmetric_key" "k8s" {
  name              = "${var.cluster_name}-secrets-key"
  description       = "KMS key for Kubernetes cluster secrets encryption"
  folder_id         = var.yc_folder_id
  default_algorithm = "AES_128"
  rotation_period   = "8760h" # 365 days

  labels = {
    project     = "otus-k8s-vault"
    environment = "homework"
  }
}

# ============================================================================
# Kubernetes Cluster
# ============================================================================
resource "yandex_kubernetes_cluster" "this" {
  name        = var.cluster_name
  description = "Kubernetes cluster for Vault and Consul homework"
  folder_id   = var.yc_folder_id

  network_id = yandex_vpc_network.this.id

  master {
    version = var.k8s_version
    zonal {
      zone      = var.yc_zone
      subnet_id = yandex_vpc_subnet.this.id
    }

    public_ip = true

    maintenance_policy {
      auto_upgrade = true

      maintenance_window {
        start_time = "03:00"
        duration   = "3h"
      }
    }

    security_group_ids = []
  }

  service_account_id      = yandex_iam_service_account.k8s.id
  node_service_account_id = yandex_iam_service_account.k8s.id

  kms_provider {
    key_id = yandex_kms_symmetric_key.k8s.id
  }

  release_channel         = "REGULAR"
  cluster_ipv4_range      = "10.112.0.0/16"
  service_ipv4_range      = "10.96.0.0/16"
  node_ipv4_cidr_mask_size = 24

  labels = {
    project     = "otus-k8s-vault"
    environment = "homework"
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s_editor,
  ]
}

# ============================================================================
# Kubernetes Node Groups
# ============================================================================

# Worker node group
resource "yandex_kubernetes_node_group" "worker" {
  name        = "${var.cluster_name}-worker"
  description = "Worker node group for general workloads"
  cluster_id  = yandex_kubernetes_cluster.this.id
  version     = var.k8s_version

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.this.id]
      security_group_ids = []
    }

    resources {
      memory = var.worker_node_memory
      cores  = var.worker_node_cores
      core_fraction = var.node_core_fraction
    }

    boot_disk {
      type = var.node_disk_type
      size = var.node_disk_size
    }

    scheduling_policy {
      preemptible = var.preemptible
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = var.worker_node_count
    }
  }

  allocation_policy {
    location {
      zone = var.yc_zone
    }
  }

  deploy_policy {
    max_expansion   = 1
    max_unavailable = 1
  }

  node_version = var.k8s_version

  node_labels = {
    node-type = "worker"
  }

  node_taints = []

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      start_time = "03:00"
      duration   = "3h"
    }
  }
}

# Infra node group for system services (Vault, Consul)
resource "yandex_kubernetes_node_group" "infra" {
  name        = "${var.cluster_name}-infra"
  description = "Infra node group for system services (Vault, Consul)"
  cluster_id  = yandex_kubernetes_cluster.this.id
  version     = var.k8s_version

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.this.id]
      security_group_ids = []
    }

    resources {
      memory = var.infra_node_memory
      cores  = var.infra_node_cores
      core_fraction = var.node_core_fraction
    }

    boot_disk {
      type = var.node_disk_type
      size = var.node_disk_size
    }

    scheduling_policy {
      preemptible = var.preemptible
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = var.infra_node_count
    }
  }

  allocation_policy {
    location {
      zone = var.yc_zone
    }
  }

  deploy_policy {
    max_expansion   = 1
    max_unavailable = 1
  }

  node_version = var.k8s_version

  node_labels = {
    node-role = "infra"
  }

  node_taints = [
    {
      key    = "node-role"
      value  = "infra"
      effect = "NoSchedule"
    }
  ]

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      start_time = "03:00"
      duration   = "3h"
    }
  }
}

# ============================================================================
# Outputs
# ============================================================================
output "cluster_id" {
  description = "Kubernetes cluster ID"
  value       = yandex_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = yandex_kubernetes_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes cluster external endpoint"
  value       = yandex_kubernetes_cluster.this.master[0].external_v4_endpoint
}

output "network_id" {
  description = "VPC network ID"
  value       = yandex_vpc_network.this.id
}

output "subnet_id" {
  description = "VPC subnet ID"
  value       = yandex_vpc_subnet.this.id
}

output "kubeconfig_command" {
  description = "Command to get kubeconfig"
  value       = "yc managed-kubernetes cluster get-credentials ${var.cluster_name} --external"
}

output "kubectl_get_nodes_command" {
  description = "Command to get all nodes with labels"
  value       = "kubectl get node -o wide --show-labels"
}

output "kubectl_get_taints_command" {
  description = "Command to get node taints"
  value       = "kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints"
}
