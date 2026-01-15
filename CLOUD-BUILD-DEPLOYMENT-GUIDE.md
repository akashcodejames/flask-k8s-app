# Complete GCP Cloud Build + GKE Deployment Guide

**A step-by-step guide to deploy your Flask K8s application using GCP Cloud Build, Artifact Registry, GKE, and GitLab CI/CD in India region.**

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Part 1: GCP Initial Setup](#part-1-gcp-initial-setup)
4. [Part 2: GKE Cluster Setup](#part-2-gke-cluster-setup)
5. [Part 3: Artifact Registry Setup](#part-3-artifact-registry-setup)
6. [Part 4: Cloud Build Configuration](#part-4-cloud-build-configuration)
7. [Part 5: Service Account Setup](#part-5-service-account-setup)
8. [Part 6: GitLab CI/CD Configuration](#part-6-gitlab-cicd-configuration)
9. [Part 7: First Time Deployment](#part-7-first-time-deployment)
10. [Part 8: Rollout Updates](#part-8-rollout-updates)
11. [Command Reference](#command-reference)
12. [Troubleshooting](#troubleshooting)

---

## Overview

### Architecture

```
GitLab Repository
      │
      ├─ Push Code
      ▼
GitLab CI/CD Pipeline
      │
      ├─ Trigger Cloud Build
      ▼
GCP Cloud Build
      │
      ├─ Build Docker Images
      ├─ Push to Artifact Registry
      ▼
Artifact Registry (India - Mumbai)
      │
      └─ Images: backend:tag, frontend:tag
      
GitLab CI/CD (continued)
      │
      ├─ Update K8s Manifests
      ├─ Deploy to GKE
      ▼
GKE Cluster (India - Mumbai)
      │
      ├─ Backend Pods (2 replicas)
      ├─ Frontend Pods (1 replica)
      ▼
Google Cloud Load Balancer
      │
      └─ ssfuture.store (with SSL)
```

### Why Cloud Build Instead of GitLab Docker?

**Advantages:**
1. **No Docker-in-Docker complexity** - Cloud Build handles it natively
2. **Better caching** - Cloud Build caches layers efficiently in GCP
3. **Faster builds** - Closer to Artifact Registry (same region)
4. **Cost-effective** - 120 free build-minutes/day
5. **Native GCP integration** - Better IAM and monitoring

---

## Prerequisites

Before starting, ensure you have:

- [ ] Google Cloud Platform account (with billing enabled)
- [ ] GitLab account and repository
- [ ] Domain name (you have: `ssfuture.store`)
- [ ] Local machine with:
  - [ ] `gcloud` CLI installed
  - [ ] `kubectl` installed
  - [ ] Git installed
- [ ] Basic knowledge of:
  - [ ] Kubernetes concepts
  - [ ] Docker basics
  - [ ] GitLab CI/CD

---

## Part 1: GCP Initial Setup

### Step 1.1: Create GCP Project

```bash
# Set your project ID (must be globally unique)
export PROJECT_ID="flask-k8s-production"

# Create new project
gcloud projects create $PROJECT_ID --name="Flask K8s Production"
```

**Explanation:**
- `gcloud projects create`: Creates a new GCP project
- `$PROJECT_ID`: Your unique project identifier
- `--name`: Human-readable project name

**Expected Output:**
```
Create in progress for [https://cloudresourcemanager.googleapis.com/v1/projects/flask-k8s-production].
Waiting for [operations/cp.xxx] to finish...done.
```

### Step 1.2: Set Default Project

```bash
# Set as default project for all gcloud commands
gcloud config set project $PROJECT_ID

# Verify
gcloud config get-value project
```

**Explanation:**
- `gcloud config set project`: Sets the active project for all future commands
- This avoids needing `--project` flag on every command

**Expected Output:**
```
flask-k8s-production
```

### Step 1.3: Enable Billing

```bash
# List billing accounts
gcloud billing accounts list

# Link billing account to project (replace BILLING_ACCOUNT_ID)
export BILLING_ACCOUNT_ID="YOUR-BILLING-ACCOUNT-ID"
gcloud billing projects link $PROJECT_ID \
  --billing-account=$BILLING_ACCOUNT_ID
```

**Explanation:**
- GCP requires billing to be enabled for most services
- You can also enable billing via Console: https://console.cloud.google.com/billing

**Note:** If you don't have a billing account, create one at https://console.cloud.google.com/billing

### Step 1.4: Enable Required APIs

```bash
# Enable all necessary APIs
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sourcerepo.googleapis.com

#Wait for enablement (takes 1-2 minutes)
sleep 60

# Verify APIs are enabled
gcloud services list --enabled | grep -E 'container|compute|artifact|cloudbuild'
```

**API Explanations:**
- `container.googleapis.com` - **GKE**: Kubernetes cluster management
- `compute.googleapis.com` - **Compute Engine**: VMs for cluster nodes
- `artifactregistry.googleapis.com` - **Artifact Registry**: Docker image storage
- `cloudbuild.googleapis.com` - **Cloud Build**: Build Docker images
- `cloudresourcemanager.googleapis.com` - **Resource Manager**: Project/IAM management
- `iam.googleapis.com` - **IAM**: Permission management
- `iamcredentials.googleapis.com` - **IAM Credentials**: Service account tokens
- `sourcerepo.googleapis.com` - **Source Repositories**: Git repo integration (optional)

**Expected Output:**
```
container.googleapis.com          Kubernetes Engine API
compute.googleapis.com            Compute Engine API
artifactregistry.googleapis.com   Artifact Registry API
cloudbuild.googleapis.com         Cloud Build API
```

---

## Part 2: GKE Cluster Setup

### Step 2.1: Set Variables

```bash
# India (Mumbai) region configuration
export REGION="asia-south1"
export ZONE="asia-south1-a"
export CLUSTER_NAME="flask-k8s-cluster"
export MACHINE_TYPE="e2-medium"
export NUM_NODES="2"
```

**Variable Explanations:**
- `REGION`: GCP region (`asia-south1` = Mumbai, India)
- `ZONE`: Specific zone within region (a, b, or c)
- `CLUSTER_NAME`: Your GKE cluster name
- `MACHINE_TYPE`: Node machine type (2 vCPU, 4GB RAM = ~$25/month each)
- `NUM_NODES`: Number of worker nodes

### Step 2.2: Create GKE Cluster

```bash
# Create zonal cluster (recommended for development/small production)
gcloud container clusters create $CLUSTER_NAME \
  --zone=$ZONE \
  --num-nodes=$NUM_NODES \
  --machine-type=$MACHINE_TYPE \
  --disk-type=pd-standard \
  --disk-size=20GB \
  --enable-cloud-logging \
  --enable-cloud-monitoring \
  --enable-autoscaling \
  --min-nodes=1 \
  --max-nodes=4 \
  --addons=HorizontalPodAutoscaling,HttpLoadBalancing \
  --workload-pool=$PROJECT_ID.svc.id.goog \
  --enable-shielded-nodes
```

**Command Breakdown:**

| Flag | Purpose | Why? |
|------|---------|------|
| `--zone=$ZONE` | Create in Mumbai zone | Low latency for India users |
| `--num-nodes=2` | Start with 2 nodes | Handles 3 pods (2 backend + 1 frontend) |
| `--machine-type=e2-medium` | 2vCPU, 4GB RAM | Good for small apps, ~$50/month |
| `--disk-size=20GB` | Boot disk size | Sufficient for OS + containers |
| `--enable-cloud-logging` | Send logs to Cloud Logging | Centralized log management |
| `--enable-cloud-monitoring` | Send metrics to Cloud Monitoring | Resource monitoring, alerts |
| `--enable-autoscaling` | Auto-add/remove nodes | Scale based on load |
| `--min-nodes=1` | Minimum nodes | Cost savings during low traffic |
| `--max-nodes=4` | Maximum nodes | Handle traffic spikes |
| `--addons=...` | Enable features | HPA (auto-scale pods), Load Balancer |
| `--workload-pool=...` | Enable Workload Identity | Secure service account auth |
| `--enable-shielded-nodes` | Security features | Boot integrity, vTPM |

**Expected Output:**
```
Creating cluster flask-k8s-cluster in asia-south1-a... 
Creating cluster...done.
Created [https://container.googleapis.com/v1/projects/flask-k8s-production/zones/asia-south1-a/clusters/flask-k8s-cluster].
```

**Time:** ~5-7 minutes

### Step 2.3: Get Cluster Credentials

```bash
# Configure kubectl to use your cluster
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT_ID
```

**Explanation:**
- Downloads cluster credentials
- Updates `~/.kube/config` with cluster details
- Sets the current context to your cluster

**Expected Output:**
```
Fetching cluster endpoint and auth data.
kubeconfig entry generated for flask-k8s-cluster.
```

### Step 2.4: Verify Cluster

```bash
# Check cluster connection
kubectl cluster-info

# List nodes
kubectl get nodes

# Check node details
kubectl get nodes -o wide
```

**Expected Output:**
```
NAME                                        STATUS   ROLES    AGE   VERSION
gke-flask-k8s-cluster-default-pool-xxx...   Ready    <none>   2m    v1.27.x
gke-flask-k8s-cluster-default-pool-yyy...   Ready    <none>   2m    v1.27.x
```

---

## Part 3: Artifact Registry Setup

### Step 3.1: Create Repository

```bash
# Create Docker repository in Mumbai
export REPO_NAME="flask-repo"

gcloud artifacts repositories create $REPO_NAME \
  --repository-format=docker \
  --location=$REGION \
  --description="Flask K8s application images"
```

**Explanation:**
- `--repository-format=docker`: For Docker/OCI images
- `--location=$REGION`: Same region as GKE (free data transfer, low latency)
- `flask-repo`: Your repository name (matches your K8s manifests)

**Expected Output:**
```
Create request issued for: [flask-repo]
Waiting for operation [operations/xxx] to complete...done.
Created repository [flask-repo].
```

### Step 3.2: Verify Repository

```bash
# List repositories
gcloud artifacts repositories list --location=$REGION

# Get repository details
gcloud artifacts repositories describe $REPO_NAME \
  --location=$REGION
```

**Expected Output:**
```
name: projects/flask-k8s-production/locations/asia-south1/repositories/flask-repo
format: DOCKER
state: ACTIVE
```

### Step 3.3: Configure Docker Authentication (Local Only)

```bash
# Configure Docker to authenticate with Artifact Registry
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```

**Explanation:**
- Adds Artifact Registry to Docker's credential helpers
- Allows `docker push` to Artifact Registry
- **Note:** This is for local testing only. Cloud Build doesn't need this.

**Expected Output:**
```
{
  "credHelpers": {
    "asia-south1-docker.pkg.dev": "gcloud"
  }
}
```

---

## Part 4: Cloud Build Configuration

### Step 4.1: Create Cloud Build Configuration Files

Cloud Build uses a `cloudbuild.yaml` file to define build steps.

**Create `cloudbuild-backend.yaml`:**

```bash
cat > cloudbuild-backend.yaml << 'EOF'
steps:
  # Build the Docker image
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-t'
      - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/backend:${SHORT_SHA}'
      - '-t'
      - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/backend:latest'
      - '-f'
      - 'backend/Dockerfile'
      - './backend'
    id: 'build-backend'

  # Push the image to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/backend:${SHORT_SHA}'
    id: 'push-backend-sha'
    waitFor: ['build-backend']

  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/backend:latest'
    id: 'push-backend-latest'
    waitFor: ['build-backend']

images:
  - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/backend:${SHORT_SHA}'
  - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/backend:latest'

substitutions:
  _REGION: 'asia-south1'
  _REPO_NAME: 'flask-repo'

options:
  machineType: 'N1_HIGHCPU_8'
  logging: CLOUD_LOGGING_ONLY
  
timeout: '1200s'  # 20 minutes
EOF
```

**File Breakdown:**

| Section | Purpose |
|---------|---------|
| `steps` | Sequential build commands |
| `name: 'gcr.io/cloud-builders/docker'` | Use pre-built Docker builder image |
| `args: ['build', '-t', ...]` | Docker build command arguments |
| `${SHORT_SHA}` | Git commit SHA (first 7 chars) - auto-provided by Cloud Build |
| `${PROJECT_ID}` | Your GCP project ID - auto-provided |
| `waitFor` | Wait for previous step to complete |
| `images` | Images to store in build metadata |
| `substitutions` | Custom variables |
| `machineType` | Builder VM size (N1_HIGHCPU_8 = 8 vCPUs) |
| `timeout` | Maximum build time |

**Create `cloudbuild-frontend.yaml`:**

```bash
cat > cloudbuild-frontend.yaml << 'EOF'
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-t'
      - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/frontend:${SHORT_SHA}'
      - '-t'
      - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/frontend:latest'
      - '-f'
      - 'frontend/Dockerfile'
      - './frontend'
    id: 'build-frontend'

  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/frontend:${SHORT_SHA}'
    id: 'push-frontend-sha'
    waitFor: ['build-frontend']

  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/frontend:latest'
    id: 'push-frontend-latest'
    waitFor: ['build-frontend']

images:
  - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/frontend:${SHORT_SHA}'
  - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/frontend:latest'

substitutions:
  _REGION: 'asia-south1'
  _REPO_NAME: 'flask-repo'

options:
  machineType: 'N1_HIGHCPU_8'
  logging: CLOUD_LOGGING_ONLY
  
timeout: '1200s'
EOF
```

### Step 4.2: Test Cloud Build Locally (Optional)

```bash
# Submit backend build
gcloud builds submit \
  --config=cloudbuild-backend.yaml \
  --region=$REGION \
  .

# Submit frontend build
gcloud builds submit \
  --config=cloudbuild-frontend.yaml \
  --region=$REGION \
  .
```

**Explanation:**
- `gcloud builds submit`: Triggers a Cloud Build
- `--config`: Path to cloudbuild.yaml
- `--region`: Where to run the build (Mumbai)
- `.`: Source code directory (current directory)

**Expected Output:**
```
Creating temporary tarball archive of X file(s) totalling Y MB before compression.
Uploading tarball of [.] to [gs://...]
...
BUILD SUCCESS
```

**Time:** ~2-5 minutes per image

---

## Part 5: Service Account Setup

### Step 5.1: Create Service Account for GitLab

```bash
# Set service account name
export SA_NAME="gitlab-deployer"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Create service account
gcloud iam service-accounts create $SA_NAME \
  --display-name="GitLab CI/CD Deployer" \
  --description="Service account for GitLab CI/CD pipelines"
```

**Explanation:**
- Service accounts are used by applications (like GitLab) to authenticate to GCP
- No username/password - uses cryptographic keys

**Expected Output:**
```
Created service account [gitlab-deployer].
```

### Step 5.2: Grant Required Permissions

```bash
# 1. Cloud Build Editor - Trigger builds
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/cloudbuild.builds.editor"

# 2. Artifact Registry Writer - Push images (Cloud Build needs this)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/artifactregistry.writer"

# 3. GKE Developer - Deploy to cluster
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/container.developer"

# 4. Service Account User - Use Cloud Build default service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/iam.serviceAccountUser"

# 5. Storage Object Viewer - Read Cloud Build logs
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/storage.objectViewer"
```

**Permission Explanations:**

| Role | Purpose | Why Needed? |
|------|---------|-------------|
| `cloudbuild.builds.editor` | Create/view builds | GitLab triggers Cloud Build |
| `artifactregistry.writer` | Push Docker images | Store built images |
| `container.developer` | Deploy to GKE | Update K8s deployments |
| `iam.serviceAccountUser` | Impersonate Cloud Build SA | Cloud Build runs as its own SA |
| `storage.objectViewer` | Read build logs/artifacts | Access build outputs |

### Step 5.3: Create and Download Service Account Key

```bash
# Create key file
gcloud iam service-accounts keys create ~/gitlab-deployer-key.json \
  --iam-account=$SA_EMAIL

# View key (you'll use this in GitLab)
cat ~/gitlab-deployer-key.json

# Base64 encode for GitLab variable
cat ~/gitlab-deployer-key.json | base64 > ~/gitlab-deployer-key-base64.txt

# Display encoded key (copy this)
cat ~/gitlab-deployer-key-base64.txt
```

**Explanation:**
- Creates a JSON key file for authentication
- GitLab will use this to authenticate as the service account
- Base64 encoding makes it safer to store in GitLab variables

> **SECURITY WARNING:** 
> - This key grants full access defined by the service account
> - Never commit to Git
> - Store only in GitLab CI/CD variables (masked & protected)
> - Delete local copy after adding to GitLab

**Expected Output:**
```
created key [xxx] of type [json] as [/Users/.../gitlab-deployer-key.json] for [gitlab-deployer@flask-k8s-production.iam.gserviceaccount.com]
```

### Step 5.4: Secure the Key

```bash
# After adding to GitLab, delete local copies
rm ~/gitlab-deployer-key.json
rm ~/gitlab-deployer-key-base64.txt

# Verify deletion
ls -la ~ | grep gitlab-deployer
```

---

## Part 6: GitLab CI/CD Configuration

### Step 6.1: Add GitLab CI/CD Variables

1. Go to your GitLab project
2. Navigate to **Settings** → **CI/CD**
3. Expand **Variables** section
4. Add these variables:

| Variable Name | Value | Masked | Protected | Description |
|--------------|--------|---------|-----------|-------------|
| `GCP_SERVICE_KEY` | Base64 key content | ✅ Yes | ✅ Yes | Service account key |
| `GCP_PROJECT_ID` | `flask-k8s-production` | ❌ No | ❌ No | Your GCP project ID |
| `GCP_REGION` | `asia-south1` | ❌ No | ❌ No | Mumbai region |
| `GCP_ZONE` | `asia-south1-a` | ❌ No | ❌ No | Mumbai zone A |
| `ARTIFACT_REGISTRY_REPO` | `flask-repo` | ❌ No | ❌ No | Your registry name |
| `GKE_CLUSTER_NAME` | `flask-k8s-cluster` | ❌ No | ❌ No | Your cluster name |
| `KUBE_NAMESPACE` | `flask-app` | ❌ No | ❌ No | K8s namespace |

**How to add a variable:**
- Click **"Add variable"**
- Enter key and value
- Check "Mask variable" if needed (for secrets)
- Check "Protect variable" (only available on protected branches)
- Click **"Add variable"**

### Step 6.2: Create `.gitlab-ci.yml`

Create this file in your repository root:

```yaml
stages:
  - build
  - deploy
  - verify

variables:
  # GCP Configuration (from GitLab CI/CD variables)
  # GCP_PROJECT_ID, GCP_REGION, GCP_ZONE, GCP_SERVICE_KEY set in GitLab
  REGISTRY_URL: ${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${ARTIFACT_REGISTRY_REPO}

# Build backend using Cloud Build
build:backend:
  stage: build
  image: google/cloud-sdk:alpine
  before_script:
    # Authenticate to GCP
    - echo $GCP_SERVICE_KEY | base64 -d > ${HOME}/gcp-key.json
    - gcloud auth activate-service-account --key-file ${HOME}/gcp-key.json
    - gcloud config set project $GCP_PROJECT_ID
  script:
    - echo "Building backend using Cloud Build..."
    - |
      gcloud builds submit \
        --config=cloudbuild-backend.yaml \
        --region=$GCP_REGION \
        --substitutions=SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
        .
    - echo "✅ Backend build submitted to Cloud Build"
  after_script:
    - rm -f ${HOME}/gcp-key.json
  only:
    - main
    - develop
  tags:
    - docker

# Build frontend using Cloud Build
build:frontend:
  stage: build
  image: google/cloud-sdk:alpine
  before_script:
    - echo $GCP_SERVICE_KEY | base64 -d > ${HOME}/gcp-key.json
    - gcloud auth activate-service-account --key-file ${HOME}/gcp-key.json
    - gcloud config set project $GCP_PROJECT_ID
  script:
    - echo "Building frontend using Cloud Build..."
    - |
      gcloud builds submit \
        --config=cloudbuild-frontend.yaml \
        --region=$GCP_REGION \
        --substitutions=SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
        .
    - echo "✅ Frontend build submitted to Cloud Build"
  after_script:
    - rm -f ${HOME}/gcp-key.json
  only:
    - main
    - develop
  tags:
    - docker

# Deploy to GKE
deploy:production:
  stage: deploy
  image: google/cloud-sdk:alpine
  environment:
    name: production
    url: https://ssfuture.store
  when: manual  # Requires manual approval
  before_script:
    # Authenticate to GCP
    - echo $GCP_SERVICE_KEY | base64 -d > ${HOME}/gcp-key.json
    - gcloud auth activate-service-account --key-file ${HOME}/gcp-key.json
    - gcloud config set project $GCP_PROJECT_ID
    # Install kubectl
    - gcloud components install kubectl --quiet
    # Get GKE credentials
    - gcloud container clusters get-credentials $GKE_CLUSTER_NAME --zone=$GCP_ZONE
  script:
    - echo "Deploying to GKE cluster..."
    - export IMAGE_TAG=${CI_COMMIT_SHORT_SHA}
    
    # Update deployment manifests with new image tags
    - |
      sed -i "s|image:.*backend:.*|image: $REGISTRY_URL/backend:$IMAGE_TAG|g" k8s/gke/backend-deployment.yaml
      sed -i "s|image:.*frontend:.*|image: $REGISTRY_URL/frontend:$IMAGE_TAG|g" k8s/gke/frontend-deployment.yaml
    
    # Apply all Kubernetes manifests
    - kubectl apply -f k8s/gke/namespace.yaml
    - kubectl apply -f k8s/gke/backend-backendconfig.yaml
    - kubectl apply -f k8s/gke/frontend-backendconfig.yaml
    - kubectl apply -f k8s/gke/backend-deployment.yaml
    - kubectl apply -f k8s/gke/backend-service.yaml
    - kubectl apply -f k8s/gke/frontend-deployment.yaml
    - kubectl apply -f k8s/gke/frontend-service.yaml
    - kubectl apply -f k8s/gke/managed-cert.yaml
    - kubectl apply -f k8s/gke/ingress.yaml
    
    # Wait for rollout
    - kubectl rollout status deployment/backend-deployment -n $KUBE_NAMESPACE --timeout=5m
    - kubectl rollout status deployment/frontend-deployment -n $KUBE_NAMESPACE --timeout=5m
    
    - echo "✅ Deployment complete"
  after_script:
    - rm -f ${HOME}/gcp-key.json
  only:
    - main
  tags:
    - docker

# Verify deployment
verify:deployment:
  stage: verify
  image: google/cloud-sdk:alpine
  before_script:
    - echo $GCP_SERVICE_KEY | base64 -d > ${HOME}/gcp-key.json
    - gcloud auth activate-service-account --key-file ${HOME}/gcp-key.json
    - gcloud config set project $GCP_PROJECT_ID
    - gcloud components install kubectl --quiet
    - gcloud container clusters get-credentials $GKE_CLUSTER_NAME --zone=$GCP_ZONE
  script:
    - echo "Verifying deployment..."
    - kubectl get pods -n $KUBE_NAMESPACE
    - kubectl get svc -n $KUBE_NAMESPACE
    - kubectl get ingress -n $KUBE_NAMESPACE
    - echo "✅ Verification complete"
  after_script:
    - rm -f ${HOME}/gcp-key.json
  only:
    - main
  tags:
    - docker
```

**Pipeline Explanation:**

| Stage | Jobs | Purpose |
|-------|------|---------|
| `build` | `build:backend`, `build:frontend` | Trigger Cloud Build for each image |
| `deploy` | `deploy:production` | Update K8s deployments with new images |
| `verify` | `verify:deployment` | Check deployment status |

**Key Points:**
- `when: manual` - Requires manual approval for production
- `${CI_COMMIT_SHORT_SHA}` - GitLab provides commit SHA
- Images tagged with commit SHA for version tracking
- `after_script` - Always delete the key file

---

## Part 7: First Time Deployment

### Step 7.1: Prepare Your Code

```bash
# Ensure you have all required files in your repository
cd /Users/akashyadav/Desktop/k8s/flask-k8s-app

# Check file structure
tree -L 2
```

**Required files:**
```
.
├── .gitlab-ci.yml
├── cloudbuild-backend.yaml
├── cloudbuild-frontend.yaml
├── backend/
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
├── frontend/
│   ├── Dockerfile
│   └── index.html
└── k8s/gke/
    ├── namespace.yaml
    ├── backend-deployment.yaml
    ├── backend-service.yaml
    ├── backend-backendconfig.yaml
    ├── frontend-deployment.yaml
    ├── frontend-service.yaml
    ├── frontend-backendconfig.yaml
    ├── managed-cert.yaml
    └── ingress.yaml
```

### Step 7.2: Commit and Push to GitLab

```bash
# Add Cloud Build config files
git add cloudbuild-backend.yaml cloudbuild-frontend.yaml

# Add updated GitLab CI/CD config
git add .gitlab-ci.yml

# Commit changes
git commit -m "Add Cloud Build deployment configuration"

# Push to GitLab
git push origin main
```

**Explanation:**
- This triggers the GitLab CI/CD pipeline
- Builds will be submitted to Cloud Build
- Waiting for manual approval for deployment

### Step 7.3: Monitor Cloud Build

1. **GitLab Pipeline:**
   - Go to your GitLab project
   - Click **CI/CD** → **Pipelines**
   - Click on running pipeline
   - Watch build stage

2. **GCP Cloud Build:**
   - Go to https://console.cloud.google.com/cloud-build/builds
   - Select your project
   - See real-time build logs

**Expected Timeline:**
- Build stage: 3-5 minutes (both parallel)
- Deploy stage: Waiting for manual approval

### Step 7.4: Manual Approval and Deploy

1. In GitLab pipeline, click the **play** button (▶️) next to `deploy:production`
2. Deployment will start
3. Monitor logs

**Expected Output:**
```
Deploying to GKE cluster...
namespace/flask-app created
backendconfig.cloud.google.com/backend-config created
deployment.apps/backend-deployment created
service/backend-service created
...
deployment "backend-deployment" successfully rolled out
deployment "frontend-deployment" successfully rolled out
✅ Deployment complete
```

### Step 7.5: Verify Deployment

```bash
# Check pods
kubectl get pods -n flask-app

# Check services
kubectl get svc -n flask-app

# Check ingress
kubectl get ingress -n flask-app
```

**Expected Output:**
```
NAME                                  READY   STATUS    
backend-deployment-xxx                2/2     Running
frontend-deployment-yyy               1/1     Running

NAME               TYPE        CLUSTER-IP      EXTERNAL-IP
backend-service    ClusterIP   10.xx.xx.xx     <none>
frontend-service   ClusterIP   10.xx.xx.xx     <none>

NAME                 HOSTS             ADDRESS         
flask-app-ingress    ssfuture.store    XX.XX.XX.XX
```

### Step 7.6: Configure DNS

1. **Get External IP:**
   ```bash
   kubectl get ingress flask-app-ingress -n flask-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

2. **Update DNS Records:**
   - Go to your domain registrar (where you bought `ssfuture.store`)
   - Add an **A record**:
     - **Name:** `@` (or blank for root domain)
     - **Type:** `A`
     - **Value:** Your external IP
     - **TTL:** `300` or `3600`

3. **Wait for DNS Propagation** (5-30 minutes)
   ```bash
   # Check DNS
   nslookup ssfuture.store
   
   # Or use online tool
   # https://www.whatsmydns.net/
  ```

### Step 7.7: Wait for SSL Certificate

```bash
# Check certificate status
kubectl describe managedcertificate flask-app-cert -n flask-app
```

**Expected Status Progression:**
1. `Provisioning` (0-5 minutes)
2. `ProvisioningCertificate` (5-20 minutes)
3. `Active` (Certificate ready!)

**Full provisioning: 10-30 minutes**

> **IMPORTANT:** Google-managed certificates require:
> - DNS pointing to load balancer IP
> - HTTP/HTTPS accessible
> - Can take up to 60 minutes in some cases

### Step 7.8: Access Your Application

```bash
# Test HTTP (while waiting for HTTPS)
curl http://ssfuture.store

# Test API
curl http://ssfuture.store/api/message

# Once certificate is active
curl https://ssfuture.store
```

**Or open in browser:**
- https://ssfuture.store

---

## Part 8: Rollout Updates

### Step 8.1: Make Code Changes

```bash
# Example: Update backend
cd backend
vi app.py  # Make your changes

# Example: Update frontend
cd frontend
vi index.html  # Make your changes
```

### Step 8.2: Commit and Push

```bash
# Stage changes
git add .

# Commit with descriptive message
git commit -m "feat: Add new feature XYZ"

# Push to trigger pipeline
git push origin main
```

**This triggers:**
1. ✅ Cloud Build creates new images
2. ⏸️ Waits for manual approval
3. ✅ (After approval) Deploys to GKE

### Step 8.3: Monitor Build in Cloud Build

```bash
# List recent builds
gcloud builds list --limit=5 --region=$REGION

# View specific build (get BUILD_ID from above)
gcloud builds describe BUILD_ID --region=$REGION

# Stream logs
gcloud builds log BUILD_ID --region=$REGION --stream
```

**Or in Console:**
- https://console.cloud.google.com/cloud-build/builds

### Step 8.4: Approve Deployment

1. Go to GitLab → CI/CD → Pipelines
2. Click on pipeline
3. Click **play** button (▶️) on `deploy:production`
4. Monitor deployment logs

### Step 8.5: Verify Rolling Update

```bash
# Watch pods being updated
kubectl get pods -n flask-app -w

# Check rollout status
kubectl rollout status deployment/backend-deployment -n flask-app

# View rollout history
kubectl rollout history deployment/backend-deployment -n flask-app
```

**Expected Behavior:**
- Old pods terminate gracefully
- New pods start with new image
- Zero downtime (thanks to rolling update strategy)

**Timeline:**
- Build: 3-5 minutes
- Deploy: 2-3 minutes
- Total: ~5-8 minutes

### Step 8.6: Rollback (If Needed)

```bash
# Rollback to previous version
kubectl rollout undo deployment/backend-deployment -n flask-app

# Or rollback to specific revision
kubectl rollout history deployment/backend-deployment -n flask-app
kubectl rollout undo deployment/backend-deployment --to-revision=2 -n flask-app

# Verify rollback
kubectl rollout status deployment/backend-deployment -n flask-app
```

---

## Command Reference

### GCP Commands

```bash
# Project management
gcloud projects list
gcloud config set project PROJECT_ID

# API management
gcloud services list --enabled
gcloud services enable API_NAME

# Cloud Build
gcloud builds list --limit=10
gcloud builds describe BUILD_ID
gcloud builds cancel BUILD_ID

# Artifact Registry
gcloud artifacts docker images list REGISTRY_URL
gcloud artifacts docker images delete IMAGE_URL
```

### Kubernetes Commands

```bash
# Cluster access
gcloud container clusters get-credentials CLUSTER_NAME --zone=ZONE

# Pod management
kubectl get pods -n flask-app
kubectl describe pod POD_NAME -n flask-app
kubectl logs POD_NAME -n flask-app
kubectl exec -it POD_NAME -n flask-app -- /bin/sh

# Deployment management
kubectl get deployment -n flask-app
kubectl scale deployment/backend-deployment --replicas=3 -n flask-app
kubectl rollout restart deployment/backend-deployment -n flask-app

# Service and Ingress
kubectl get svc -n flask-app
kubectl get ingress -n flask-app
kubectl describe ingress flask-app-ingress -n flask-app

# Certificate
kubectl get managedcertificate -n flask-app
kubectl describe managedcertificate flask-app-cert -n flask-app
```

---

## Troubleshooting

### Issue: Cloud Build fails with "Permission Denied"

**Solution:**
```bash
# Verify Cloud Build service account has permissions
export CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# Get project number
gcloud projects describe $PROJECT_ID --format="value(projectNumber)"

# Grant Artifact Registry Writer
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CB_SA" \
  --role="roles/artifactregistry.writer"
```

### Issue: Git image pull fails in GKE

**Solution:**
```bash
# Verify GKE service account has permissions
export GKE_SA=$(gcloud container clusters describe $CLUSTER_NAME \
  --zone=$ZONE \
  --format="value(nodeConfig.serviceAccount)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$GKE_SA" \
  --role="roles/artifactregistry.reader"
```

### Issue: Managed Certificate stuck in "Provisioning"

**Checklist:**
- [ ] DNS points to load balancer IP
- [ ] Ingress has external IP
- [ ] Domain is accessible via HTTP
- [ ] Wait at least 30 minutes

```bash
# Check ingress
kubectl describe ingress flask-app-ingress -n flask-app

# Check certificate events
kubectl describe managedcertificate flask-app-cert -n flask-app

# Verify DNS
nslookup ssfuture.store
```

### Issue: Pipeline fails at authentication

**Solution:**
```bash
# Verify GitLab variable is set correctly
# In GitLab: Settings → CI/CD → Variables → Check GCP_SERVICE_KEY

# Re-encode key
cat gitlab-deployer-key.json | base64 -w 0 > key-base64.txt

# Update in GitLab
```

---

## Cost Estimation

**Monthly costs (India region):**

| Resource | Configuration | Cost |
|----------|--------------|------|
| GKE Management | Zonal cluster | Free |
| Compute Nodes | 2x e2-medium | ~₹4,000 ($48) |
| Cloud Build | 120 min/day free | ₹0 (within free tier) |
| Artifact Registry | <5GB storage | ₹50 ($0.60) |
| Load Balancer | 1 external IP | ₹1,500 ($18) |
| Network Egress | India users | ₹400 ($5) |
| **Total** | | **~₹6,000/month ($72)** |

**Free Tier:**
- Cloud Build: 120 build-minutes/day
- Artifact Registry: First 0.5GB free

---

## Best Practices

1. **Always tag images with commit SHA** - Easy rollback
2. **Use manual approval for production** - Prevent accidental deploys
3. **Monitor Cloud Build logs** - Catch issues early
4. **Set resource limits** - Prevent pod resource starvation
5. **Use health probes** - Ensure pods are ready before traffic
6. **Enable autoscaling** - Handle traffic spikes
7. **Regular key rotation** - Rotate service account keys every 90 days
8. **Review IAM permissions** - Principle of least privilege

---

## Next Steps

1. **Set up monitoring:**
   - Enable Cloud Monitoring alerts
   - Set up uptime checks

2. **Add environments:**
   - Create staging environment
   - Test deployments in staging first

3. **Implement CI testing:**
   - Add unit tests to pipeline
   - Run tests before build

4. **Database setup:**
   - Add Cloud SQL for persistent data
   - Configure connection in backend

5. **Backup strategy:**
   - Set up Velero for cluster backups
   - Regular resource backups

---

**🎉 Congratulations! Your application is now deployed on GKE with Cloud Build! 🎉**

For issues, refer to [GKE-TROUBLESHOOTING.md](./GKE-TROUBLESHOOTING.md)
