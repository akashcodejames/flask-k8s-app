# GKE Deployment Guide

This guide walks you through deploying your Flask K8s application to Google Kubernetes Engine (GKE) using images from Artifact Registry.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Prepare Kubernetes Manifests](#prepare-kubernetes-manifests)
3. [Deploy Application to GKE](#deploy-application-to-gke)
4. [Configure External Access](#configure-external-access)
5. [DNS and Domain Setup](#dns-and-domain-setup)
6. [SSL/TLS Configuration](#ssltls-configuration)
7. [Monitor Deployment](#monitor-deployment)
8. [Application Updates](#application-updates)
9. [Rollback Strategy](#rollback-strategy)
10. [Next Steps](#next-steps)

---

## Prerequisites

Before deploying, ensure you have completed:

- ✅ [GKE Cluster Setup](./GKE-SETUP.md) - GKE cluster created and running
- ✅ [Artifact Registry Setup](./ARTIFACT-REGISTRY-SETUP.md) - Images pushed to registry
- ✅ kubectl configured for your GKE cluster
- ✅ Images available in Artifact Registry

**Verify prerequisites:**

```bash
# Check GKE cluster
gcloud container clusters list
kubectl cluster-info

# Check images in Artifact Registry
gcloud artifacts docker images list \
  asia-south1-docker.pkg.dev/flask-k8s-production/flask-app-images

# Verify kubectl context
kubectl config current-context
```

---

## Prepare Kubernetes Manifests

The GKE manifests are located in `k8s/gke/` directory. They are configured to use images from Artifact Registry.

### Understanding the Manifest Structure

```
k8s/gke/
├── namespace.yaml              # Creates flask-app namespace
├── backend-deployment.yaml     # Backend pods (Flask API)
├── backend-service.yaml        # Backend ClusterIP service
├── frontend-deployment.yaml    # Frontend pods (Nginx)
├── frontend-service.yaml       # Frontend ClusterIP service
├── ingress-gke.yaml           # GKE Ingress (Google Load Balancer)
└── ingress-nginx.yaml         # nginx-ingress (Alternative)
```

### Image References

All deployments reference images from your Artifact Registry:

```yaml
# Format:
image: REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY_NAME/IMAGE_NAME:TAG

# Example:
image: asia-south1-docker.pkg.dev/flask-k8s-production/flask-app-images/flask-backend:latest
```

### Configuration Variables

Set these environment variables for easy deployment:

```bash
# Create gke-deploy-config.env
cat > gke-deploy-config.env << 'EOF'
# GCP Configuration
export GCP_PROJECT_ID="flask-k8s-production"
export REGION="asia-south1"
export ZONE="asia-south1-a"

# Artifact Registry
export REPOSITORY_NAME="flask-app-images"
export REGISTRY_URL="$REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPOSITORY_NAME"

# Application
export IMAGE_TAG="latest"  # Or specific version like v1.0.0
export BACKEND_REPLICAS="2"
export FRONTEND_REPLICAS="2"

# Domain (if you have one)
export APP_DOMAIN="flask-app.example.com"  # Change to your domain
EOF

# Load configuration
source gke-deploy-config.env
```

---

## Deploy Application to GKE

### Step 1: Get GKE Credentials

```bash
# Configure kubectl to use your GKE cluster
gcloud container clusters get-credentials flask-k8s-cluster \
  --zone=asia-south1-a \
  --project=flask-k8s-production
```

### Step 2: Create Namespace

```bash
# Apply namespace configuration
kubectl apply -f k8s/gke/namespace.yaml

# Verify namespace creation
kubectl get namespace flask-app

# Set as default namespace
kubectl config set-context --current --namespace=flask-app
```

### Step 3: Deploy Backend

```bash
# Deploy backend deployment and service
kubectl apply -f k8s/gke/backend-deployment.yaml
kubectl apply -f k8s/gke/backend-service.yaml

# Watch deployment progress
kubectl rollout status deployment/backend-deployment -n flask-app

# Verify pods are running
kubectl get pods -n flask-app -l app=flask-backend
```

**Expected output:**
```
NAME                                  READY   STATUS    RESTARTS   AGE
backend-deployment-7d8f9c5b6d-abc12   1/1     Running   0          30s
backend-deployment-7d8f9c5b6d-def34   1/1     Running   0          30s
```

### Step 4: Deploy Frontend

```bash
# Deploy frontend deployment and service
kubectl apply -f k8s/gke/frontend-deployment.yaml
kubectl apply -f k8s/gke/frontend-service.yaml

# Watch deployment progress
kubectl rollout status deployment/frontend-deployment -n flask-app

# Verify pods are running
kubectl get pods -n flask-app -l app=flask-frontend
```

### Step 5: Deploy Ingress

Choose either GKE Ingress or nginx-ingress:

**Option A: GKE Ingress (Google Cloud Load Balancer)**

```bash
# Deploy GKE ingress
kubectl apply -f k8s/gke/ingress-gke.yaml

# Wait for load balancer provisioning (takes 5-10 minutes)
kubectl get ingress -n flask-app --watch

# Get the external IP
kubectl get ingress flask-app-ingress -n flask-app
```

**Option B: nginx-ingress (Faster, more flexible)**

```bash
# First, ensure nginx-ingress controller is installed (from GKE-SETUP.md)
kubectl get pods -n ingress-nginx

# Deploy nginx ingress
kubectl apply -f k8s/gke/ingress-nginx.yaml

# Get the LoadBalancer IP
kubectl get ingress flask-app-ingress -n flask-app
```

### Step 6: All-in-One Deployment

Or deploy everything at once:

```bash
# Deploy all manifests
kubectl apply -f k8s/gke/

# Wait for all deployments
kubectl wait --for=condition=available --timeout=300s \
  deployment/backend-deployment -n flask-app
kubectl wait --for=condition=available --timeout=300s \
  deployment/frontend-deployment -n flask-app

# Verify everything is running
kubectl get all -n flask-app
```

---

## Configure External Access

### Get the External IP

```bash
# For GKE Ingress
kubectl get ingress flask-app-ingress -n flask-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# For nginx-ingress controller
kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Save the IP
export EXTERNAL_IP=$(kubectl get ingress flask-app-ingress -n flask-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP: $EXTERNAL_IP"
```

### Test Access Using IP

```bash
# Test frontend (replace with your actual IP)
curl http://$EXTERNAL_IP

# Test backend API
curl http://$EXTERNAL_IP/api/message

# Or use browser
echo "Frontend: http://$EXTERNAL_IP"
echo "API: http://$EXTERNAL_IP/api/message"
```

---

## DNS and Domain Setup

### Option 1: Using /etc/hosts (Local Testing)

For local testing without a real domain:

```bash
# Add to /etc/hosts (macOS/Linux)
echo "$EXTERNAL_IP flask-app.local" | sudo tee -a /etc/hosts

# Verify
ping flask-app.local

# Access application
open http://flask-app.local
```

### Option 2: Real Domain Setup

If you have a domain name (e.g., purchased from Google Domains, GoDaddy, etc.):

**Step 1: Create DNS A Record**

```bash
# Option A: Using Google Cloud DNS

# Create a DNS zone
gcloud dns managed-zones create flask-app-zone \
  --dns-name="flask-app.example.com." \
  --description="Flask K8s App DNS Zone"

# Add A record pointing to load balancer IP
gcloud dns record-sets transaction start --zone=flask-app-zone

gcloud dns record-sets transaction add $EXTERNAL_IP \
  --name="flask-app.example.com." \
  --ttl=300 \
  --type=A \
  --zone=flask-app-zone

gcloud dns record-sets transaction execute --zone=flask-app-zone

# Get nameservers
gcloud dns managed-zones describe flask-app-zone \
  --format="get(nameServers)"
```

**Step 2: Update Domain Registrar**

1. Go to your domain registrar (GoDaddy, Namecheap, etc.)
2. Update nameservers to Google Cloud DNS nameservers (from above)
3. Or add an A record directly:
   - **Name**: `@` or `flask-app`
   - **Type**: `A`
   - **Value**: Your `$EXTERNAL_IP`
   - **TTL**: `300` or `3600`

**Step 3: Wait for DNS Propagation**

```bash
# Check DNS propagation (can take up to 48 hours, usually 5-30 minutes)
nslookup flask-app.example.com

# Or use online tools:
# - https://www.whatsmydns.net/
# - https://dnschecker.org/
```

**Step 4: Update Ingress with Domain**

Edit `k8s/gke/ingress-gke.yaml` or `k8s/gke/ingress-nginx.yaml`:

```yaml
spec:
  rules:
  - host: flask-app.example.com  # Add your domain
    http:
      paths:
      # ... rest of configuration
```

Apply changes:

```bash
kubectl apply -f k8s/gke/ingress-gke.yaml
```

---

## SSL/TLS Configuration

### Option 1: Google-Managed SSL Certificate (GKE Ingress Only)

Automatic SSL certificate management (easiest):

**Step 1: Create ManagedCertificate**

```bash
# Create managed-cert.yaml
cat > k8s/gke/managed-cert.yaml << EOF
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: flask-app-cert
  namespace: flask-app
spec:
  domains:
    - flask-app.example.com  # Your domain
EOF

# Apply
kubectl apply -f k8s/gke/managed-cert.yaml
```

**Step 2: Update Ingress**

Edit `k8s/gke/ingress-gke.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: flask-app-ingress
  namespace: flask-app
  annotations:
    kubernetes.io/ingress.class: "gce"
    networking.gke.io/managed-certificates: "flask-app-cert"  # Add this
    kubernetes.io/ingress.allow-http: "true"
spec:
  # ... rest of configuration
```

Apply:

```bash
kubectl apply -f k8s/gke/ingress-gke.yaml

# Check certificate provisioning status (takes 10-30 minutes)
kubectl describe managedcertificate flask-app-cert -n flask-app

# Wait for status: Active
```

### Option 2: cert-manager with Let's Encrypt (nginx-ingress)

Free SSL certificates from Let's Encrypt:

**Step 1: Install cert-manager**

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Verify installation
kubectl get pods -n cert-manager
```

**Step 2: Create ClusterIssuer**

```bash
# Create letsencrypt-issuer.yaml
cat > k8s/gke/letsencrypt-issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # Change this
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Apply
kubectl apply -f k8s/gke/letsencrypt-issuer.yaml
```

**Step 3: Update nginx Ingress**

Edit `k8s/gke/ingress-nginx.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: flask-app-ingress
  namespace: flask-app
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Add this
spec:
  tls:  # Add this section
  - hosts:
    - flask-app.example.com
    secretName: flask-app-tls
  rules:
  - host: flask-app.example.com
    # ... rest of configuration
```

Apply:

```bash
kubectl apply -f k8s/gke/ingress-nginx.yaml

# Check certificate
kubectl get certificate -n flask-app
kubectl describe certificate flask-app-tls -n flask-app
```

**Step 4: Verify HTTPS**

```bash
# Test HTTPS
curl https://flask-app.example.com

# Check certificate
curl -vI https://flask-app.example.com 2>&1 | grep -i "SSL\|TLS\|certificate"
```

---

## Monitor Deployment

### Check Pod Status

```bash
# Get all pods
kubectl get pods -n flask-app

# Watch pods in real-time
kubectl get pods -n flask-app --watch

# Get detailed pod information
kubectl describe pod <pod-name> -n flask-app

# Check pod logs
kubectl logs -n flask-app -l app=flask-backend
kubectl logs -n flask-app -l app=flask-frontend

# Follow logs in real-time
kubectl logs -n flask-app -l app=flask-backend -f
```

### Check Services

```bash
# Get all services
kubectl get svc -n flask-app

# Describe service
kubectl describe svc backend-service -n flask-app
kubectl describe svc frontend-service -n flask-app
```

### Check Ingress

```bash
# Get ingress
kubectl get ingress -n flask-app

# Describe ingress
kubectl describe ingress flask-app-ingress -n flask-app

# Check ingress events
kubectl get events -n flask-app --sort-by='.lastTimestamp' | grep ingress
```

### Health Checks

```bash
# Check if health endpoints work
export EXTERNAL_IP=$(kubectl get ingress flask-app-ingress -n flask-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test backend health
curl http://$EXTERNAL_IP/health

# Test API endpoint
curl http://$EXTERNAL_IP/api/message
```

### Resource Usage

```bash
# Check resource usage
kubectl top pods -n flask-app
kubectl top nodes

# Check resource quotas and limits
kubectl describe deployment backend-deployment -n flask-app | grep -A 5 "Limits\|Requests"
```

### View Events

```bash
# See all events in namespace
kubectl get events -n flask-app --sort-by='.lastTimestamp'

# Filter for warnings
kubectl get events -n flask-app --field-selector type=Warning
```

---

## Application Updates

### Update Strategy 1: Rolling Update (Default)

```bash
# Update image tag in deployment
kubectl set image deployment/backend-deployment \
  flask-backend=asia-south1-docker.pkg.dev/flask-k8s-production/flask-app-images/flask-backend:v1.1.0 \
  -n flask-app

# Watch rollout
kubectl rollout status deployment/backend-deployment -n flask-app

# Check rollout history
kubectl rollout history deployment/backend-deployment -n flask-app
```

### Update Strategy 2: Update Manifest and Apply

```bash
# Edit k8s/gke/backend-deployment.yaml
# Change image tag from :latest to :v1.1.0

# Apply changes
kubectl apply -f k8s/gke/backend-deployment.yaml

# Verify update
kubectl get pods -n flask-app -l app=flask-backend
```

### Update Strategy 3: Automated Script

```bash
# Use the deployment script (created later)
./scripts/gke-deploy.sh
```

### Zero-Downtime Updates

The rolling update strategy ensures zero downtime:

```yaml
# In deployment.yaml
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # Max 1 extra pod during update
      maxUnavailable: 0  # Always keep 2 pods running
```

---

## Rollback Strategy

### Quick Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/backend-deployment -n flask-app

# Verify rollback
kubectl rollout status deployment/backend-deployment -n flask-app

# Check which revision
kubectl rollout history deployment/backend-deployment -n flask-app
```

### Rollback to Specific Revision

```bash
# View rollout history with details
kubectl rollout history deployment/backend-deployment -n flask-app

# Rollback to specific revision
kubectl rollout undo deployment/backend-deployment --to-revision=2 -n flask-app
```

### Pause and Resume Rollout

```bash
# Pause rollout (useful if you see issues)
kubectl rollout pause deployment/backend-deployment -n flask-app

# Resume rollout
kubectl rollout resume deployment/backend-deployment -n flask-app
```

---

## Troubleshooting

### Issue: Pods not starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n flask-app

# Common issues:
# 1. ImagePullBackOff - Check image name and Artifact Registry permissions
# 2. CrashLoopBackOff - Check application logs
# 3. Pending - Check resource availability
```

### Issue: ImagePullBackOff

```bash
# Check if GKE can pull from Artifact Registry
kubectl describe pod <pod-name> -n flask-app | grep -A 10 Events

# Grant permissions to GKE service account
gcloud projects add-iam-policy-binding flask-k8s-production \
  --member="serviceAccount:$(gcloud container clusters describe flask-k8s-cluster --zone=us-central1-a --format='get(nodeConfig.serviceAccount)')" \
  --role="roles/artifactregistry.reader"
```

### Issue: Ingress not working

```bash
# Check ingress status
kubectl describe ingress flask-app-ingress -n flask-app

# Check backend services
kubectl get svc -n flask-app

# Verify health checks pass
kubectl get pods -n flask-app
curl http://<pod-ip>:5000/health
```

### Issue: 502 Bad Gateway

```bash
# Backend pods not ready
kubectl get pods -n flask-app -l app=flask-backend

# Check health probes
kubectl describe deployment backend-deployment -n flask-app | grep -A 10 Liveness

# Check service endpoints
kubectl get endpoints -n flask-app
```

---

## Deployment Checklist

Use this checklist for each deployment:

- [ ] Images built and pushed to Artifact Registry
- [ ] kubectl context set to correct GKE cluster
- [ ] Namespace created
- [ ] Backend deployment and service applied
- [ ] Frontend deployment and service applied
- [ ] Ingress configured and applied
- [ ] External IP obtained
- [ ] DNS configured (if using domain)
- [ ] SSL/TLS configured (if using HTTPS)
- [ ] Health checks passing
- [ ] Application accessible via browser
- [ ] Monitoring and logging verified

---

## Next Steps

✅ **Application deployed to GKE!**

Continue with:

1. **[GitLab CI/CD Setup](./GKE-GITLAB-CI-CD-GUIDE.md)** - Automate future deployments
2. **[Monitoring Setup](./GKE-TROUBLESHOOTING.md)** - Set up alerts and monitoring
3. **[Production Hardening](./GKE-PRODUCTION-CHECKLIST.md)** - Security and optimization

---

## Additional Resources

- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

---

**Next Guide**: [GitLab CI/CD Setup →](./GKE-GITLAB-CI-CD-GUIDE.md)
