#!/bin/bash
set-e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
export GCP_PROJECT_ID="${GCP_PROJECT_ID:-flask-k8s-production}"
export REGION="${REGION:-asia-south1}"
export ZONE="${ZONE:-asia-south1-a}"
export CLUSTER_NAME="${CLUSTER_NAME:-flask-k8s-cluster}"
export REPOSITORY_NAME="${REPOSITORY_NAME:-flask-app-images}"
export IMAGE_TAG="${IMAGE_TAG:-latest}"
export KUBE_NAMESPACE="${KUBE_NAMESPACE:-flask-app}"
export REGISTRY_URL="$REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME"

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Deploy to GKE Cluster Script                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Project ID:   $GCP_PROJECT_ID"
echo "  Region:       $REGION"
echo "  Zone:         $ZONE"
echo "  Cluster:      $CLUSTER_NAME"
echo "  Namespace:    $KUBE_NAMESPACE"
echo "  Image Tag:    $IMAGE_TAG"
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}❌ gcloud CLI not found. Please install it first.${NC}"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install it first.${NC}"
    exit 1
fi

# Get GKE credentials
echo -e "${YELLOW}🔐 Getting GKE cluster credentials...${NC}"
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$GCP_PROJECT_ID

# Verify connection
echo -e "${YELLOW}✓ Verifying cluster connection...${NC}"
kubectl cluster-info | head -1

# Update image tags in manifests
echo ""
echo -e "${GREEN}📝 Updating deployment manifests with new image tags...${NC}"
sed -i.bak "s|image: .*flask-backend.*|image: $REGISTRY_URL/flask-backend:$IMAGE_TAG|g" k8s/gke/backend-deployment.yaml
sed -i.bak "s|image: .*flask-frontend.*|image: $REGISTRY_URL/flask-frontend:$IMAGE_TAG|g" k8s/gke/frontend-deployment.yaml

# Deploy namespace
echo ""
echo -e "${GREEN}📦 Creating namespace...${NC}"
kubectl apply -f k8s/gke/namespace.yaml

# Deploy backend
echo -e "${GREEN}🚀 Deploying backend...${NC}"
kubectl apply -f k8s/gke/backend-deployment.yaml
kubectl apply -f k8s/gke/backend-service.yaml

# Deploy frontend
echo -e "${GREEN}🚀 Deploying frontend...${NC}"
kubectl apply -f k8s/gke/frontend-deployment.yaml
kubectl apply -f k8s/gke/frontend-service.yaml

# Deploy ingress
echo -e "${GREEN}🌐 Deploying ingress...${NC}"
if kubectl apply -f k8s/gke/ingress-nginx.yaml 2>/dev/null; then
    echo "  ✓ nginx ingress deployed"
else
    echo "  ℹ️  nginx ingress failed, trying GKE ingress..."
    kubectl apply -f k8s/gke/ingress-gke.yaml
    echo "  ✓ GKE ingress deployed"
fi

# Wait for backend rollout
echo ""
echo -e "${YELLOW}⏳ Waiting for backend deployment to complete...${NC}"
kubectl rollout status deployment/backend-deployment -n $KUBE_NAMESPACE --timeout=5m

# Wait for frontend rollout
echo -e "${YELLOW}⏳ Waiting for frontend deployment to complete...${NC}"
kubectl rollout status deployment/frontend-deployment -n $KUBE_NAMESPACE --timeout=5m

# Restore original manifests
echo ""
echo -e "${YELLOW}🔄 Restoring original manifests...${NC}"
mv k8s/gke/backend-deployment.yaml.bak k8s/gke/backend-deployment.yaml 2>/dev/null || true
mv k8s/gke/frontend-deployment.yaml.bak k8s/gke/frontend-deployment.yaml 2>/dev/null || true

# Get deployment status
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✅ Deployment Successful!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📊 Deployment Status:${NC}"
kubectl get pods -n $KUBE_NAMESPACE
echo ""
echo -e "${BLUE}🌐 Services:${NC}"
kubectl get svc -n $KUBE_NAMESPACE
echo ""
echo -e "${BLUE}🔗 Ingress:${NC}"
kubectl get ingress -n $KUBE_NAMESPACE

# Get external IP
echo ""
EXTERNAL_IP=$(kubectl get ingress -n $KUBE_NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
echo -e "${YELLOW}📍 External IP: ${NC}$EXTERNAL_IP"

if [ "$EXTERNAL_IP" != "Pending..." ]; then
    echo ""
    echo -e "${GREEN}🎉 Application URLs:${NC}"
    echo "  Frontend: http://$EXTERNAL_IP"
    echo "  API:      http://$EXTERNAL_IP/api/message"
    echo "  Health:   http://$EXTERNAL_IP/health"
else
    echo -e "${YELLOW}⏳ External IP is being provisioned. Check again in a few minutes:${NC}"
    echo "  kubectl get ingress -n $KUBE_NAMESPACE"
fi
echo ""
