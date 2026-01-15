#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
export GCP_PROJECT_ID="${GCP_PROJECT_ID:-flask-k8s-production}"
export ZONE="${ZONE:-asia-south1-a}"
export CLUSTER_NAME="${CLUSTER_NAME:-flask-k8s-cluster}"
export KUBE_NAMESPACE="${KUBE_NAMESPACE:-flask-app}"

# Parse arguments
DEPLOYMENT="${1:-backend-deployment}"
REVISION="${2:-0}"  # 0 means previous revision

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              GKE Rollback Script                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠️  Warning: This will rollback the deployment!${NC}"
echo "  Deployment: $DEPLOYMENT"
echo "  Namespace:  $KUBE_NAMESPACE"
if [ "$REVISION" -eq "0" ]; then
    echo "  Revision:   Previous"
else
    echo "  Revision:   $REVISION"
fi
echo ""

# Confirm rollback
read -p "Continue with rollback? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Rollback cancelled.${NC}"
    exit 1
fi

# Get GKE credentials
echo -e "${YELLOW}🔐 Getting GKE cluster credentials...${NC}"
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$GCP_PROJECT_ID

# Show rollout history
echo ""
echo -e "${BLUE}📜 Rollout history:${NC}"
kubectl rollout history deployment/$DEPLOYMENT -n $KUBE_NAMESPACE

# Perform rollback
echo ""
echo -e "${YELLOW}⏪ Rolling back deployment...${NC}"
if [ "$REVISION" -eq "0" ]; then
    # Rollback to previous revision
    kubectl rollout undo deployment/$DEPLOYMENT -n $KUBE_NAMESPACE
else
    # Rollback to specific revision
    kubectl rollout undo deployment/$DEPLOYMENT --to-revision=$REVISION -n $KUBE_NAMESPACE
fi

# Wait for rollback
echo -e "${YELLOW}⏳ Waiting for rollback to complete...${NC}"
kubectl rollout status deployment/$DEPLOYMENT -n $KUBE_NAMESPACE --timeout=5m

# Verify rollback
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✅ Rollback Successful!                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📊 Current Status:${NC}"
kubectl get pods -n $KUBE_NAMESPACE -l app=${DEPLOYMENT%-deployment}

echo ""
echo -e "${BLUE}🔍 Current Image:${NC}"
kubectl get deployment/$DEPLOYMENT -n $KUBE_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
echo ""

echo -e "${GREEN}Usage for future rollbacks:${NC}"
echo "  Rollback to previous:       ./scripts/gke-rollback.sh $DEPLOYMENT"
echo "  Rollback to specific version: ./scripts/gke-rollback.sh $DEPLOYMENT 3"
echo ""
