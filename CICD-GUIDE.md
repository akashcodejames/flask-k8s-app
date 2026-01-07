# CI/CD Setup Guide - Flask K8s Application

Complete guide for setting up automated deployment pipeline for your Flask Kubernetes application.

## Table of Contents

1. [Overview](#overview)
2. [GitHub Actions Setup](#github-actions-setup)
3. [Manual Deployment Process](#manual-deployment-process)
4. [Local Auto-Update](#local-auto-update)
5. [Troubleshooting](#troubleshooting)

---

## Overview

This guide covers two deployment approaches:

1. **GitHub Actions (CI/CD)**: Automated builds and deployments when code is pushed
2. **Manual/Local Updates**: Scripts for quick local development updates

### Architecture

```
Code Push → GitHub Actions
    ↓
Build Docker Images → Push to Registry (GHCR)
    ↓
Update K8s Manifests → Deploy to Cluster
    ↓
Kind Cluster Updates → Application Running
```

---

## GitHub Actions Setup

### 1. Prerequisites

- GitHub repository for your code
- GitHub Container Registry (GHCR) access (free with GitHub)
- (Optional) Self-hosted runner for local Kind cluster deployment

### 2. Enable GitHub Container Registry

1. Go to your repository settings
2. Navigate to **Packages** → **Container registry**  
3. Enable container registry for your repository

### 3. GitHub Actions Workflow

The workflow file is already created at [`.github/workflows/deploy.yml`](file:///Users/akashyadav/Desktop/k8s/flask-k8s-app/.github/workflows/deploy.yml)

**What it does:**

- ✅ Triggers on push to `main`/`master` branch
- ✅ Builds Docker images for backend and frontend
- ✅ Pushes images to GitHub Container Registry
- ✅ Tags images with commit SHA and branch name
- ✅ Creates updated Kubernetes manifests as artifacts
- 🔧 (Optional) Deploys to Kind cluster via self-hosted runner

### 4. Using the CI/CD Pipeline

**Automatic Deployment:**

```bash
# Make your code changes
vim backend/app.py

# Commit and push
git add .
git commit -m "Update backend API"
git push origin main
```

GitHub Actions will automatically:
1. Build new Docker images
2. Push to GHCR (ghcr.io/your-username/flask-k8s-app/backend:latest)
3. Create deployment artifacts

### 5. Pull Images from GHCR to Local Kind

After GitHub Actions completes:

```bash
# Pull the latest images
docker pull ghcr.io/YOUR_USERNAME/flask-k8s-app/backend:latest
docker pull ghcr.io/YOUR_USERNAME/flask-k8s-app/frontend:latest

# Tag for local use
docker tag ghcr.io/YOUR_USERNAME/flask-k8s-app/backend:latest flask-backend:latest
docker tag ghcr.io/YOUR_USERNAME/flask-k8s-app/frontend:latest flask-frontend:latest

# Load to Kind cluster
kind load docker-image flask-backend:latest --name akash-multi
kind load docker-image flask-frontend:latest --name akash-multi

# Restart deployments
kubectl rollout restart deployment/backend-deployment -n flask-app
kubectl rollout restart deployment/frontend-deployment -n flask-app
```

### 6. Self-Hosted Runner (Optional - For Automatic Local Deployment)

To enable automatic deployment to your local Kind cluster:

**Step 1: Set up self-hosted runner**

1. Go to your repository → Settings → Actions → Runners
2. Click "New self-hosted runner"
3. Follow instructions to install runner on your Mac
4. Start the runner

**Step 2: Enable deployment job**

Edit `.github/workflows/deploy.yml`:

```yaml
deploy-to-kind:
  runs-on: self-hosted  # Your self-hosted runner
  needs: build-and-deploy
  if: true  # Change from 'false' to 'true'
```

Now deployments to your local Kind cluster will happen automatically!

---

## Manual Deployment Process

For local development without GitHub Actions.

### Method 1: Quick Update Script

Use the automated update script:

```bash
./update.sh
```

This script:
- ✅ Pulls latest code from git
- ✅ Builds Docker images with versioned tags
- ✅ Loads images to Kind cluster
- ✅ Restarts deployments
- ✅ Waits for rollout completion
- ✅ Shows current status

**Environment Variables:**

```bash
# Customize cluster name
KIND_CLUSTER_NAME=my-cluster ./update.sh
```

### Method 2: Manual Step-by-Step

**1. Make code changes:**

```bash
vim backend/app.py
vim frontend/index.html
```

**2. Build images:**

```bash
docker build -t flask-backend:latest ./backend
docker build -t flask-frontend:latest ./frontend
```

**3. Load to Kind:**

```bash
kind load docker-image flask-backend:latest --name akash-multi
kind load docker-image flask-frontend:latest --name akash-multi
```

**4. Update deployments:**

```bash
# Option A: Restart (recommended for image updates)
kubectl rollout restart deployment/backend-deployment -n flask-app
kubectl rollout restart deployment/frontend-deployment -n flask-app

# Option B: Re-apply manifests (if you changed k8s configs)
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
```

**5. Verify:**

```bash
# Check rollout status
kubectl rollout status deployment/backend-deployment -n flask-app
kubectl rollout status deployment/frontend-deployment -n flask-app

# Check pods
kubectl get pods -n flask-app

# Test application
curl http://akash.local/api/message
```

### Method 3: Using deploy.sh (Full Deployment)

For complete redeployment from scratch:

```bash
./deploy.sh
```

This rebuilds everything and applies all manifests.

---

## Local Auto-Update

### Watch Mode with Git

Set up a git hook to auto-update on pull:

**1. Create post-merge hook:**

```bash
cat > .git/hooks/post-merge << 'EOF'
#!/bin/bash
echo "Code updated, running auto-update..."
./update.sh
EOF

chmod +x .git/hooks/post-merge
```

**2. Now when you pull:**

```bash
git pull  # Automatically triggers update.sh
```

### File Watcher (Advanced)

Use `fswatch` to auto-rebuild on file changes:

```bash
# Install fswatch
brew install fswatch

# Watch for changes
fswatch -o backend/ frontend/ | xargs -n1 -I{} ./update.sh
```

---

## Rollback

If an update breaks something, rollback to the previous version:

```bash
./rollback.sh
```

Or manually:

```bash
# Rollback to previous revision
kubectl rollout undo deployment/backend-deployment -n flask-app
kubectl rollout undo deployment/frontend-deployment -n flask-app

# Rollback to specific revision
kubectl rollout undo deployment/backend-deployment -n flask-app --to-revision=2

# Check rollout history
kubectl rollout history deployment/backend-deployment -n flask-app
```

---

## Troubleshooting

### Images Not Updating

**Problem:** New code doesn't reflect after deployment

**Solution:**

```bash
# Force pull new images
docker rmi flask-backend:latest flask-frontend:latest

# Rebuild without cache
docker build --no-cache -t flask-backend:latest ./backend
docker build --no-cache -t flask-frontend:latest ./frontend

# Reload to Kind
kind load docker-image flask-backend:latest --name akash-multi
kind load docker-image flask-frontend:latest --name akash-multi

# Delete and recreate pods
kubectl delete pods -n flask-app --all
```

### GitHub Actions Failing

**Problem:** Workflow fails on image push

**Solution:**

1. Check GITHUB_TOKEN permissions:
   - Repository Settings → Actions → General
   - Set "Workflow permissions" to "Read and write permissions"

2. Verify package visibility:
   - Your profile → Packages → flask-k8s-app
   - Change visibility to match your repository (public/private)

### Self-Hosted Runner Issues

**Problem:** Runner can't access Kind cluster

**Solution:**

```bash
# Ensure runner user has kubectl access
sudo usermod -aG docker github-runner

# Verify kubectl works
kubectl get nodes

# Check Kind cluster exists
kind get clusters
```

### Deployment Stuck

**Problem:** Rollout never completes

**Solution:**

```bash
# Check pod status
kubectl get pods -n flask-app

# Check pod logs
kubectl logs -n flask-app <pod-name>

# Describe pod for events
kubectl describe pod -n flask-app <pod-name>

# Force delete stuck pods
kubectl delete pod -n flask-app <pod-name> --force --grace-period=0
```

---

## Quick Reference

### Useful Commands

```bash
# Check deployment status
kubectl get deployments -n flask-app

# View rollout history
kubectl rollout history deployment/backend-deployment -n flask-app

# Scale replicas
kubectl scale deployment/backend-deployment --replicas=3 -n flask-app

# Get deployment YAML
kubectl get deployment backend-deployment -n flask-app -o yaml

# Port forward for debugging
kubectl port-forward -n flask-app svc/backend-service 5000:80

# Execute command in pod
kubectl exec -it -n flask-app deployment/backend-deployment -- sh

# View real-time logs
kubectl logs -f -n flask-app deployment/backend-deployment
```

### File Structure

```
flask-k8s-app/
├── .github/workflows/deploy.yml    # CI/CD workflow
├── update.sh                        # Auto-update script
├── rollback.sh                      # Rollback script
├── deploy.sh                        # Full deployment script
├── backend/                         # Backend source
├── frontend/                        # Frontend source
└── k8s/                            # Kubernetes manifests
```

---

## Next Steps

1. ✅ Set up GitHub repository
2. ✅ Push code to trigger first build
3. ✅ (Optional) Configure self-hosted runner
4. ✅ Test manual update process with `./update.sh`
5. ✅ Create a test PR to verify pipeline

Happy deploying! 🚀
