# Milvus Backup - OpenShift Deployment Guide

This guide explains how to deploy the Milvus Backup tool as a Kubernetes Job in your OpenShift Container Platform (OCP) cluster.

## Overview

The deployment consists of:
- **Dockerfile**: Containerizes the milvus-backup binary
- **ConfigMap**: Contains the backup.yaml configuration
- **Secret**: Stores sensitive credentials (passwords, access keys, CA certificates)
- **Job**: Runs the backup operation to S3 storage and exits

## Prerequisites

- OpenShift CLI (`oc`) or Kubernetes CLI (`kubectl`)
- Podman installed locally
- Access to an OpenShift cluster
- Container registry access (e.g., Quay.io, Docker Hub, or internal registry)
- Running Milvus instance
- S3-compatible storage for backups
- CA certificate for Milvus connection (if using TLS)

## Step 1: Build the Container Image with Podman

Build the image using Podman:

```bash
# Build the image
podman build -t milvus-backup:0.5.10 .

# Tag for your registry (example with Quay.io)
podman tag milvus-backup:0.5.10 quay.io/your-org/milvus-backup:0.5.10

# Login to your registry
podman login quay.io

# Push to registry
podman push quay.io/your-org/milvus-backup:0.5.10
```

For OpenShift internal registry:

```bash
# Login to OpenShift
oc login

# Get the registry route
REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')

# Login to OpenShift registry
podman login -u $(oc whoami) -p $(oc whoami -t) $REGISTRY

# Tag for OpenShift registry
podman tag milvus-backup:0.5.10 $REGISTRY/your-namespace/milvus-backup:0.5.10

# Push to OpenShift registry
podman push $REGISTRY/your-namespace/milvus-backup:0.5.10
```

## Step 2: Configure the Deployment

### 2.1 Update ConfigMap (configmap.yaml)

Edit `configmap.yaml` to match your Milvus and S3 configuration:

```yaml
# Key configurations to update:
milvus:
  address: milvus-proxy.your-namespace.svc.cluster.local  # Your Milvus service
  port: 19530
  user: root
  tlsMode: 1  # 0: none, 1: one-way TLS, 2: two-way/mtls
  caCertPath: /opt/milvus-backup/certs/ca.crt  # Path to mounted CA cert
  serverName: milvus-proxy.your-namespace.svc.cluster.local

minio:
  storageType: s3  # Use s3, aws, or other S3-compatible storage
  address: s3.amazonaws.com  # Your S3 endpoint
  port: 443
  useSSL: true
  bucketName: your-milvus-bucket  # Your Milvus data bucket
  rootPath: file  # Milvus data root path

backup:
  # Backup will be stored in S3
  backupStorageType: s3  # or aws
  backupAddress: s3.amazonaws.com  # Your backup S3 endpoint
  backupPort: 443
  backupUseSSL: true
  backupBucketName: your-backup-bucket  # Your backup bucket
  backupRootPath: milvus-backups
  crossStorage: true  # Enable if backup storage differs from Milvus storage
```

### 2.2 Prepare CA Certificate

If your Milvus instance uses TLS, prepare the CA certificate:

```bash
# Save your CA certificate to a file
cat > ca.crt << 'EOF'
-----BEGIN CERTIFICATE-----
YOUR_CA_CERTIFICATE_CONTENT_HERE
-----END CERTIFICATE-----
EOF
```

### 2.3 Create Secret with Credentials and CA Cert

Create the secret with credentials and CA certificate:

```bash
# Create secret with all credentials and CA cert
oc create secret generic milvus-backup-secret \
  --from-literal=milvus-password='YourMilvusPassword' \
  --from-literal=minio-access-key='YourS3AccessKey' \
  --from-literal=minio-secret-key='YourS3SecretKey' \
  --from-literal=backup-access-key='YourBackupS3AccessKey' \
  --from-literal=backup-secret-key='YourBackupS3SecretKey' \
  --from-file=ca.crt=ca.crt \
  -n your-namespace
```

Or use the secret.yaml file and add the CA cert:

```bash
# First create the secret from YAML
oc apply -f secret.yaml

# Then add the CA certificate
oc create secret generic milvus-backup-secret \
  --from-file=ca.crt=ca.crt \
  --dry-run=client -o yaml | oc apply -f -
```

### 2.4 Update Job (job.yaml)

Update the image reference in `job.yaml`:

```yaml
containers:
- name: milvus-backup
  image: quay.io/your-org/milvus-backup:0.5.10  # Your image location
```

## Step 3: Deploy to OpenShift

```bash
# Create or switch to your namespace
oc project your-namespace

# Apply ConfigMap
oc apply -f configmap.yaml

# Create Secret with credentials and CA cert
oc create secret generic milvus-backup-secret \
  --from-literal=milvus-password='YourPassword' \
  --from-literal=minio-access-key='YourS3AccessKey' \
  --from-literal=minio-secret-key='YourS3SecretKey' \
  --from-literal=backup-access-key='YourBackupAccessKey' \
  --from-literal=backup-secret-key='YourBackupSecretKey' \
  --from-file=ca.crt=ca.crt \
  -n your-namespace

# Deploy the Job
oc apply -f job.yaml
```

## Step 4: Monitor the Backup Job

Check job status:

```bash
# List jobs
oc get jobs

# Check job details
oc describe job milvus-backup-job

# View pod logs in real-time
oc logs -f job/milvus-backup-job

# Or find the pod name and view logs
oc get pods | grep milvus-backup
oc logs -f <pod-name>
```

## Step 5: Verify Backup in S3

The backup will be stored in your S3 bucket. Verify using AWS CLI or S3 console:

```bash
# Using AWS CLI
aws s3 ls s3://your-backup-bucket/milvus-backups/

# Or using s3cmd
s3cmd ls s3://your-backup-bucket/milvus-backups/
```

## Running Backups on Schedule

Create a CronJob for scheduled backups:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: milvus-backup-cronjob
  namespace: your-namespace
spec:
  schedule: "0 2 * * *"  # Run daily at 2 AM UTC
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 86400  # Keep completed jobs for 24 hours
      backoffLimit: 3
      template:
        # Copy the entire template spec from job.yaml
```

Save as `cronjob.yaml` and apply:

```bash
oc apply -f cronjob.yaml
```

## Cleanup

To delete the job and related resources:

```bash
# Delete job
oc delete job milvus-backup-job

# Delete configmap
oc delete configmap milvus-backup-config

# Delete secret
oc delete secret milvus-backup-secret

# Delete cronjob (if created)
oc delete cronjob milvus-backup-cronjob
```

## Troubleshooting

### Job Fails with Connection Error

Check if Milvus service is accessible:

```bash
# Test Milvus connection
oc run -it --rm debug --image=busybox --restart=Never -- \
  nc -zv milvus-proxy.your-namespace.svc.cluster.local 19530
```

### TLS/Certificate Issues

Verify the CA certificate is correctly mounted:

```bash
# Check the secret
oc get secret milvus-backup-secret -o yaml

# Exec into a running pod to verify cert
oc exec -it <pod-name> -- cat /opt/milvus-backup/certs/ca.crt
```

### S3 Connection Issues

Verify S3 credentials and connectivity:

```bash
# Check if S3 endpoint is accessible
oc run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -I https://s3.amazonaws.com

# Verify credentials are set correctly
oc get secret milvus-backup-secret -o jsonpath='{.data.minio-access-key}' | base64 -d
```

### View Job Logs After Completion

```bash
# List all pods including completed ones
oc get pods --show-all

# View logs from completed pod
oc logs <completed-pod-name>
```

### Permission Denied Errors

Ensure the SecurityContextConstraints (SCC) allows the job to run:

```bash
# Check current SCC
oc get pod <pod-name> -o yaml | grep scc

# If needed, create a service account with appropriate permissions
oc create serviceaccount milvus-backup-sa
oc adm policy add-scc-to-user anyuid -z milvus-backup-sa

# Update job.yaml to use the service account
spec:
  template:
    spec:
      serviceAccountName: milvus-backup-sa
```

## Environment Variables

The job supports environment variable overrides for sensitive data:

- `MILVUS_PASSWORD`: Milvus password
- `MINIO_ACCESS_KEY_ID`: S3 access key for Milvus storage
- `MINIO_SECRET_ACCESS_KEY`: S3 secret key for Milvus storage
- `BACKUP_MINIO_ACCESS_KEY_ID`: S3 access key for backup storage
- `BACKUP_MINIO_SECRET_ACCESS_KEY`: S3 secret key for backup storage

These are automatically injected from the Secret in the job manifest.

## S3 Configuration Examples

### AWS S3

```yaml
minio:
  storageType: aws
  address: s3.amazonaws.com
  port: 443
  useSSL: true
  bucketName: my-milvus-bucket
  rootPath: file

backup:
  backupStorageType: aws
  backupAddress: s3.amazonaws.com
  backupPort: 443
  backupUseSSL: true
  backupBucketName: my-backup-bucket
  backupRootPath: milvus-backups
  crossStorage: true
```

### MinIO (S3-compatible)

```yaml
minio:
  storageType: minio
  address: minio.your-namespace.svc.cluster.local
  port: 9000
  useSSL: false
  bucketName: milvus-bucket
  rootPath: file

backup:
  backupStorageType: s3
  backupAddress: s3.amazonaws.com
  backupPort: 443
  backupUseSSL: true
  backupBucketName: my-backup-bucket
  backupRootPath: milvus-backups
  crossStorage: true
```

## Additional Resources

- [Milvus Backup GitHub](https://github.com/zilliztech/milvus-backup)
- [Milvus Documentation](https://milvus.io/docs)
- [OpenShift Documentation](https://docs.openshift.com/)
- [Podman Documentation](https://podman.io/docs)

## Support

For issues related to:
- **Milvus Backup Tool**: Check the [GitHub Issues](https://github.com/zilliztech/milvus-backup/issues)
- **OpenShift Deployment**: Consult your cluster administrator
- **Container Build**: Review the Dockerfile and build logs with `podman build`