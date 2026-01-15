# Flask K8s Application

A production-ready Flask application with HTML frontend, deployed on Kubernetes with automated CI/CD pipeline.

## 🚀 Deployment Options

This application supports two deployment environments:

### 1. **Local Development (Kind)**
- Quick local testing with Kind (Kubernetes in Docker)
- Self-hosted GitHub Actions runner
- See: [Local Setup Guide](./README-LOCAL.md)

### 2. **Production (GKE)** ⭐ **Recommended**
- Google Kubernetes Engine (GKE) cluster
- Google Artifact Registry for Docker images
- GitLab CI/CD for automated deployments
- See documentation below

---

## 📋 Table of Contents

- [Architecture](#architecture)
- [Features](#features)
- [GKE Setup](#gke-setup)
- [Local Development](#local-development)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Contributing](#contributing)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform                     │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Artifact Registry                         │ │
│  │  • flask-backend:latest                                │ │
│  │  • flask-frontend:latest                               │ │
│  └────────────────────────────────────────────────────────┘ │
│                           │                                  │
│                           ▼                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │         Google Kubernetes Engine (GKE)                 │ │
│  │                                                         │ │
│  │   ┌──────────────┐          ┌──────────────┐          │ │
│  │   │   Backend    │          │   Frontend   │          │ │
│  │   │   (Flask)    │◄────────►│   (Nginx)    │          │ │
│  │   │   2 replicas │          │   2 replicas │          │ │
│  │   └──────────────┘          └──────────────┘          │ │
│  │          │                          │                  │ │
│  │          ▼                          ▼                  │ │
│  │   ┌─────────────────────────────────────┐             │ │
│  │   │      Ingress Controller             │             │ │
│  │   │   (GKE or nginx-ingress)            │             │ │
│  │   └─────────────────────────────────────┘             │ │
│  │                     │                                  │ │
│  └─────────────────────┼──────────────────────────────────┘ │
│                        │                                    │
└────────────────────────┼────────────────────────────────────┘
                         │
                         ▼
                 ┌───────────────┐
                 │  Load Balancer │
                 │  (External IP) │
                 └───────────────┘
                         │
                         ▼
                  Internet Users
```

**CI/CD Flow:**
```
GitLab Push → Build Images → Push to Registry → Deploy to GKE → Verify
```

---

## ✨ Features

### Backend (Flask)
- RESTful API with health checks
- CORS support for frontend integration
- Production-ready with proper error handling
- Health endpoint: `/health`
- API endpoints: `/api`, `/api/message`

### Frontend
- Modern responsive HTML/CSS design
- Auto-fetches data from backend
- Beautiful gradient UI with animations
- Mobile-friendly design

### Kubernetes Features
- **High Availability**: 2+ replicas per service
- **Health Probes**: Liveness and readiness checks
- **Resource Management**: CPU and memory limits
- **Rolling Updates**: Zero-downtime deployments
- **Auto-scaling**: Horizontal Pod Autoscaling ready
- **Ingress Routing**: Path-based routing (/, /api)

### DevOps
- **GitLab CI/CD**: Automated build, push, and deploy
- **Multi-Environment**: Staging and production pipelines
- **Artifact Registry**: Secure Docker image storage
- **Monitoring**: Google Cloud Logging and Monitoring
- **Rollback**: Easy rollback to previous versions

---

## 🚀 GKE Setup

### Prerequisites

- Google Cloud Platform account with billing enabled
- `gcloud` CLI installed and configured
- `kubectl` installed
- GitLab account and repository
- Docker installed (for local testing)

### Step-by-Step Setup

#### 1. **GKE Cluster Setup**
Complete guide: [GKE-SETUP.md](./GKE-SETUP.md)

```bash
# Quick setup
gcloud container clusters create flask-k8s-cluster \
  --zone=asia-south1-a \
  --num-nodes=2 \
  --machine-type=e2-medium
```

#### 2. **Artifact Registry Setup**
Complete guide: [ARTIFACT-REGISTRY-SETUP.md](./ARTIFACT-REGISTRY-SETUP.md)

```bash
# Create repository
gcloud artifacts repositories create flask-app-images \
  --repository-format=docker \
  --location=asia-south1

# Configure Docker
gcloud auth configure-docker asia-south1-docker.pkg.dev
```

#### 3. **GitLab CI/CD Configuration**
Complete guide: [GKE-GITLAB-CI-CD-GUIDE.md](./GKE-GITLAB-CI-CD-GUIDE.md)

```bash
# Create service account
gcloud iam service-accounts create gitlab-deployer

# Grant permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:gitlab-deployer@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Create key and add to GitLab CI/CD variables
```

#### 4. **Deploy Application**
Complete guide: [GKE-DEPLOYMENT-GUIDE.md](./GKE-DEPLOYMENT-GUIDE.md)

```bash
# Using scripts
./scripts/gke-build-push.sh
./scripts/gke-deploy.sh

# Or push to GitLab (triggers automatic deployment)
git push origin main
```

---

## 💻 Local Development

### Using Kind (Kubernetes in Docker)

```bash
# Create Kind cluster
kind create cluster --config kind-cluster-config.yaml

# Build images
docker build -t flask-backend:latest ./backend
docker build -t flask-frontend:latest ./frontend

# Load to Kind
kind load docker-image flask-backend:latest
kind load docker-image flask-frontend:latest

# Deploy
kubectl apply -f k8s/

# Access
echo "127.0.0.1 akash.local" | sudo tee -a /etc/hosts
open http://akash.local
```

### Using Docker Compose

```bash
docker-compose up -d
open http://localhost
```

---

## 📁 Project Structure

```
flask-k8s-app/
├── backend/
│   ├── app.py              # Flask application
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile          # Backend container
├── frontend/
│   ├── index.html          # Frontend UI
│   └── Dockerfile          # Frontend container (nginx)
├── k8s/
│   ├── gke/                # GKE-specific manifests
│   │   ├── namespace.yaml
│   │   ├── backend-deployment.yaml
│   │   ├── backend-service.yaml
│   │   ├── frontend-deployment.yaml
│   │   ├── frontend-service.yaml
│   │   ├── ingress-gke.yaml     # GKE Ingress
│   │   └── ingress-nginx.yaml   # nginx Ingress
│   └── [local manifests]
├── scripts/
│   ├── gke-build-push.sh   # Build and push images
│   ├── gke-deploy.sh       # Deploy to GKE
│   └── gke-rollback.sh     # Rollback deployment
├── .gitlab-ci.yml          # GitLab CI/CD pipeline
├── gke-config.env.example  # Configuration template
├── GKE-SETUP.md           # GKE cluster setup guide
├── ARTIFACT-REGISTRY-SETUP.md  # Artifact Registry guide
├── GKE-DEPLOYMENT-GUIDE.md     # Deployment guide
├── GKE-GITLAB-CI-CD-GUIDE.md   # CI/CD setup guide
├── GKE-TROUBLESHOOTING.md      # Troubleshooting guide
└── README.md              # This file
```

---

## 🎯 Quick Start

### Option 1: Automated Deployment (GitLab CI/CD)

1. **Fork/Clone** this repository to GitLab
2. **Complete setup guides** in order:
   - [GKE Setup](./GKE-SETUP.md)
   - [Artifact Registry](./ARTIFACT-REGISTRY-SETUP.md)
   - [GitLab CI/CD](./GKE-GITLAB-CI-CD-GUIDE.md)
3. **Configure GitLab variables** (see CI/CD guide)
4. **Push to main branch**:
   ```bash
   git add .
   git commit -m "Initial deployment"
   git push origin main
   ```
5. **Monitor pipeline** in GitLab → CI/CD → Pipelines
6. **Access application** via external IP

### Option 2: Manual Deployment

1. **Setup configuration**:
   ```bash
   cp gke-config.env.example gke-config.env
   # Edit gke-config.env with your values
   source gke-config.env
   ```

2. **Build and push images**:
   ```bash
   ./scripts/gke-build-push.sh
   ```

3. **Deploy to GKE**:
   ```bash
   ./scripts/gke-deploy.sh
   ```

4. **Get external IP**:
   ```bash
   kubectl get ingress -n flask-app
   ```

---

## 📚 Documentation

### Setup Guides
- **[GKE Cluster Setup](./GKE-SETUP.md)** - Complete GKE cluster creation guide
- **[Artifact Registry Setup](./ARTIFACT-REGISTRY-SETUP.md)** - Docker image registry setup
- **[Deployment Guide](./GKE-DEPLOYMENT-GUIDE.md)** - Application deployment walkthrough
- **[GitLab CI/CD Guide](./GKE-GITLAB-CI-CD-GUIDE.md)** - Automated pipeline configuration
- **[Troubleshooting Guide](./GKE-TROUBLESHOOTING.md)** - Common issues and solutions

### API Documentation

**Health Check:**
```bash
GET /health
Response: {"status": "healthy"}
```

**API Root:**
```bash
GET /api
Response: {
  "message": "Welcome to Flask K8s API",
  "endpoints": ["/api/message", "/health"]
}
```

**Message Endpoint:**
```bash
GET /api/message
Response: {
  "message": "Hello from Flask running on Kubernetes!",
  "pod": "backend-deployment-xxx",
  "timestamp": "2026-01-11T12:00:00Z"
}
```

---

## 🔧 Configuration

### Environment Variables

Set in `gke-config.env`:

| Variable | Description | Default |
|----------|-------------|---------|
| `GCP_PROJECT_ID` | GCP project ID | `flask-k8s-production` |
| `GCP_REGION` | GCP region | `us-central1` |
| `GCP_ZONE` | GCP zone | `us-central1-a` |
| `CLUSTER_NAME` | GKE cluster name | `flask-k8s-cluster` |
| `REPOSITORY_NAME` | Artifact Registry repo | `flask-app-images` |
| `KUBE_NAMESPACE` | Kubernetes namespace | `flask-app` |
| `IMAGE_TAG` | Docker image tag | `latest` |

### GitLab CI/CD Variables

Set in GitLab → Settings → CI/CD → Variables:

- `GCP_SERVICE_KEY` (masked, protected)
- `GCP_PROJECT_ID`
- `GCP_REGION`
- `GCP_ZONE`
- `ARTIFACT_REGISTRY_REPO`
- `GKE_CLUSTER_NAME`

---

## 🛠️ Common Tasks

### View Application Logs
```bash
# Backend logs
kubectl logs -n flask-app -l app=flask-backend -f

# Frontend logs
kubectl logs -n flask-app -l app=flask-frontend -f
```

### Scale Application
```bash
# Scale backend
kubectl scale deployment/backend-deployment --replicas=4 -n flask-app

# Enable autoscaling
kubectl autoscale deployment/backend-deployment \
  --min=2 --max=10 --cpu-percent=70 -n flask-app
```

### Update Application
```bash
# Build new version
./scripts/gke-build-push.sh

# Deploy
./scripts/gke-deploy.sh

# Or push to GitLab for automatic deployment
git push origin main
```

### Rollback Deployment
```bash
# Rollback backend to previous version
./scripts/gke-rollback.sh backend-deployment

# Rollback to specific revision
./scripts/gke-rollback.sh backend-deployment 3
```

### Delete Application
```bash
# Delete all resources
kubectl delete namespace flask-app

# Or delete cluster
gcloud container clusters delete flask-k8s-cluster --zone=us-central1-a
```

---

## 💰 Cost Estimation

**Monthly costs for production setup:**

| Service | Configuration | Cost |
|---------|--------------|------|
| GKE Management | Zonal cluster | Free |
| Compute Nodes | 2x e2-medium | ~$50 |
| Load Balancer | 1 external IP | ~$20 |
| Artifact Registry | <10GB storage | ~$1 |
| Network Egress | Minimal | ~$5 |
| **Total** | | **~$76/month** |

**Cost optimization tips:**
- Use preemptible nodes (60% cheaper)
- Enable cluster autoscaling
- Delete unused load balancers
- Use regional storage in same region as cluster
- Clean up old images in Artifact Registry

---

## 🐛 Troubleshooting

See [GKE-TROUBLESHOOTING.md](./GKE-TROUBLESHOOTING.md) for detailed solutions.

**Quick checks:**
```bash
# Check pod status
kubectl get pods -n flask-app

# Check logs
kubectl logs -n flask-app <pod-name>

# Check ingress
kubectl get ingress -n flask-app

# Describe resources
kubectl describe pod <pod-name> -n flask-app
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally with Kind
5. Submit a pull request

---

## 📝 License

This project is licensed under the MIT License.

---

## 🙏 Acknowledgments

- Flask - Python web framework
- Kubernetes - Container orchestration
- Google Cloud Platform - Cloud infrastructure
- GitLab - CI/CD platform

---

## 📞 Support

For issues and questions:
- Open an issue on GitLab
- Check [Troubleshooting Guide](./GKE-TROUBLESHOOTING.md)
- Review setup guides for common problems

---

**Made with ❤️ for Kubernetes deployments**
