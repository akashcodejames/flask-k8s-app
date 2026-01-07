# Flask K8s Application

A minimal Flask application with HTML frontend deployed on Kubernetes with Ingress.

## Project Structure

```
flask-k8s-app/
├── backend/
│   ├── app.py              # Flask application
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile          # Backend container image
├── frontend/
│   ├── index.html          # Frontend UI
│   └── Dockerfile          # Frontend container image
└── k8s/
    ├── namespace.yaml              # Namespace: flask-app
    ├── backend-deployment.yaml     # Backend deployment (2 replicas)
    ├── backend-service.yaml        # Backend ClusterIP service
    ├── frontend-deployment.yaml    # Frontend deployment (2 replicas)
    ├── frontend-service.yaml       # Frontend ClusterIP service
    └── ingress.yaml                # Ingress for akash.local
```

## Features

- **Backend**: Flask API with CORS support
  - `/health` - Health check endpoint
  - `/api` - API root with endpoint list
  - `/api/message` - Returns JSON message

- **Frontend**: Modern responsive HTML with gradient design
  - Auto-fetches message from backend on load
  - Beautiful UI with animations
  - Error handling

- **Kubernetes**:
  - Namespace isolation
  - 2 replicas each for HA
  - Health probes (liveness + readiness)
  - Resource limits
  - Path-based ingress routing

## Quick Start

### 1. Build Docker Images

```bash
cd /Users/akashyadav/Desktop/k8s/flask-k8s-app

# Build backend
docker build -t flask-backend:latest ./backend

# Build frontend
docker build -t flask-frontend:latest ./frontend
```

### 2. Load Images to Kind Cluster

```bash
kind load docker-image flask-backend:latest
kind load docker-image flask-frontend:latest
```

### 3. Deploy to Kubernetes

```bash
# Apply all manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/ingress.yaml
```

### 4. Configure Local DNS

Add this line to `/etc/hosts`:

```
127.0.0.1 akash.local
```

### 5. Access the Application

Open your browser and navigate to:
- **Frontend**: http://akash.local
- **API**: http://akash.local/api/message

## Verify Deployment

```bash
# Check namespace
kubectl get ns flask-app

# Check all resources
kubectl get all -n flask-app

# Check ingress
kubectl get ingress -n flask-app

# View logs
kubectl logs -n flask-app -l app=flask-backend
kubectl logs -n flask-app -l app=flask-frontend
```

## Ingress Configuration

The ingress uses path-based routing:

- **Path `/`** → `frontend-service:80` (Nginx)
- **Path `/api`** → `backend-service:80` (Flask on port 5000)

Host: `akash.local`

## Cleanup

```bash
kubectl delete namespace flask-app
```

## Prerequisites

- Kind cluster running with ingress controller
- Docker installed
- kubectl configured
