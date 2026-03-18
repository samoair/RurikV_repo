# Kubernetes Vault Homework

This homework demonstrates the setup and configuration of HashiCorp Vault with Consul as a storage backend in a Kubernetes cluster, including integration with External Secrets Operator.

## Prerequisites

- Yandex Cloud account with configured CLI (`yc`)
- `kubectl` installed and configured
- `helm` v3+ installed
- `vault` CLI (optional, for local development)
- Yandex Cloud folder ID

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Yandex Cloud K8s Cluster                 │
│                    (vault-cluster)                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌────────────────────────────────────────────────────┐     │
│  │  Consul (HA mode) - namespace: consul              │     │
│  │  - 3 server replicas                               │     │
│  │  - Raft storage backend                            │     │
│  │  - UI available via LoadBalancer                   │     │
│  └────────────────────────────────────────────────────┘     │
│                          ▲                                  │
│                          │ Storage                          │
│  ┌───────────────────────┴──────────────────────────┐       │
│  │  Vault (HA mode) - namespace: vault              │       │
│  │  - 3 replicas                                    │       │
│  │  - Consul as HA storage backend                  │       │
│  │  - KV secrets engine at /otus                    │       │
│  │  - Kubernetes auth method                        │       │
│  │  - UI available via LoadBalancer                 │       │
│  │                                                  │       │
│  │  Secret: otus/cred                               │       │
│  │    - username: otus                              │       │
│  │    - password: asajkjkahs                        │       │
│  └──────────────────────────────────────────────────┘       │
│                          │                                  │
│                          │ Kubernetes Auth                  │
│  ┌───────────────────────┴──────────────────────────┐       │
│  │  External Secrets Operator - namespace: vault    │       │
│  │  - Fetches secrets from Vault                    │       │
│  │  - Creates K8s secrets from Vault data           │       │
│  │                                                  │       │
│  │  SecretStore: vault-backend                      │       │
│  │    Role: otus                                    │       │
│  │    ServiceAccount: vault-auth                    │       │
│  │                                                  │       │
│  │  ExternalSecret: otus-cred                       │       │
│  │    → Secret: otus-cred                           │       │
│  └──────────────────────────────────────────────────┘       │
│                                                             │
│  Node Groups:                                               │
│  - 3 infra nodes (Consul, Vault)                            │
│  - 2 worker nodes                                           │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
kubernetes-vault/
├── README.md                    # This file
├── terraform/                   # Infrastructure as Code
│   ├── main.tf                  # Main Terraform configuration
│   ├── variables.tf             # Variable definitions
│   └── terraform.tfvars         # Variable values
├── helm/                        # Helm chart values
│   ├── consul-values.yaml        # Consul HA configuration (3 replicas)
│   ├── vault-values.yaml         # Vault HA with Consul storage
│   └── eso-values.yaml           # External Secrets Operator
├── manifests/                   # Kubernetes manifests
│   ├── README.md                # Manifests documentation
│   ├── namespaces.yaml           # consul and vault namespaces
│   ├── vault-auth-rbac.yaml      # SA vault-auth + ClusterRoleBinding
│   ├── otus-policy.hcl           # Vault policy for /otus/cred
│   ├── secretstore.yaml          # SecretStore CRD
│   └── externalsecret.yaml       # ExternalSecret CRD
└── scripts/                     # Installation scripts
    ├── 01-install-consul.sh      # Install Consul HA
    ├── 02-install-vault.sh       # Install Vault HA
    ├── 03-init-vault.sh          # Initialize and unseal Vault
    ├── 04-configure-k8s-auth.sh  # Configure K8s auth in Vault
    └── 05-install-eso.sh         # Install ESO and apply manifests
```

## Step-by-Step Instructions

### 1. Create Kubernetes Cluster with Terraform

```bash
cd terraform

# Initialize Terraform
terraform init

# Apply the configuration
terraform apply

# Get cluster credentials
yc managed-kubernetes cluster get-credentials vault-cluster --external

# Verify cluster
kubectl get nodes
```

**Note:** The cluster will have:
- 3 infra nodes (for Consul and Vault HA)
- 2 worker nodes (for general workloads)

### 2. Install Consul in HA Mode

```bash
cd ../scripts

# Run the Consul installation script
./01-install-consul.sh
```

**What this does:**
- Installs Consul Helm chart with 3 server replicas
- Configures Raft storage backend
- Deploys to `consul` namespace on infra nodes
- Exposes Consul UI via LoadBalancer

**Verify:**
```bash
kubectl get pods -n consul -l app=consul,component=server
kubectl exec -n consul -it consul-0 -- consul members
```

### 3. Install Vault in HA Mode

```bash
# Run the Vault installation script
./02-install-vault.sh
```

**What this does:**
- Installs Vault Helm chart with 3 replicas
- Configures Consul as HA storage backend
- Deploys to `vault` namespace on infra nodes
- Exposes Vault UI via LoadBalancer

**Verify:**
```bash
kubectl get pods -n vault -l app.kubernetes.io/name=vault
```

### 4. Initialize and Unseal Vault

```bash
# Run the Vault initialization script
./03-init-vault.sh
```

**What this does:**
- Initializes Vault (generates unseal keys and root token)
- Saves unseal keys to `vault-init.json`
- Unseals Vault using 3 of 5 keys
- Saves root token to `vault-root-token.txt`
- Enables KV secrets engine at `/otus`
- Creates secret `otus/cred` with `username` and `password`

**IMPORTANT:** Store `vault-init.json` and `vault-root-token.txt` securely!

**Verify:**
```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN=$(cat vault-root-token.txt)
vault kv get otus/cred
```

### 5. Configure Kubernetes Authentication

```bash
# Run the K8s auth configuration script
./04-configure-k8s-auth.sh
```

**What this does:**
- Creates ServiceAccount `vault-auth` in `vault` namespace
- Creates ClusterRoleBinding with `system:auth-delegator` role
- Enables Kubernetes auth method in Vault
- Configures Vault with K8s API host and CA certificate
- Creates Vault policy `otus-policy` (read/list access to `/otus/cred`)
- Creates Vault role `otus` with SA `vault-auth` and policy `otus-policy`

**Manifests applied:**
- `manifests/vault-auth-rbac.yaml`

**Verify:**
```bash
# Check service account
kubectl get sa vault-auth -n vault

# Check Vault role
kubectl exec -n vault <vault-pod> -- vault read auth/kubernetes/role/otus

# Check Vault policy
kubectl exec -n vault <vault-pod> -- vault policy read otus-policy
```

### 6. Install External Secrets Operator

```bash
# Run the ESO installation script
./05-install-eso.sh
```

**What this does:**
- Installs External Secrets Operator via Helm
- Applies all Kubernetes manifests:
  - `namespaces.yaml` - Creates namespaces
  - `vault-auth-rbac.yaml` - Creates SA and RBAC
  - `secretstore.yaml` - Creates SecretStore CRD
  - `externalsecret.yaml` - Creates ExternalSecret CRD
- Verifies SecretStore is ready
- Verifies ExternalSecret synced successfully

**Manifests applied:**
- `manifests/namespaces.yaml`
- `manifests/vault-auth-rbac.yaml`
- `manifests/secretstore.yaml`
- `manifests/externalsecret.yaml`

**Verify:**
```bash
# Check SecretStore
kubectl get secretstore -n vault
kubectl describe secretstore vault-backend -n vault

# Check ExternalSecret
kubectl get externalsecret -n vault
kubectl describe externalsecret otus-cred -n vault

# Check the created secret
kubectl get secret otus-cred -n vault -o yaml

# Verify secret contents
kubectl get secret otus-cred -n vault -o jsonpath='{.data}' | jq
```

## Expected Output

### Final Secret
After successful completion, you should have a secret `otus-cred` in the `vault` namespace:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: otus-cred
  namespace: vault
type: Opaque
data:
  username: b3R1cQ==  # otus
  password: YXNhampramFocw==  # asajkjkahs
```

## Verification Checklist

- [ ] Kubernetes cluster created with Terraform
- [ ] 3 infra nodes and 2 worker nodes running
- [ ] Consul installed with 3 server replicas (HA mode)
- [ ] Vault installed with 3 replicas using Consul storage
- [ ] Vault initialized and unsealed
- [ ] KV secrets engine enabled at `/otus`
- [ ] Secret `otus/cred` created with username and password
- [ ] ServiceAccount `vault-auth` created
- [ ] ClusterRoleBinding with `system:auth-delegator` created
- [ ] Kubernetes auth method enabled in Vault
- [ ] Vault policy `otus-policy` created
- [ ] Vault role `otus` created with SA and policy
- [ ] External Secrets Operator installed
- [ ] SecretStore `vault-backend` created and ready
- [ ] ExternalSecret `otus-cred` created and synced
- [ ] Kubernetes secret `otus-cred` exists with correct values

## Cleanup

```bash
# Delete ESO and manifests
helm uninstall external-secrets -n vault
kubectl delete -f ../manifests/

# Uninstall Vault
helm uninstall vault -n vault

# Uninstall Consul
helm uninstall consul -n consul

# Delete namespaces
kubectl delete namespace vault consul

# Destroy Terraform resources
cd ../terraform
terraform destroy
```

## Files for Homework Submission

### Terraform
- `terraform/main.tf` - Cluster configuration
- `terraform/variables.tf` - Variable definitions
- `terraform/terraform.tfvars` - Variable values

### Helm Values
- `helm/consul-values.yaml` - Consul HA configuration (3 replicas)
- `helm/vault-values.yaml` - Vault HA with Consul storage
- `helm/eso-values.yaml` - External Secrets Operator configuration

### Installation Commands
```bash
# Consul installation
helm install consul hashicorp/consul -n consul --create-namespace \
  -f helm/consul-values.yaml

# Vault installation
helm install vault hashicorp/vault -n vault --create-namespace \
  -f helm/vault-values.yaml

# ESO installation
helm install external-secrets external-secrets/external-secrets \
  -n vault --create-namespace -f helm/eso-values.yaml
```

### Kubernetes Manifests
- `manifests/namespaces.yaml`
- `manifests/vault-auth-rbac.yaml` - ServiceAccount and ClusterRoleBinding
- `manifests/otus-policy.hcl` - Vault policy
- `manifests/secretstore.yaml` - SecretStore CRD
- `manifests/externalsecret.yaml` - ExternalSecret CRD

### Screenshots Required
- ArgoCD or kubectl showing pods in consul namespace (3 Consul servers)
- ArgoCD or kubectl showing pods in vault namespace (3 Vault pods)
- Consul UI with cluster members
- Vault UI showing HA status
- Vault secret `otus/cred` contents
- SecretStore status showing Ready
- ExternalSecret status showing Synced
- Kubernetes secret `otus-cred` with decoded values
