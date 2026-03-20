# ─── Yandex Cloud ────────────────────────────────────────────────────────────

variable "yc_cloud_id" {
  description = "Yandex Cloud ID"
  type        = string
  default     = ""
}

variable "yc_folder_id" {
  description = "Yandex Cloud folder ID"
  type        = string
}

variable "zone" {
  description = "Yandex Cloud availability zone"
  type        = string
  default     = "ru-central1-a"
}

# ─── Cluster ─────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Cluster name prefix"
  type        = string
  default     = "prod"
}

variable "image_id" {
  description = "Ubuntu 22.04 LTS image ID in Yandex Cloud"
  type        = string
  default     = "fd8jb8872l222i8afjgp" # Ubuntu 22.04 LTS
}

variable "platform_id" {
  description = "VM platform type"
  type        = string
  default     = "standard-v3"
}

# ─── Network ─────────────────────────────────────────────────────────────────

variable "network_name" {
  description = "VPC network name"
  type        = string
  default     = "prod-network"
}

variable "subnet_name" {
  description = "VPC subnet name"
  type        = string
  default     = "prod-subnet"
}

variable "subnet_cidr" {
  description = "VPC subnet CIDR (must not overlap with 10.96.0.0/12 or 10.244.0.0/16)"
  type        = string
  default     = "192.168.10.0/24"
}

# ─── Service Account ─────────────────────────────────────────────────────────

variable "sa_name" {
  description = "Service account name"
  type        = string
  default     = "k8s-prod-sa"
}

# ─── Master ──────────────────────────────────────────────────────────────────

variable "master_cores" {
  description = "Master node vCPUs"
  type        = number
  default     = 2
}

variable "master_memory" {
  description = "Master node RAM in GB"
  type        = number
  default     = 8
}

# ─── Workers ─────────────────────────────────────────────────────────────────

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "worker_cores" {
  description = "Worker node vCPUs"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Worker node RAM in GB"
  type        = number
  default     = 8
}

# ─── Disk ────────────────────────────────────────────────────────────────────

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 64
}

variable "disk_type" {
  description = "Disk type"
  type        = string
  default     = "network-ssd"
}

# ─── SSH ─────────────────────────────────────────────────────────────────────

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
