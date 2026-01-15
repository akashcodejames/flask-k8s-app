# GKE Troubleshooting Guide

Common issues and solutions when deploying Flask K8s app to GKE with GitLab CI/CD.

## Table of Contents

1. [GKE Cluster Issues](#gke-cluster-issues)
2. [Artifact Registry Issues](#artifact-registry-issues)
3. [Image Pull Errors](#image-pull-errors)
4. [Deployment Failures](#deployment-failures)
5. [Ingress Issues](#ingress-issues)
6. [GitLab CI/CD Pipeline Issues](#gitlab-cicd-pipeline-issues)
7. [Networking and Connectivity](#networking-and-connectivity)
8. [Performance Issues](#performance-issues)
9. [Cost and Quota Issues](#cost-and-quota-issues)
10. [Useful Debugging Commands](#useful-debugging-commands)

---

## GKE Cluster Issues

### Issue: Cannot create GKE cluster - quota exceeded

**Error:**
```
ERROR: (gcloud.container.clusters.create) ResponseError: code=403
Quota 'CPUS' exceeded. Limit: 8.0 in region us-central1.
```

**Solution:**
```bash
# Check current quotas
gcloud compute project-info describe --project=$GCP_PROJECT_ID

# Request quota increase:
# 1. Go to Console → IAM & Admin → Quotas
# 2. Filter for "Compute Engine API" and your region
# 3. Select "CPUs" quota
# 4. Click "EDIT QUOTAS"
# 5. Request increase (usually approved within minutes for small increases)

# Or create cluster in different region with available quota
gcloud container clusters create flask-k8s-cluster \
  --zone=us-east1-b \
  --num-nodes=2
```

### Issue: kubectl cannot connect to cluster

**Error:**
```
Unable to connect to the server: dial tcp: lookup <cluster-ip>: no such host
```

**Solution:**
```bash
# Re-fetch cluster credentials
gcloud container clusters get-credentials flask-k8s-cluster \
  --zone=us-central1-a \
  --project=flask-k8s-production

# Verify kubeconfig
kubectl config view
kubectl config current-context

# Test connection
kubectl cluster-info
kubectl get nodes
```

### Issue: Cluster nodes not starting

**Error:**
```
All cluster resources were brought up, but: only 0 nodes out of 2 have registered
```

**Solution:**
```bash
# Check node pool status
gcloud container node-pools list --cluster=flask-k8s-cluster --zone=us-central1-a

# Describe node pool
gcloud container node-pools describe default-pool \
  --cluster=flask-k8s-cluster \
  --zone=us-central1-a

# Check events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# If persistent, recreate the node pool
gcloud container node-pools delete default-pool \
  --cluster=flask-k8s-cluster \
  --zone=us-central1-a

gcloud container node-pools create new-pool \
  --cluster=flask-k8s-cluster \
  --zone=us-central1-a \
  --num-nodes=2 \
  --machine-type=e2-medium
```

---

## Artifact Registry Issues

### Issue: Permission denied when pushing to Artifact Registry

**Error:**
```
denied: Permission "artifactregistry.repositories.uploadArtifacts" denied
```

**Solution:**
```bash
# Check current user's permissions
gcloud projects get-iam-policy $GCP_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)"

# Grant yourself artifactregistry.writer role
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/artifactregistry.writer"

# Re-configure Docker authentication
gcloud auth configure-docker us-central1-docker.pkg.dev
```

### Issue: Repository not found

**Error:**
```
DENIED: Repository <repository-name> not found
```

**Solution:**
```bash
# List existing repositories
gcloud artifacts repositories list --location=us-central1

# Create the repository if it doesn't exist
gcloud artifacts repositories create flask-app-images \
  --repository-format=docker \
  --location=us-central1 \
  --description="Docker images for Flask K8s application"

# Verify creation
gcloud artifacts repositories describe flask-app-images --location=us-central1
```

### Issue: Docker push is very slow

**Problem:** Pushing large images takes too long

**Solution:**
```bash
# 1. Use multi-stage builds to reduce image size
# Example Dockerfile:
FROM python:3.11-slim as builder
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM python:3.11-slim
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH

# 2. Use .dockerignore to exclude unnecessary files
cat > .dockerignore << EOF
.git
.gitignore
*.md
node_modules
venv
__pycache__
*.pyc
.pytest_cache
EOF

# 3. Use smaller base images
# Instead of: python:3.11
#Use: python:3.11-slim (50% smaller)
# Or: python:3.11-alpine (80% smaller, but may have compatibility issues)

# 4. Layer caching - order Dockerfile commands from least to most frequently changed
```

---

## Image Pull Errors

### Issue: ImagePullBackOff in GKE pods

**Error:**
```
Failed to pull image "us-central1-docker.pkg.dev/...": rpc error: code = Unknown desc = failed to pull and unpack image: failed to resolve reference
```

**Solution 1: Check IAM permissions**
```bash
# Get GKE service account
export GKE_SA=$(gcloud container clusters describe flask-k8s-cluster \
  --zone=us-central1-a \
  --format="get(nodeConfig.serviceAccount)")

echo "GKE Service Account: $GKE_SA"

# Grant Artifact Registry Reader permission
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:$GKE_SA" \
  --role="roles/artifactregistry.reader"

# Delete and recreate pods to retry
kubectl delete pods -n flask-app -l app=flask-backend
```

**Solution 2: Check image name and tag**
```bash
# List images in registry
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/$GCP_PROJECT_ID/flask-app-images

# Verify the exact image name in deployment
kubectl get deployment backend-deployment -n flask-app -o yaml | grep image:

# If image doesn't exist, build and push it
./scripts/gke-build-push.sh
```

**Solution 3: Check network connectivity**
```bash
# Test if GKE can reach Artifact Registry
kubectl run test-pull --image=us-central1-docker.pkg.dev/$GCP_PROJECT_ID/flask-app-images/flask-backend:latest --rm -it sh

# If firewall is blocking, check VPC firewall rules
gcloud compute firewall-rules list
```

---

## Deployment Failures

### Issue: Pods crashing (CrashLoopBackOff)

**Error:**
```
NAME                                  READY   STATUS             RESTARTS   AGE
backend-deployment-7d8f9c5b6d-abc12   0/1     CrashLoopBackOff   5          3m
```

**Solution:**
```bash
# Check pod logs
kubectl logs -n flask-app backend-deployment-7d8f9c5b6d-abc12

# Check previous logs (if pod restarted)
kubectl logs -n flask-app backend-deployment-7d8f9c5b6d-abc12 --previous

# Describe pod for events
kubectl describe pod -n flask-app backend-deployment-7d8f9c5b6d-abc12

# Common causes:
# 1. Application error on startup - fix code and rebuild
# 2. Missing environment variables - add to deployment.yaml
# 3. Port mismatch - verify containerPort matches application port
# 4. Health check failing too early - increase initialDelaySeconds
```

### Issue: Pods pending (not scheduling)

**Error:**
```
NAME                                  READY   STATUS    RESTARTS   AGE
backend-deployment-7d8f9c5b6d-abc12   0/1     Pending   0          5m
```

**Solution:**
```bash
# Describe pod to see why it's pending
kubectl describe pod -n flask-app backend-deployment-7d8f9c5b6d-abc12

# Common reasons:

# 1. Insufficient resources
#    Solution: Add more nodes or reduce resource requests
gcloud container clusters resize flask-k8s-cluster \
  --num-nodes=3 \
  --zone=us-central1-a

# 2. Node selector/affinity not matching
#    Solution: Remove node selectors or fix node labels

# 3. PersistentVolumeClaim not bound
#    Solution: Create PV or fix PVC
kubectl get pvc -n flask-app
```

### Issue: Deployment rollout timeout

**Error:**
```
error: timed out waiting for the condition
```

**Solution:**
```bash
# Check pod status
kubectl get pods -n flask-app

# Check events
kubectl get events -n flask-app --sort-by='.lastTimestamp' | tail -20

# Increase timeout
kubectl rollout status deployment/backend-deployment -n flask-app --timeout=10m

# Or manually check readiness
kubectl get deployment backend-deployment -n flask-app -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
```

---

## Ingress Issues

### Issue: Ingress not getting external IP

**Error:**
```
NAME                CLASS    HOSTS     ADDRESS   PORTS   AGE
flask-app-ingress   <none>   *                   80      10m
```

**Solution:**
```bash
# For GKE Ingress (can take 5-10 minutes)
kubectl describe ingress flask-app-ingress -n flask-app

# Check if HttpLoadBalancing addon is enabled
gcloud container clusters describe flask-k8s-cluster \ --zone=us-central1-a \
  --format="get(addonsConfig.httpLoadBalancing)"

# If disabled, enable it
gcloud container clusters update flask-k8s-cluster \
  --zone=us-central1-a \
  --update-addons=HttpLoadBalancing=ENABLED

# For nginx-ingress, check if controller is running
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

### Issue: 502 Bad Gateway

**Error:** Accessing ingress returns 502 error

**Solution:**
```bash
# Check backend pod status
kubectl get pods -n flask-app -l app=flask-backend

# Check if backend service has endpoints
kubectl get endpoints -n flask-app backend-service

# Check backend health endpoints
kubectl port-forward -n flask-app pod/<backend-pod-name> 5000:5000
curl http://localhost:5000/health

# Common causes:
# 1. Backend pods not ready - check readiness probe
# 2. Service selector doesn't match pod labels
# 3. Backend pods crashing - check logs
# 4. Port mismatch - verify service port and targetPort

# Fix service selector
kubectl edit svc backend-service -n flask-app
# Ensure selector matches deployment labels
```

### Issue: 404 Not Found on API paths

**Error:** Frontend works but `/api` paths return 404

**Solution:**
```bash
# Check ingress path configuration
kubectl get ingress flask-app-ingress -n flask-app -o yaml

# For GKE Ingress, verify path type
# Should be: pathType: Prefix

# For nginx-ingress, check rewrite rules
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /

# Test backend service directly
kubectl port-forward -n flask-app svc/backend-service 8080:80
curl http://localhost:8080/api/message
```

---

## GitLab CI/CD Pipeline Issues

### Issue: Pipeline fails at authentication step

**Error:**
```
ERROR: (gcloud.auth.activate-service-account) Invalid key file format
```

**Solution:**
```bash
# Verify GCP_SERVICE_KEY is correctly base64 encoded
# Locally test:
echo $GCP_SERVICE_KEY | base64 -d | jq .

# Re-encode the service account key
cat ~/gitlab-deployer-key.json | base64 > ~/key-base64.txt
cat ~/key-base64.txt | pbcopy  # Copy to clipboard

# Update GitLab CI/CD variable:
# 1. Settings → CI/CD → Variables
# 2. Edit GCP_SERVICE_KEY
# 3. Paste new value
# 4. Ensure "Masked" is checked
```

### Issue: Docker build fails in pipeline

**Error:**
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

**Solution:**
```yaml
# Ensure Docker-in-Docker service is enabled in .gitlab-ci.yml
build:backend:
  image: docker:24-dind
  services:
    - docker:24-dind
  variables:
    DOCKER_TLS_CERTDIR: ""
```

### Issue: kubectl command not found in pipeline

**Error:**
```
/bin/sh: kubectl: not found
```

**Solution:**
```yaml
# Install kubectl in the job
deploy:production:
  image: google/cloud-sdk:alpine
  before_script:
    - gcloud components install kubectl --quiet
```

### Issue: Pipeline succeeds but deployment not updated

**Problem:** Pipeline shows success but pods still running old version

**Solution:**
```bash
# Check if image tag actually changed
kubectl get deployment backend-deployment -n flask-app -o jsonpath='{.spec.template.spec.containers[0].image}'

# Force deployment update even with same tag
kubectl rollout restart deployment/backend-deployment -n flask-app

# Better: Always use unique tags (commit SHA)
IMAGE_TAG: ${CI_COMMIT_SHORT_SHA}  # Instead of 'latest'
```

### Issue: GitLab runner runs out of disk space

**Error:**
```
no space left on device
```

**Solution:**
```bash
# On the runner machine, clean up Docker
docker system prune -a -f

# Add cleanup job to pipeline
cleanup:
  stage: .post
  script:
    - docker system prune -f
  when: always
```

---

## Networking and Connectivity

### Issue: Frontend cannot reach backend

**Error:** Frontend loads but API calls fail with network errors

**Solution:**
```bash
# 1. Check if backend service exists
kubectl get svc -n flask-app backend-service

# 2. Test backend from frontend pod
kubectl exec -it -n flask-app <frontend-pod> -- wget -O- http://backend-service/api/message

# 3. Check CORS settings in backend
# Ensure Flask app has CORS enabled for your frontend
from flask_cors import CORS
CORS(app)

# 4. Update frontend to use correct backend URL
# In index.html, API URL should point to ingress path
const API_URL = '/api/message';  // Not 'http://backend-service'
```

### Issue: External users cannot access application

**Problem:** Application works locally but not from internet

**Solution:**
```bash
# Check if ingress has external IP
kubectl get ingress -n flask-app

# Check if firewall is blocking
gcloud compute firewall-rules list | grep allow-http

# Create firewall rule if needed
gcloud compute firewall-rules create allow-http \
  --allow tcp:80 \
  --source-ranges 0.0.0.0/0

gcloud compute firewall-rules create allow-https \
  --allow tcp:443 \
  --source-ranges 0.0.0.0/0

# Check Network Endpoint Groups (for GKE Ingress)
gcloud compute network-endpoint-groups list
```

---

## Performance Issues

### Issue: Slow response times

**Problem:** Application responds slowly

**Solution:**
```bash
# 1. Check pod resource usage
kubectl top pods -n flask-app

# If near limits, increase resources
kubectl edit deployment backend-deployment -n flask-app
# Increase CPU/memory limits

# 2. Increase replica count
kubectl scale deployment backend-deployment --replicas=4 -n flask-app

# 3. Enable autoscaling
kubectl autoscale deployment backend-deployment \
  --min=2 --max=10 \
  --cpu-percent=70 \
  -n flask-app

# 4. Check for slow database queries or external API calls
kubectl logs -n flask-app -l app=flask-backend | grep -i "slow\|timeout"
```

### Issue: High memory usage

**Problem:** Pods getting OOMKilled

**Solution:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n flask-app | grep -i "oomkilled"

# Increase memory limits
kubectl edit deployment backend-deployment -n flask-app
# Change:
resources:
  limits:
    memory: "512Mi"  # Increase from 256Mi

# Check for memory leaks in application
# Add memory profiling to your app
```

---

## Cost and Quota Issues

### Issue: Unexpected high costs

**Problem:** GCP bill is higher than expected

**Solution:**
```bash
# Check current resource usage
kubectl get nodes
kubectl top nodes

# Reduce costs:

# 1. Use smaller node types
gcloud container node-pools create small-pool \
  --cluster=flask-k8s-cluster \
  --machine-type=e2-small \
  --num-nodes=2

# 2. Use preemptible/spot instances (60-80% cheaper)
gcloud container node-pools create spot-pool \
  --cluster=flask-k8s-cluster \
  --machine-type=e2-medium \
  --num-nodes=2 \
  --spot

# 3. Enable cluster autoscaling
gcloud container clusters update flask-k8s-cluster \
  --enable-autoscaling \
  --min-nodes=1 \
  --max-nodes=3 \
  --zone=us-central1-a

# 4. Delete unused load balancers
kubectl get svc --all-namespaces | grep LoadBalancer
# Delete unused services

# 5. Monitor costs
# Go to: Console → Billing → Cost Table
# Filter by: Service = "Kubernetes Engine" or "Compute Engine"
```

---

## Useful Debugging Commands

### Pod Debugging

```bash
# Get pod status
kubectl get pods -n flask-app

# Describe pod (shows events)
kubectl describe pod <pod-name> -n flask-app

# View logs
kubectl logs -n flask-app <pod-name>
kubectl logs -n flask-app <pod-name> --previous  # Previous crash logs
kubectl logs -n flask-app -l app=flask-backend -f  # Follow logs

# Execute command in pod
kubectl exec -it -n flask-app <pod-name> -- /bin/sh
kubectl exec -it -n flask-app <pod-name> -- env  # Check environment variables

# Port forward to pod
kubectl port-forward -n flask-app <pod-name> 5000:5000

# Copy files from pod
kubectl cp -n flask-app <pod-name>:/app/logs/app.log ./local-app.log
```

### Deployment Debugging

```bash
# Check deployment status
kubectl get deployment -n flask-app
kubectl describe deployment backend-deployment -n flask-app

# View deployment history
kubectl rollout history deployment/backend-deployment -n flask-app

# Check replica sets
kubectl get rs -n flask-app

# Scale deployment
kubectl scale deployment/backend-deployment --replicas=3 -n flask-app
```

### Service and Network Debugging

```bash
# Check services
kubectl get svc -n flask-app
kubectl describe svc backend-service -n flask-app

# Check endpoints (should match pod IPs)
kubectl get endpoints -n flask-app

# Test service from within cluster
kubectl run test-pod --image=curlimages/curl -it --rm -- sh
curl http://backend-service.flask-app.svc.cluster.local/health

# Check ingress
kubectl get ingress -n flask-app
kubectl describe ingress flask-app-ingress -n flask-app
```

### Resource Debugging

```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n flask-app

# Check resource quotas
kubectl get resourcequota -n flask-app
kubectl describe resourcequota -n flask-app

# Check events
kubectl get events -n flask-app --sort-by='.lastTimestamp'
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -50
```

### GKE-specific Debugging

```bash
# Check cluster info
gcloud container clusters describe flask-k8s-cluster --zone=us-central1-a

# Check node pool
gcloud container node-pools list --cluster=flask-k8s-cluster --zone=us-central1-a

# View cluster logs in Cloud Logging
gcloud logging read "resource.type=k8s_cluster AND resource.labels.cluster_name=flask-k8s-cluster" --limit=50

# Check IAM permissions
gcloud projects get-iam-policy $GCP_PROJECT_ID
```

---

## Getting Help

### Resources

- **GKE Documentation**: https://cloud.google.com/kubernetes-engine/docs
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **Artifact Registry Docs**: https://cloud.google.com/artifact-registry/docs
- **GitLab CI/CD Docs**: https://docs.gitlab.com/ee/ci/

### Support Channels

- **GCP Support**: https://cloud.google.com/support
- **Stack Overflow**: Tag your questions with `google-kubernetes-engine`, `kubectl`, `gitlab-ci`
- **Kubernetes Slack**: https://kubernetes.slack.com

### Diagnostic Bundle

When asking for help, provide:

```bash
# Collect diagnostic information
echo "=== Cluster Info ===" > diagnostic.txt
kubectl cluster-info >> diagnostic.txt

echo "\n=== Nodes ===" >> diagnostic.txt
kubectl get nodes -o wide >> diagnostic.txt

echo "\n=== Pods ===" >> diagnostic.txt
kubectl get pods -n flask-app -o wide >> diagnostic.txt

echo "\n=== Events ===" >> diagnostic.txt
kubectl get events -n flask-app --sort-by='.lastTimestamp' >> diagnostic.txt

echo "\n=== Ingress ===" >> diagnostic.txt
kubectl describe ingress flask-app-ingress -n flask-app >> diagnostic.txt

# Share diagnostic.txt when asking for help
```

---

**Related Guides:**
- [GKE Setup Guide](./GKE-SETUP.md)
- [Artifact Registry Setup](./ARTIFACT-REGISTRY-SETUP.md)
- [Deployment Guide](./GKE-DEPLOYMENT-GUIDE.md)
- [GitLab CI/CD Guide](./GKE-GITLAB-CI-CD-GUIDE.md)
