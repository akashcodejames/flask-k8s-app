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
export REGION="${REGION:-asia-south1}"
export REPOSITORY_NAME="${REPOSITORY_NAME:-flask-app-images}"
export IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')}"
export REGISTRY_URL="$REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME"

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Build and Push to Artifact Registry Script       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Project ID:   $GCP_PROJECT_ID"
echo "  Region:       $REGION"
echo "  Repository:   $REPOSITORY_NAME"
echo "  Image Tag:    $IMAGE_TAG"
echo "  Registry URL: $REGISTRY_URL"
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}❌ gcloud CLI not found. Please install it first.${NC}"
    exit 1
fi

# Check if Docker is running
if ! docker ps &> /dev/null; then
    echo -e "${RED}❌ Docker is not running. Please start Docker.${NC}"
    exit 1
fi

# Check authentication
echo -e "${YELLOW}🔐 Checking GCP authentication...${NC}"
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    echo -e "${RED}❌ Not authenticated to GCP. Run: gcloud auth login${NC}"
    exit 1
fi

# Configure Docker for Artifact Registry
echo -e "${YELLOW}🔧 Configuring Docker authentication...${NC}"
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Build backend
echo ""
echo -e "${GREEN}🔨 Building backend image...${NC}"
docker build -t flask-backend:$IMAGE_TAG ./backend
docker tag flask-backend:$IMAGE_TAG flask-backend:latest

# Build frontend
echo""
echo -e "${GREEN}🔨 Building frontend image...${NC}"
docker build -t flask-frontend:$IMAGE_TAG ./frontend
docker tag flask-frontend:$IMAGE_TAG flask-frontend:latest

# Tag backend for Artifact Registry
echo ""
echo -e "${GREEN}🏷️  Tagging backend image...${NC}"
docker tag flask-backend:$IMAGE_TAG $REGISTRY_URL/flask-backend:$IMAGE_TAG
docker tag flask-backend:$IMAGE_TAG $REGISTRY_URL/flask-backend:latest

# Tag frontend for Artifact Registry
echo -e "${GREEN}🏷️  Tagging frontend image...${NC}"
docker tag flask-frontend:$IMAGE_TAG $REGISTRY_URL/flask-frontend:$IMAGE_TAG
docker tag flask-frontend:$IMAGE_TAG $REGISTRY_URL/flask-frontend:latest

# Push backend to Artifact Registry
echo ""
echo -e "${GREEN}⬆️  Pushing backend to Artifact Registry...${NC}"
docker push $REGISTRY_URL/flask-backend:$IMAGE_TAG
docker push $REGISTRY_URL/flask-backend:latest

# Push frontend to Artifact Registry
echo -e "${GREEN}⬆️  Pushing frontend to Artifact Registry...${NC}"
docker push $REGISTRY_URL/flask-frontend:$IMAGE_TAG
docker push $REGISTRY_URL/flask-frontend:latest

# Success message
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            ✅ Images pushed successfully!            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Backend Image:${NC}"
echo "  $REGISTRY_URL/flask-backend:$IMAGE_TAG"
echo "  $REGISTRY_URL/flask-backend:latest"
echo ""
echo -e "${BLUE}Frontend Image:${NC}"
echo "  $REGISTRY_URL/flask-frontend:$IMAGE_TAG"
echo "  $REGISTRY_URL/flask-frontend:latest"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Run: ./scripts/gke-deploy.sh"
echo "  2. Or push to GitLab to trigger CI/CD pipeline"
echo ""
