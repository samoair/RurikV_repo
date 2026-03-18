# ============================================================================
# Variables for Yandex Cloud Kubernetes Cluster with Vault
# ============================================================================

variable "yc_folder_id" {
  description = "Yandex Cloud folder ID"
  type        = string
}

variable "yc_cloud_id" {
  description = "Yandex Cloud cloud ID"
  type        = string
  default     = null
}

variable "yc_zone" {
  description = "Yandex Cloud availability zone"
  type        = string
  default     = "ru-central1-a"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "vault-cluster"
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32"
}

# ============================================================================
# Network Configuration
# ============================================================================
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "vault-network"
}

variable "subnet_name" {
  description = "Name of the VPC subnet"
  type        = string
  default     = "vault-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet (must not conflict with k8s service CIDR 10.96.0.0/16)"
  type        = string
  default     = "192.168.2.0/24"
}

# ============================================================================
# Service Accounts
# ============================================================================
variable "k8s_sa_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "k8s-vault-sa"
}

# ============================================================================
# Node Configuration
# ============================================================================
variable "worker_node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_node_count >= 1
    error_message = "Worker node count must be at least 1"
  }
}

variable "infra_node_count" {
  description = "Number of infra nodes (for Vault, Consul)"
  type        = number
  default     = 3

  validation {
    condition     = var.infra_node_count >= 3
    error_message = "Infra node count must be at least 3 for Consul HA"
  }
}

variable "worker_node_memory" {
  description = "Worker node memory in GB"
  type        = number
  default     = 4
}

variable "worker_node_cores" {
  description = "Worker node vCPUs"
  type        = number
  default     = 2
}

variable "infra_node_memory" {
  description = "Infra node memory in GB"
  type        = number
  default     = 4
}

variable "infra_node_cores" {
  description = "Infra node vCPUs"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Node disk size in GB"
  type        = number
  default     = 64

  validation {
    condition     = var.node_disk_size >= 32
    error_message = "Node disk size must be at least 32 GB"
  }
}

variable "node_disk_type" {
  description = "Node disk type"
  type        = string
  default     = "network-ssd"

  validation {
    condition     = contains(["network-hdd", "network-ssd", "network-ssd-nonreplicated"], var.node_disk_type)
    error_message = "Disk type must be one of: network-hdd, network-ssd, network-ssd-nonreplicated"
  }
}

variable "preemptible" {
  description = "Use preemptible instances (cheaper but can be evicted)"
  type        = bool
  default     = true
}

variable "node_core_fraction" {
  description = "Core fraction as percentage (5, 20, 50, or 100)"
  type        = number
  default     = 50

  validation {
    condition     = contains([5, 20, 50, 100], var.node_core_fraction)
    error_message = "Core fraction must be one of: 5, 20, 50, 100"
  }
}
