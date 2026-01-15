# Artifact Registry Setup Guide

This guide walks you through setting up Google Artifact Registry to store Docker images for your Flask K8s application.

## Table of Contents

1. [What is Artifact Registry?](#what-is-artifact-registry)
2. [Prerequisites](#prerequisites)
3. [Enable Artifact Registry API](#enable-artifact-registry-api)
4. [Create Artifact Registry Repository](#create-artifact-registry-repository)
5. [Configure Docker Authentication](#configure-docker-authentication)
6. [Build and Push Images](#build-and-push-images)
7. [Verify Images](#verify-images)
8. [Configure IAM Permissions](#configure-iam-permissions)
9. [Image Management](#image-management)
10. [Next Steps](#next-steps)

---

## What is Artifact Registry?

**Artifact Registry** is Google Cloud's service for storing and managing container images and other artifacts. It's the successor to Container Registry and offers:

- **Better Performance**: Faster image pulls from GKE
- **Enhanced Security**: Vulnerability scanning, binary authorization
- **Regional Storage**: Store images close to your cluster
- **IAM Integration**: Fine-grained access control
- **Multi-format Support**: Docker, Maven, npm, Python, etc.

**Pricing:**
- **Storage**: $0.10 per GB/month
- **Network Egress**: Free within same region as GKE
- **Typical Cost**: ~$1-5/month for small projects

---

## Prerequisites

Before starting, ensure you have:

- ✅ GCP project created (from [GKE Setup Guide](./GKE-SETUP.md))
- ✅ gcloud CLI installed and authenticated
- ✅ Docker installed locally
- ✅ Billing enabled on your GCP project

```bash
# Verify prerequisites
gcloud --version
docker --version
gcloud auth list
```

---

## Enable Artifact Registry API

### Step 1: Enable the API

```bash
# Enable Artifact Registry API
gcloud services enable artifactregistry.googleapis.com

# Verify it's enabled
gcloud services list --enabled | grep artifactregistry

# Expected output:
# artifactregistry.googleapis.com  Artifact Registry API
```

### Step 2: Verify Permissions

```bash
# Check if you have necessary permissions
gcloud projects get-iam-policy $GCP_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)"

# You should have one of these roles:
# - roles/artifactregistry.admin
# - roles/editor
# - roles/owner
```

---

## Create Artifact Registry Repository

### Step 1: Set Environment Variables

```bash
# Set your configuration
export GCP_PROJECT_ID="flask-k8s-production"  # Replace with your project ID
export REGION="asia-south1"  # Should match your GKE cluster region (Mumbai, India)
export REPOSITORY_NAME="flask-app-images"
export REPOSITORY_DESCRIPTION="Docker images for Flask K8s application"
```

### Step 2: Create Repository

```bash
# Create a Docker repository
gcloud artifacts repositories create $REPOSITORY_NAME \
  --repository-format=docker \
  --location=$REGION \
  --description="$REPOSITORY_DESCRIPTION"

# This creates a repository at:
# asia-south1-docker.pkg.dev/flask-k8s-production/flask-app-images
```

**Command breakdown:**
- `--repository-format=docker`: For Docker/container images
- `--location=$REGION`: Same region as GKE for faster pulls
- `--description`: Human-readable description

### Step 3: Verify Repository Creation

```bash
# List all repositories
gcloud artifacts repositories list

# Get repository details
gcloud artifacts repositories describe $REPOSITORY_NAME \
  --location=$REGION

# Expected output shows:
# - name: projects/.../repositories/flask-app-images
# - format: DOCKER
# - state: ACTIVE
```

### Step 4: Get Repository URL

```bash
# Your repository URL format is:
# REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY_NAME

# Full URL for your images:
echo "$REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME"

# Example: asia-south1-docker.pkg.dev/flask-k8s-production/flask-app-images
```

> [!IMPORTANT]
> **Save this URL!** You'll use it to tag and push Docker images.

---

## Configure Docker Authentication

You need to configure Docker to authenticate with Artifact Registry.

### Method 1: gcloud Credential Helper (Recommended)

This is the easiest method for local development:

```bash
# Configure Docker to use gcloud as a credential helper
gcloud auth configure-docker $REGION-docker.pkg.dev

# Example for asia-south1:
gcloud auth configure-docker asia-south1-docker.pkg.dev
```

This adds configuration to your `~/.docker/config.json`:

```json
{
  "credHelpers": {
    "asia-south1-docker.pkg.dev": "gcloud"
  }
}
```

**Verify authentication:**

```bash
# Test by pulling a public image through Artifact Registry
docker pull $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/test:latest 2>&1 | head -5

# You should see authentication happening (even if image doesn't exist)
```

### Method 2: Service Account Key (For CI/CD)

For GitLab CI/CD pipelines, use a service account:

```bash
# Create service account
gcloud iam service-accounts create gitlab-deployer \
  --display-name="GitLab CI/CD Deployer" \
  --description="Service account for GitLab CI/CD to push images and deploy to GKE"

# Grant Artifact Registry Writer permission
gcloud artifacts repositories add-iam-policy-binding $REPOSITORY_NAME \
  --location=$REGION \
  --member="serviceAccount:gitlab-deployer@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Grant GKE Developer permission (for deployments)
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:gitlab-deployer@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

# Create and download key (save this securely!)
gcloud iam service-accounts keys create ~/gitlab-deployer-key.json \
  --iam-account=gitlab-deployer@$GCP_PROJECT_ID.iam.gserviceaccount.com

# View the key location
ls -lh ~/gitlab-deployer-key.json
```

> [!CAUTION]
> **Security Warning**: The JSON key file grants full access. Keep it secure!
> - Never commit it to Git
> - Store it in GitLab CI/CD variables (masked and protected)
> - Rotate keys regularly (every 90 days recommended)

**Use in GitLab CI/CD:**

```yaml
# In .gitlab-ci.yml
variables:
  GCP_SERVICE_KEY: $GCP_SERVICE_KEY  # Set in GitLab CI/CD variables

before_script:
  - echo $GCP_SERVICE_KEY | base64 -d > ${HOME}/gcp-key.json
  - gcloud auth activate-service-account --key-file ${HOME}/gcp-key.json
  - gcloud auth configure-docker $REGION-docker.pkg.dev
```

### Method 3: Workload Identity (Most Secure - Advanced)

For production GitLab runners running on GKE:

```bash
# This is covered in detail in GKE-GITLAB-CI-CD-GUIDE.md
# Enables authentication without needing key files
```

---

## Build and Push Images

### Step 1: Build Docker Images Locally

```bash
# Navigate to your project
cd /Users/akashyadav/Desktop/k8s/flask-k8s-app

# Set variables
export GCP_PROJECT_ID="flask-k8s-production"
export REGION="asia-south1"
export REPOSITORY_NAME="flask-app-images"
export IMAGE_TAG="v1.0.0"  # Or use git commit SHA

# Build backend image
docker build -t flask-backend:$IMAGE_TAG ./backend

# Build frontend image
docker build -t flask-frontend:$IMAGE_TAG ./frontend

# Verify images
docker images | grep flask
```

### Step 2: Tag Images for Artifact Registry

```bash
# Tag backend image
docker tag flask-backend:$IMAGE_TAG \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:$IMAGE_TAG

# Also tag as 'latest'
docker tag flask-backend:$IMAGE_TAG \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:latest

# Tag frontend image
docker tag flask-frontend:$IMAGE_TAG \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-frontend:$IMAGE_TAG

# Tag as 'latest'
docker tag flask-frontend:$IMAGE_TAG \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-frontend:latest

# Verify tags
docker images | grep pkg.dev
```

### Step 3: Push Images to Artifact Registry

```bash
# Push backend images
docker push $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:$IMAGE_TAG
docker push $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:latest

# Push frontend images
docker push $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-frontend:$IMAGE_TAG
docker push $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-frontend:latest
```

**Example output:**
```
The push refers to repository [asia-south1-docker.pkg.dev/flask-k8s-production/flask-app-images/flask-backend]
a1b2c3d4e5f6: Pushed
...
v1.0.0: digest: sha256:abc123... size: 1234
```

### Step 4: Automated Build and Push Script

Create a helper script for easier workflow:

```bash
# Create scripts directory if it doesn't exist
mkdir -p scripts

# Create the build-push script
cat > scripts/build-push-to-registry.sh << 'EOF'
#!/bin/bash
set -e

# Configuration
export GCP_PROJECT_ID="${GCP_PROJECT_ID:-flask-k8s-production}"
export REGION="${REGION:-asia-south1}"
export REPOSITORY_NAME="${REPOSITORY_NAME:-flask-app-images}"
export IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔨 Building and pushing images to Artifact Registry${NC}"
echo "Project: $GCP_PROJECT_ID"
echo "Region: $REGION"
echo "Repository: $REPOSITORY_NAME"
echo "Tag: $IMAGE_TAG"
echo ""

# Build backend
echo -e "${GREEN}Building backend...${NC}"
docker build -t flask-backend:$IMAGE_TAG ./backend

# Build frontend
echo -e "${GREEN}Building frontend...${NC}"
docker build -t flask-frontend:$IMAGE_TAG ./frontend

# Tag and push backend
echo -e "${GREEN}Pushing backend to Artifact Registry...${NC}"
docker tag flask-backend:$IMAGE_TAG \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:$IMAGE_TAG
docker tag flask-backend:$IMAGE_TAG \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:latest
docker push $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:$IMAGE_TAG
docker push $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:latest

# Tag and push frontend
echo -e "${GREEN}Pushing frontend to Artifact Registry...${NC}"
docker tag flask-frontend:$IMAGE_TAG \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-frontend:$IMAGE_TAG
docker tag flask-frontend:$IMAGE_TAG \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-frontend:latest
docker push $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-frontend:$IMAGE_TAG
docker push $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-frontend:latest

echo ""
echo -e "${GREEN}✅ Successfully pushed images!${NC}"
echo ""
echo "Backend: $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:$IMAGE_TAG"
echo "Frontend: $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-frontend:$IMAGE_TAG"
EOF

# Make it executable
chmod +x scripts/build-push-to-registry.sh

# Run it
./scripts/build-push-to-registry.sh
```

---

## Verify Images

### Method 1: Using gcloud CLI

```bash
# List all images in repository
gcloud artifacts docker images list \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME

# List tags for specific image
gcloud artifacts docker images list \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend \
  --include-tags

# Get detailed image information
gcloud artifacts docker images describe \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:latest
```

### Method 2: Using Google Cloud Console

1. Go to [Artifact Registry](https://console.cloud.google.com/artifacts)
2. Click on your repository (`flask-app-images`)
3. Browse images and tags
4. View vulnerability scan results
5. See image layers and size

### Method 3: Pull and Test Locally

```bash
# Pull image from Artifact Registry
docker pull $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:latest

# Run it locally to test
docker run -p 5000:5000 \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:latest

# Test endpoint
curl http://localhost:5000/health

# Stop the container
docker ps
docker stop <container-id>
```

---

## Configure IAM Permissions

### For Teams and Multiple Users

Grant appropriate permissions to team members:

```bash
# Grant read-only access (pull images)
gcloud artifacts repositories add-iam-policy-binding $REPOSITORY_NAME \
  --location=$REGION \
  --member="user:developer@example.com" \
  --role="roles/artifactregistry.reader"

# Grant read-write access (push and pull images)
gcloud artifacts repositories add-iam-policy-binding $REPOSITORY_NAME \
  --location=$REGION \
  --member="user:admin@example.com" \
  --role="roles/artifactregistry.writer"

# View current permissions
gcloud artifacts repositories get-iam-policy $REPOSITORY_NAME \
  --location=$REGION
```

### For GKE Cluster (Image Pull)

GKE needs permission to pull images:

```bash
# Get your GKE cluster's service account
export GKE_SA=$(gcloud container clusters describe flask-k8s-cluster \
  --zone=asia-south1-a \
  --format="get(nodeConfig.serviceAccount)")

# Grant Artifact Registry Reader permission
gcloud artifacts repositories add-iam-policy-binding $REPOSITORY_NAME \
  --location=$REGION \
  --member="serviceAccount:$GKE_SA" \
  --role="roles/artifactregistry.reader"
```

> [!NOTE]
> If using the default Compute Engine service account, it usually already has these permissions.

### Available Roles

| Role | Permissions | Use Case |
|------|-------------|----------|
| `roles/artifactregistry.reader` | Pull images | GKE nodes, developers |
| `roles/artifactregistry.writer` | Pull & push images | CI/CD pipelines |
| `roles/artifactregistry.admin` | Full control | Repository admins |

---

## Image Management

### Image Tagging Best Practices

Use semantic versioning and multiple tags:

```bash
# Tag with version
docker tag myimage $REGISTRY/myimage:v1.2.3

# Tag with git commit
docker tag myimage $REGISTRY/myimage:$(git rev-parse --short HEAD)

# Tag with date
docker tag myimage $REGISTRY/myimage:$(date +%Y%m%d)

# Tag environment
docker tag myimage $REGISTRY/myimage:production
docker tag myimage $REGISTRY/myimage:staging

# Always tag latest
docker tag myimage $REGISTRY/myimage:latest
```

### List and Delete Images

```bash
# List all tags for an image
gcloud artifacts docker tags list \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend

# Delete specific tag
gcloud artifacts docker images delete \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:v1.0.0 \
  --quiet

# Delete untagged images (cleanup)
gcloud artifacts docker images list \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME \
  --filter="-tags:*" \
  --format="get(package)" | \
  xargs -I {} gcloud artifacts docker images delete {} --quiet
```

### Vulnerability Scanning

Artifact Registry automatically scans images for vulnerabilities:

```bash
# View vulnerabilities for an image
gcloud artifacts docker images list \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend \
  --show-occurrences

# Get detailed vulnerability report
gcloud artifacts docker images describe \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME/flask-backend:latest \
  --show-all-metadata
```

View in Console:
1. Go to Artifact Registry
2. Click on image
3. Go to "Vulnerabilities" tab
4. See CVEs, severity, and fixes

### Cleanup Policies

Set up automatic cleanup to save costs:

```bash
# Create cleanup policy (delete images older than 30 days with no tags)
# Note: This feature requires console configuration
# Go to: Console → Artifact Registry → Repository → Cleanup Policies
```

**Recommended policy:**
- Keep `latest` tag forever
- Keep last 10 tagged versions
- Delete untagged images after 7 days
- Delete images older than 90 days (except latest)

---

## Cost Optimization

### Monitor Storage Usage

```bash
# Check repository size
gcloud artifacts repositories describe $REPOSITORY_NAME \
  --location=$REGION \
  --format="get(sizeBytes)"

# List images by size
gcloud artifacts docker images list \
  $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME \
  --format="table(package, version, size)"
```

### Best Practices to Save Costs

1. **Use multi-stage Docker builds** to reduce image size:
   ```dockerfile
   FROM python:3.11-slim as builder
   # Build steps...
   
   FROM python:3.11-slim
   COPY --from=builder /app /app
   ```

2. **Delete old images regularly**:
   ```bash
   # Delete images older than 30 days
   # (implement custom script or use cleanup policies)
   ```

3. **Use appropriate base images**:
   - `alpine` for smallest size (5-10 MB)
   - `slim` for good balance (50-100 MB)
   - Avoid full images (500+ MB)

4. **Compress layers**:
   ```dockerfile
   RUN apt-get update && apt-get install -y --no-install-recommends \
       package1 package2 \
       && apt-get clean \
       && rm -rf /var/lib/apt/lists/*
   ```

---

## Troubleshooting

### Issue: Authentication failure when pushing

```bash
# Error: "denied: Permission denied for resource"

# Solution: Re-authenticate
gcloud auth login
gcloud auth configure-docker $REGION-docker.pkg.dev

# Verify project
gcloud config get-value project
```

### Issue: Image pull fails in GKE

```bash
# Error: "Failed to pull image... unauthorized"

# Solution: Grant GKE service account access
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:$GKE_SA" \
  --role="roles/artifactregistry.reader"
```

### Issue: Slow image pushes

```bash
# Check Docker layer caching
docker system df

# Clean up unused layers
docker system prune -a

# Use BuildKit for faster builds
export DOCKER_BUILDKIT=1
docker build -t myimage .
```

### Issue: Repository not found

```bash
# Verify repository exists
gcloud artifacts repositories list --location=$REGION

# Check spelling and region
echo $REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME
```

---

## Environment Configuration File

Create a config file for convenience:

```bash
# Create gke-config.env
cat > gke-config.env << EOF
# GCP Configuration
export GCP_PROJECT_ID="flask-k8s-production"
export REGION="us-central1"
export ZONE="us-central1-a"

# Artifact Registry
export REPOSITORY_NAME="flask-app-images"
export REGISTRY_URL="$REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME"

# GKE Cluster
export CLUSTER_NAME="flask-k8s-cluster"

# GitLab CI/CD
export GITLAB_DEPLOYER_SA="gitlab-deployer@$GCP_PROJECT_ID.iam.gserviceaccount.com"
EOF

# Load configuration
source gke-config.env

# Verify
echo $REGISTRY_URL
```

---

## Next Steps

✅ **Artifact Registry is now set up!**

Continue with:

1. **[Deploy to GKE](./GKE-DEPLOYMENT-GUIDE.md)** - Deploy your application using these images
2. **[GitLab CI/CD Setup](./GKE-GITLAB-CI-CD-GUIDE.md)** - Automate the build and push process
3. **[Monitoring Setup](./GKE-MONITORING.md)** - Set up monitoring and logging

---

## Additional Resources

- [Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)
- [Artifact Registry Pricing](https://cloud.google.com/artifact-registry/pricing)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Container Image Security](https://cloud.google.com/architecture/best-practices-for-building-containers)

---

**Next Guide**: [GKE Deployment Guide →](./GKE-DEPLOYMENT-GUIDE.md)
