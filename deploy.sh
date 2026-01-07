#!/bin/bash

# Deploy Flask K8s Application
# This script builds, loads, and deploys the Flask application to Kind cluster

set -e

echo "🚀 Starting deployment of Flask K8s Application..."

# Build Docker images
echo ""
echo "📦 Building Docker images..."
docker build -t flask-backend:latest ./backend
docker build -t flask-frontend:latest ./frontend

# Load images to kind cluster
echo ""
echo "⬆️  Loading images to kind cluster (akash-multi)..."
kind load docker-image flask-backend:latest --name akash-multi
kind load docker-image flask-frontend:latest --name akash-multi

# Apply Kubernetes manifests
echo ""
echo "☸️  Applying Kubernetes manifests..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/ingress.yaml

# Wait for deployments to be ready
echo ""
echo "⏳ Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=60s deployment/backend-deployment -n flask-app
kubectl wait --for=condition=available --timeout=60s deployment/frontend-deployment -n flask-app

# Show deployment status
echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Current status:"
kubectl get all -n flask-app
echo ""
kubectl get ingress -n flask-app

echo ""
echo "🌐 Application is available at:"
echo "   Frontend: http://akash.local"
echo "   API:      http://akash.local/api/message"
echo ""
echo "⚠️  Make sure you have added the following to /etc/hosts:"
echo "   127.0.0.1 akash.local"
