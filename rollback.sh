#!/bin/bash

# Rollback Flask K8s Application to previous version

set -e

NAMESPACE="flask-app"

echo "🔙 Rolling back deployments..."

# Rollback backend
echo "Rolling back backend deployment..."
kubectl rollout undo deployment/backend-deployment -n ${NAMESPACE}

# Rollback frontend
echo "Rolling back frontend deployment..."
kubectl rollout undo deployment/frontend-deployment -n ${NAMESPACE}

# Wait for rollback to complete
echo "Waiting for rollback to complete..."
kubectl rollout status deployment/backend-deployment -n ${NAMESPACE}
kubectl rollout status deployment/frontend-deployment -n ${NAMESPACE}

echo ""
echo "✓ Rollback complete!"
echo ""
echo "Current deployment status:"
kubectl get pods -n ${NAMESPACE}

echo ""
echo "Deployment history:"
echo "Backend:"
kubectl rollout history deployment/backend-deployment -n ${NAMESPACE}
echo ""
echo "Frontend:"
kubectl rollout history deployment/frontend-deployment -n ${NAMESPACE}
