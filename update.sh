#!/bin/bash

# Auto-update Flask K8s Application
# This script pulls latest code, builds images, and updates the Kind cluster

set -e

echo "🔄 Starting auto-update process..."

# Configuration
CLUSTER_NAME="${KIND_CLUSTER_NAME:-akash-multi}"
NAMESPACE="flask-app"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if git repo
if [ ! -d ".git" ]; then
    print_warning "Not a git repository. Skipping pull."
else
    # Pull latest changes
    print_step "Pulling latest changes from git..."
    git pull
    print_success "Code updated"
fi

# Get current commit SHA for versioning
COMMIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
IMAGE_TAG="${COMMIT_SHA}-${TIMESTAMP}"

print_step "Building images with tag: ${IMAGE_TAG}"

# Build Docker images
print_step "Building backend image..."
docker build -t flask-backend:${IMAGE_TAG} -t flask-backend:latest ./backend
print_success "Backend image built"

print_step "Building frontend image..."
docker build -t flask-frontend:${IMAGE_TAG} -t flask-frontend:latest ./frontend
print_success "Frontend image built"

# Load images to Kind cluster
print_step "Loading images to Kind cluster (${CLUSTER_NAME})..."
kind load docker-image flask-backend:${IMAGE_TAG} --name ${CLUSTER_NAME}
kind load docker-image flask-frontend:${IMAGE_TAG} --name ${CLUSTER_NAME}
print_success "Images loaded to cluster"

# Update deployments with new image
print_step "Updating Kubernetes deployments..."

# Restart deployments to pick up new images
kubectl rollout restart deployment/backend-deployment -n ${NAMESPACE}
kubectl rollout restart deployment/frontend-deployment -n ${NAMESPACE}

print_step "Waiting for deployments to complete..."
kubectl rollout status deployment/backend-deployment -n ${NAMESPACE} --timeout=120s
kubectl rollout status deployment/frontend-deployment -n ${NAMESPACE} --timeout=120s

print_success "Deployments updated successfully!"

# Show current status
echo ""
print_step "Current deployment status:"
kubectl get pods -n ${NAMESPACE}

echo ""
print_step "Application endpoints:"
echo "  Frontend: http://akash.local"
echo "  API:      http://akash.local/api/message"

echo ""
print_success "Update complete! 🎉"
echo ""
echo "Image tags used:"
echo "  - flask-backend:${IMAGE_TAG}"
echo "  - flask-frontend:${IMAGE_TAG}"
