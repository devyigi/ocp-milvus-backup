# Milvus Backup - Quick Start Guide

This is a quick reference guide for deploying Milvus Backup to OpenShift.

## Prerequisites Checklist

- [ ] Podman installed
- [ ] OpenShift CLI (`oc`) installed and logged in
- [ ] Access to a container registry
- [ ] Milvus instance running and accessible
- [ ] S3 bucket for backups
- [ ] S3 credentials (access key and secret key)
- [ ] Milvus credentials
- [ ] CA certificate (if Milvus uses TLS)

## Quick Deploy (5 Steps)

### 1. Build and Push Image

```bash
# For external registry (Quay.io)
./build-and-push.sh --push --registry quay.io --org your-org

# For OpenShift internal registry
./build-and-push.sh --push --ocp --namespace your-namespace
```

### 2. Update ConfigMap

Edit `configmap.yaml` and update:

```yaml
milvus:
  address: milvus-proxy.your-namespace.svc.cluster.local
  port: 19530
  tlsMode: 1  # Set to 1 if using TLS, 0 if not
  caCertPath: /opt/milvus-backup/certs/ca.crt

minio:
  storageType: s3
  address: s3.amazonaws.com
  bucketName: your-milvus-bucket
  rootPath: file

minio:
  backupStorageType: s3
  backupAddress: s3.amazonaws.com
  backupBucketName: your-backup-bucket
  backupRootPath: backups
  crossStorage: true
```

### 3. Create Secret

```bash
# If using TLS, prepare CA certificate first
cat > ca.crt << 'EOF'
-----BEGIN CERTIFICATE-----
YOUR_CA_CERTIFICATE_HERE
-----END CERTIFICATE-----
EOF

# Create secret with credentials and CA cert
oc create secret generic milvus-backup-secret \
  --from-literal=milvus-password='YourMilvusPassword' \
  --from-literal=minio-access-key='YourS3AccessKey' \
  --from-literal=minio-secret-key='YourS3SecretKey' \
  --from-literal=backup-access-key='YourBackupS3AccessKey' \
  --from-literal=backup-secret-key='YourBackupS3SecretKey' \
  --from-file=ca.crt=ca.crt \
  -n your-namespace

# If NOT using TLS, omit the ca.crt:
oc create secret generic milvus-backup-secret \
  --from-literal=milvus-password='YourMilvusPassword' \
  --from-literal=minio-access-key='YourS3AccessKey' \
  --from-literal=minio-secret-key='YourS3SecretKey' \
  --from-literal=backup-access-key='YourBackupS3AccessKey' \
  --from-literal=backup-secret-key='YourBackupS3SecretKey' \
  -n your-namespace
```

### 4. Update Job Image

Edit `job.yaml` and update the image:

```yaml
containers:
- name: milvus-backup
  image: quay.io/your-org/milvus-backup:0.5.10  # Your image location
```

### 5. Deploy

```bash
# Switch to your namespace
oc project your-namespace

# Deploy ConfigMap
oc apply -f configmap.yaml

# Deploy Job
oc apply -f job.yaml
```

## Monitor Backup

```bash
# Watch job status
oc get jobs -w

# View logs
oc logs -f job/milvus-backup-job

# Check if backup succeeded
oc logs job/milvus-backup-job | grep -i "success\|complete\|backup"
```

## Verify Backup in S3

```bash
# Using AWS CLI
aws s3 ls s3://your-backup-bucket/backups/

# Using s3cmd
s3cmd ls s3://your-backup-bucket/backups/
```

## Schedule Backups (Optional)

For automated scheduled backups:

```bash
# Edit cronjob.yaml to set schedule
# Default: "0 2 * * *" (daily at 2 AM)

# Deploy CronJob
oc apply -f cronjob.yaml

# List CronJobs
oc get cronjobs

# Manually trigger a job from CronJob
oc create job --from=cronjob/milvus-backup-cronjob manual-backup-$(date +%s)
```

## Troubleshooting

### Check Job Status

```bash
oc describe job milvus-backup-job
oc get pods | grep milvus-backup
oc logs <pod-name>
```

### Test Milvus Connection

```bash
oc run -it --rm debug --image=busybox --restart=Never -- \
  nc -zv milvus-proxy.your-namespace.svc.cluster.local 19530
```

### Verify Secret

```bash
oc get secret milvus-backup-secret -o yaml
```

### Check ConfigMap

```bash
oc get configmap milvus-backup-config -o yaml
```

## Cleanup

```bash
# Delete job
oc delete job milvus-backup-job

# Delete cronjob (if created)
oc delete cronjob milvus-backup-cronjob

# Delete configmap
oc delete configmap milvus-backup-config

# Delete secret
oc delete secret milvus-backup-secret
```

## Common Issues

### Issue: "connection refused"
**Solution**: Check Milvus service name and port in configmap.yaml

### Issue: "authentication failed"
**Solution**: Verify credentials in secret are correct

### Issue: "certificate verify failed"
**Solution**: Ensure CA certificate is correctly mounted and tlsMode is set to 1

### Issue: "access denied" to S3
**Solution**: Verify S3 credentials and bucket permissions

### Issue: "permission denied" in OpenShift
**Solution**: Check SecurityContextConstraints (SCC)

```bash
oc get pod <pod-name> -o yaml | grep scc
```

## Next Steps

- Review full documentation in [DEPLOYMENT.md](DEPLOYMENT.md)
- Configure backup retention policies in S3
- Set up monitoring and alerting for backup jobs
- Test restore procedures

## Support

- [Milvus Backup GitHub](https://github.com/zilliztech/milvus-backup)
- [Milvus Documentation](https://milvus.io/docs)