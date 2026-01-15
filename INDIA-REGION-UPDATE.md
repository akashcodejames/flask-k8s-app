# India Region Update Summary

All GKE documentation and configuration files have been updated to use India (Mumbai) region as the default.

## Changes Made

### Default Region Changed
- **From:** `us-central1` (Iowa, USA)
- **To:** `asia-south1` (Mumbai, India) ⭐

### Default Zone Changed
- **From:** `us-central1-a`
- **To:** `asia-south1-a`

---

## Files Updated

### Configuration Files (6 files)

1. **gke-config.env.example**
   - Default region: `asia-south1`
   - Default zone: `asia-south1-a`
   - Updated comments to mention Mumbai, India

2. **scripts/gke-build-push.sh**
   - Default REGION: `asia-south1`

3. **scripts/gke-deploy.sh**
   - Default REGION: `asia-south1`
   - Default ZONE: `asia-south1-a`

4. **scripts/gke-rollback.sh**
   - Default ZONE: `asia-south1-a`

5. **k8s/gke/backend-deployment.yaml**
   - Image URL: `asia-south1-docker.pkg.dev/flask-k8s-production/flask-app-images/flask-backend:latest`

6. **k8s/gke/frontend-deployment.yaml**
   - Image URL: `asia-south1-docker.pkg.dev/flask-k8s-production/flask-app-images/flask-frontend:latest`

### Documentation Files (5 files)

1. **GKE-SETUP.md**
   - Region recommendations now list India regions first
   - Added: `asia-south1` (Mumbai) - marked as **Best for India** ⭐
   - Added: `asia-south2` (Delhi) - Alternative for North India
   - All example commands updated to use `asia-south1`
   - kubectl context examples updated

2. **ARTIFACT-REGISTRY-SETUP.md**
   - All region examples changed to `asia-south1`
   - Docker authentication examples updated
   - Repository URL examples updated

3. **GKE-DEPLOYMENT-GUIDE.md**
   - All deployment examples use `asia-south1` and `asia-south1-a`
   - Image references updated

4. **README.md**
   - Quick start guide uses `asia-south1` region
   - Artifact Registry setup examples updated

5. **GKE-GITLAB-CI-CD-GUIDE.md**
   - Examples reference Asia region where applicable

---

## Region Information

### Asia-South1 (Mumbai, India)

**Zones:**
- `asia-south1-a`
- `asia-south1-b`  
- `asia-south1-c`

**Benefits:**
- ✅ Lowest latency for users in India
- ✅ Data residency in India
- ✅ Best performance for Indian users
- ✅ Competitive pricing

**Alternative India Region:**
- **asia-south2** (Delhi, India) - Good for North India

---

## What Stays the Same

- Project ID examples: `flask-k8s-production`
- Repository name: `flask-app-images`
- Cluster name: `flask-k8s-cluster`
- All kubectl commands and deployment procedures
- GitLab CI/CD pipeline structure
- Kubernetes manifest structure

---

## Usage Examples

### Create GKE Cluster in Mumbai
```bash
gcloud container clusters create flask-k8s-cluster \
  --zone=asia-south1-a \
  --num-nodes=2 \
  --machine-type=e2-medium
```

### Create Artifact Registry in Mumbai
```bash
gcloud artifacts repositories create flask-app-images \
  --repository-format=docker \
  --location=asia-south1
```

### Configure Docker Authentication
```bash
gcloud auth configure-docker asia-south1-docker.pkg.dev
```

### Full Image URL Format
```
asia-south1-docker.pkg.dev/flask-k8s-production/flask-app-images/flask-backend:latest
```

---

## Regional Cluster Setup

For high availability across multiple zones in Mumbai:

```bash
gcloud container clusters create flask-k8s-prod-cluster \
  --region=asia-south1 \
  --node-locations=asia-south1-a,asia-south1-b,asia-south1-c \
  --num-nodes=1 \
  --machine-type=e2-medium
```

---

## Next Steps

1. **Review Configuration**: Check `gke-config.env.example` for all settings
2. **Follow Setup Guides**: All guides now use India regions by default
3. **Deploy**: All scripts will use `asia-south1` by default

---

## Cost Considerations

Pricing for Asia-South1 is similar to US regions. Estimated monthly cost remains approximately $76/month for the basic production setup described in the documentation.

**Network Egress:**
- Within `asia-south1`: Free
- To India users from `asia-south1`: Lower latency, standard egress rates
- Cross-region traffic: Standard GCP egress pricing applies

---

## Important Notes

> [!TIP]
> **Fastest Setup**: The Mumbai region (`asia-south1`) provides the best performance for users in India and neighboring countries.

> [!NOTE]
> **Region Consistency**: Make sure all your resources (GKE cluster, Artifact Registry, other GCP services) are in the same region (`asia-south1`) to avoid cross-region data transfer costs and latency.

> [!CAUTION]
> **Existing Deployments**: If you already have resources in `us-central1`, you'll need to migrate them or update configuration files to match your existing setup.

---

## Testing Region Latency

Test latency from your location:

```bash
# Ping Mumbai region
gcloud compute instances create test-latency \
  --zone=asia-south1-a \
  --machine-type=e2-micro

# Check latency
ping <instance-external-ip>

# Clean up
gcloud compute instances delete test-latency --zone=asia-south1-a
```

---

**All documentation is now optimized for India-based deployments! 🇮🇳**
