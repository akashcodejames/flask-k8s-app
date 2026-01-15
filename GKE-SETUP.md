# GKE Cluster Setup Guide

This comprehensive guide walks you through setting up a Google Kubernetes Engine (GKE) cluster for deploying your Flask K8s application.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [GCP Account Setup](#gcp-account-setup)
3. [Install and Configure gcloud CLI](#install-and-configure-gcloud-cli)
4. [Enable Required APIs](#enable-required-apis)
5. [Create GKE Cluster](#create-gke-cluster)
6. [Install Ingress Controller](#install-ingress-controller)
7. [Verify Installation](#verify-installation)
8. [Configure kubectl Context](#configure-kubectl-context)
9. [Next Steps](#next-steps)

---

## Prerequisites

Before you begin, ensure you have:

- A Google Cloud Platform (GCP) account
- Billing enabled on your GCP account
- Basic knowledge of Kubernetes concepts
- Terminal access (macOS, Linux, or Windows with WSL)
- Internet connection

---

## GCP Account Setup

### Step 1: Create a GCP Account

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Sign in with your Google account
3. If you're a new user, you'll get **$300 in free credits** valid for 90 days

### Step 2: Create a New Project

```bash
# Option 1: Create project via gcloud (after installing gcloud CLI)
gcloud projects create flask-k8s-production --name="Flask K8s Production"

# Option 2: Create via Console
```

**Via Console:**
1. Navigate to [GCP Console](https://console.cloud.google.com/)
2. Click the project dropdown at the top
3. Click **"New Project"**
4. Enter project details:
   - **Project Name**: `Flask K8s Production`
   - **Project ID**: `flask-k8s-production` (must be globally unique)
   - **Organization**: (Optional) Select if applicable
5. Click **"Create"**

### Step 3: Enable Billing

1. Go to **Billing** → **Account Management**
2. Link a billing account to your project
3. Verify billing is enabled:

```bash
gcloud billing projects describe flask-k8s-production
```

> [!IMPORTANT]
> **Cost Awareness**: GKE clusters incur charges. A basic cluster costs approximately:
> - **GKE Management**: Free for zonal clusters
> - **Compute (nodes)**: ~$0.04/hour per e2-medium instance
> - **Load Balancer**: ~$0.025/hour
> - **Estimated Monthly Cost**: ~$75-100 for small production setup
>
> Always monitor your [billing dashboard](https://console.cloud.google.com/billing)!

---

## Install and Configure gcloud CLI

### Step 1: Install gcloud CLI

**For macOS:**

```bash
# Using Homebrew (recommended)
brew install --cask google-cloud-sdk

# Verify installation
gcloud version
```

**For Linux:**

```bash
# Download and install
curl https://sdk.cloud.google.com | bash

# Restart your shell
exec -l $SHELL

# Verify installation
gcloud version
```

**For Windows:**

1. Download the [Google Cloud SDK installer](https://cloud.google.com/sdk/docs/install)
2. Run the installer and follow the wizard
3. Open a new Command Prompt/PowerShell and verify:

```powershell
gcloud version
```

### Step 2: Initialize gcloud

```bash
# Initialize and authenticate
gcloud init

# Follow the prompts:
# 1. Log in to your Google account
# 2. Select or create a project: flask-k8s-production
# 3. Set default compute region/zone (e.g., asia-south1/asia-south1-a)
```

### Step 3: Set Default Project

```bash
# Set your project as default
export GCP_PROJECT_ID="flask-k8s-production"  # Replace with your project ID
gcloud config set project $GCP_PROJECT_ID

# Verify
gcloud config get-value project
```

### Step 4: Configure Default Region and Zone

```bash
# Set default region (choose closest to your users)
gcloud config set compute/region asia-south1

# Set default zone
gcloud config set compute/zone asia-south1-a

# Verify configuration
gcloud config list
```

**Recommended Regions:**
- **India (Mumbai)**: `asia-south1` - **Best for India** ⭐
- **India (Delhi)**: `asia-south2` - Alternative for North India
- **Singapore**: `asia-southeast1` - Good for Southeast Asia
- **Taiwan**: `asia-east1` - East Asia
- **US East**: `us-east1` (South Carolina)
- **US Central**: `us-central1` (Iowa)
- **Europe**: `europe-west1` (Belgium)

---

## Enable Required APIs

GKE requires several GCP APIs to be enabled:

```bash
# Enable all required APIs in one command
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iamcredentials.googleapis.com

# Verify enabled services
gcloud services list --enabled | grep -E 'container|compute|artifactregistry'
```

**What each API does:**
- `container.googleapis.com` - GKE cluster management
- `compute.googleapis.com` - Compute resources (VMs, networking)
- `artifactregistry.googleapis.com` - Docker image storage
- `cloudresourcemanager.googleapis.com` - Project and IAM management
- `iamcredentials.googleapis.com` - Service account authentication

> [!NOTE]
> Enabling APIs may take 1-2 minutes. Wait for confirmation before proceeding.

---

## Create GKE Cluster

### Option 1: Basic Cluster (Development/Testing)

Perfect for testing and development with minimal cost:

```bash
# Set variables
export CLUSTER_NAME="flask-k8s-cluster"
export REGION="asia-south1"  # Mumbai, India
export ZONE="asia-south1-a"

# Create a basic zonal cluster
gcloud container clusters create $CLUSTER_NAME \
  --zone=$ZONE \
  --num-nodes=2 \
  --machine-type=e2-medium \
  --disk-size=20GB \
  --disk-type=pd-standard \
  --enable-cloud-logging \
  --enable-cloud-monitoring \
  --no-enable-autoupgrade \
  --addons=HorizontalPodAutoscaling,HttpLoadBalancing

# This will take 3-5 minutes...
```

**Configuration breakdown:**
- `--num-nodes=2`: Create 2 worker nodes
- `--machine-type=e2-medium`: 2 vCPU, 4GB RAM per node (~$25/month each)
- `--disk-size=20GB`: 20GB boot disk per node
- `--enable-cloud-logging`: Enable Google Cloud Logging
- `--enable-cloud-monitoring`: Enable Google Cloud Monitoring
- `--addons`: Enable Horizontal Pod Autoscaling and HTTP Load Balancing

### Option 2: Production Cluster (Recommended)

For production workloads with high availability and auto-scaling:

```bash
# Set variables
export CLUSTER_NAME="flask-k8s-prod-cluster"
export REGION="asia-south1"  # Mumbai, India

# Create a regional cluster with auto-scaling
gcloud container clusters create $CLUSTER_NAME \
  --region=$REGION \
  --node-locations=asia-south1-a,asia-south1-b,asia-south1-c \
  --num-nodes=1 \
  --machine-type=e2-medium \
  --disk-size=30GB \
  --disk-type=pd-ssd \
  --enable-autoscaling \
  --min-nodes=1 \
  --max-nodes=3 \
  --enable-autorepair \
  --enable-autoupgrade \
  --maintenance-window-start=2026-01-15T00:00:00Z \
  --maintenance-window-duration=4h \
  --enable-cloud-logging \
  --enable-cloud-monitoring \
  --logging=SYSTEM,WORKLOAD \
  --monitoring=SYSTEM \
  --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
  --workload-pool=$GCP_PROJECT_ID.svc.id.goog \
  --enable-shielded-nodes \
  --shielded-secure-boot \
  --shielded-integrity-monitoring

# This will take 5-8 minutes...
```

**Production configuration breakdown:**
- `--region`: Regional cluster for high availability across zones
- `--node-locations`: Spread nodes across 3 availability zones
- `--enable-autoscaling`: Automatically scale nodes based on load
- `--min-nodes=1 --max-nodes=3`: Scale from 1 to 3 nodes per zone
- `--enable-autorepair`: Auto-repair unhealthy nodes
- `--enable-autoupgrade`: Auto-upgrade nodes during maintenance windows
- `--disk-type=pd-ssd`: Use faster SSD disks
- `--workload-pool`: Enable Workload Identity (secure authentication)
- `--enable-shielded-nodes`: Enhanced security features

### Option 3: Custom Cluster via Config File

Create a file `gke-cluster-config.yaml`:

```yaml
# Save this as: gke-cluster-config.yaml
name: flask-k8s-cluster
location: asia-south1-a
initialNodeCount: 2

nodePools:
- name: default-pool
  initialNodeCount: 2
  config:
    machineType: e2-medium
    diskSizeGb: 20
    diskType: pd-standard
    oauthScopes:
    - "https://www.googleapis.com/auth/devstorage.read_only"
    - "https://www.googleapis.com/auth/logging.write"
    - "https://www.googleapis.com/auth/monitoring"
    - "https://www.googleapis.com/auth/servicecontrol"
    - "https://www.googleapis.com/auth/service.management.readonly"
    - "https://www.googleapis.com/auth/trace.append"
    metadata:
      disable-legacy-endpoints: "true"
  management:
    autoUpgrade: false
    autoRepair: true
  autoscaling:
    enabled: true
    minNodeCount: 1
    maxNodeCount: 4

addonsConfig:
  httpLoadBalancing:
    disabled: false
  horizontalPodAutoscaling:
    disabled: false
  gcePersistentDiskCsiDriverConfig:
    enabled: true

loggingService: logging.googleapis.com/kubernetes
monitoringService: monitoring.googleapis.com/kubernetes
```

Then create the cluster:

```bash
# Note: gcloud doesn't directly support YAML config files
# Use the gcloud command with parameters instead
# The YAML above is for reference/documentation
```

### Verify Cluster Creation

```bash
# Check cluster status
gcloud container clusters list

# Get cluster details
gcloud container clusters describe $CLUSTER_NAME --zone=$ZONE

# Expected output should show:
# - status: RUNNING
# - currentNodeCount: 2 (or your specified count)
# - currentMasterVersion: 1.27.x or higher
```

---

## Install Ingress Controller

You have two options for ingress: **GKE Ingress** (default) or **nginx-ingress**.

### Option 1: GKE Ingress (Default - Already Installed)

GKE Ingress is automatically enabled with the `HttpLoadBalancing` addon. It creates a Google Cloud Load Balancer.

**Verify GKE Ingress is enabled:**

```bash
gcloud container clusters describe $CLUSTER_NAME \
  --zone=$ZONE \
  --format="get(addonsConfig.httpLoadBalancing)"

# Output should be: {}
# (Empty object means it's enabled, null means disabled)
```

**Pros:**
- Integrated with Google Cloud Load Balancer
- Automatic SSL certificate management with Google-managed certificates
- Built-in DDoS protection
- No manual installation needed

**Cons:**
- Limited customization compared to nginx
- Takes longer to provision (5-10 minutes)
- More expensive (~$20/month per load balancer)

### Option 2: nginx-ingress Controller (Recommended for Flexibility)

For more control and faster iteration during development:

```bash
# Get credentials for kubectl
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE

# Add Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install nginx-ingress controller
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalTrafficPolicy=Local \
  --set controller.publishService.enabled=true

# Wait for external IP assignment (takes 2-3 minutes)
kubectl --namespace ingress-nginx get services -o wide -w nginx-ingress-ingress-nginx-controller
```

**Verify nginx-ingress installation:**

```bash
# Check pod status
kubectl get pods -n ingress-nginx

# Get external IP (save this for DNS configuration)
kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller
```

You should see output like:
```
NAME                                     TYPE           EXTERNAL-IP
nginx-ingress-ingress-nginx-controller   LoadBalancer   35.x.x.x
```

> [!TIP]
> **Save the EXTERNAL-IP** - You'll need it for DNS configuration and accessing your application!

---

## Verify Installation

### Step 1: Get Cluster Credentials

```bash
# Configure kubectl to use your GKE cluster
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE

# Verify current context
kubectl config current-context

# Expected: gke_flask-k8s-production_asia-south1-a_flask-k8s-cluster
```


### Step 2: Check Cluster Info


```bash
# View cluster information
kubectl cluster-info

# List all nodes
kubectl get nodes -o wide

# Check node resource usage
kubectl top nodes
```


### Step 3: Verify System Pods

```bash
# Check kube-system namespace
kubectl get pods -n kube-system

# All pods should be in Running state
# Key pods to verify:
# - kube-dns-* (DNS service)
# - metrics-server-* (metrics collection)
# - event-exporter-* (event logging)
```


### Step 4: Test Basic Deployment

```bash
# Create a test deployment
kubectl create deployment nginx --image=nginx:alpine

# Expose it
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Wait for external IP
kubectl get svc nginx --watch

# Test access (replace with actual external IP)
curl http://<EXTERNAL-IP>

# Cleanup test
kubectl delete deployment nginx
kubectl delete service nginx
```

---

## Configure kubectl Context

### Set Default Namespace

```bash
# Create and set default namespace for your app
kubectl create namespace flask-app
kubectl config set-context --current --namespace=flask-app

# Verify
kubectl config view --minify | grep namespace:
```

### Multiple Clusters Management

If you have multiple clusters:

```bash
# List all contexts
kubectl config get-contexts

# Switch between clusters
kubectl config use-context gke_flask-k8s-production_asia-south1-a_flask-k8s-cluster

# Rename context for easier switching
kubectl config rename-context \
  gke_flask-k8s-production_asia-south1-a_flask-k8s-cluster \
  gke-prod
```

---

## Next Steps

✅ **GKE Cluster is now ready!**

Continue with:

1. **[Artifact Registry Setup](./ARTIFACT-REGISTRY-SETUP.md)** - Set up Docker image repository
2. **[Application Deployment](./GKE-DEPLOYMENT-GUIDE.md)** - Deploy your Flask app to GKE
3. **[GitLab CI/CD Setup](./GKE-GITLAB-CI-CD-GUIDE.md)** - Automate deployments

---

## Useful Commands

```bash
# View cluster details
gcloud container clusters describe $CLUSTER_NAME --zone=$ZONE

# Resize cluster
gcloud container clusters resize $CLUSTER_NAME --num-nodes=3 --zone=$ZONE

# Upgrade cluster
gcloud container clusters upgrade $CLUSTER_NAME --zone=$ZONE

# Delete cluster (CAUTION!)
gcloud container clusters delete $CLUSTER_NAME --zone=$ZONE

# View cluster costs
gcloud beta billing accounts list
```

---

## Cost Optimization Tips

1. **Use Preemptible Nodes** for non-production (60-80% cheaper):
   ```bash
   --preemptible
   ```

2. **Right-size your nodes**:
   - Development: `e2-small` (2GB RAM)
   - Production: `e2-medium` (4GB RAM)
   - High traffic: `e2-standard-4` (16GB RAM)

3. **Enable autoscaling**:
   - Scale down to 1 node during off-hours
   - Scale up during peak traffic

4. **Use zonal clusters** instead of regional for development (saves 66% on nodes)

5. **Delete unused load balancers** - they cost $20/month even if idle

---

## Troubleshooting

### Issue: Cluster creation fails with quota errors

```bash
# Check your quotas
gcloud compute project-info describe --project=$GCP_PROJECT_ID

# Request quota increase via Console:
# IAM & Admin → Quotas → Select quota → Request increase
```

### Issue: kubectl cannot connect to cluster

```bash
# Re-fetch credentials
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE --project=$GCP_PROJECT_ID

# Verify kubeconfig
kubectl config view

# Test connection
kubectl cluster-info
```

### Issue: Nodes not starting

```bash
# Check node pool status
gcloud container node-pools list --cluster=$CLUSTER_NAME --zone=$ZONE

# View detailed events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

---

## Additional Resources

- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [GKE Pricing Calculator](https://cloud.google.com/products/calculator)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [GKE Release Notes](https://cloud.google.com/kubernetes-engine/docs/release-notes)

---

**Next Guide**: [Artifact Registry Setup →](./ARTIFACT-REGISTRY-SETUP.md)
