# Milvus Backup - Containerized Deployment for OpenShift

This repository contains everything needed to containerize and deploy the Milvus Backup tool as a Kubernetes Job in OpenShift Container Platform (OCP).

## 📋 Overview

The Milvus Backup tool is containerized to run as a one-time job or scheduled CronJob in OpenShift. It connects to your Milvus instance, creates a backup, and stores it in S3-compatible storage.

### Key Features

- ✅ **OpenShift Compatible**: Uses Red Hat UBI base image with non-root user
- ✅ **S3 Storage**: Backups stored directly to S3 (no local storage needed)
- ✅ **TLS Support**: Optional CA certificate mounting for secure Milvus connections
- ✅ **Secrets Management**: Credentials stored securely in Kubernetes Secrets
- ✅ **Podman Ready**: Build scripts use Podman instead of Docker
- ✅ **Job-based**: Runs backup and exits (perfect for scheduled jobs)
- ✅ **Configurable**: All settings via ConfigMap and environment variables

## 📁 Repository Structure

```
.
├── Dockerfile              # Container image definition
├── configmap.yaml          # Backup configuration (backup.yaml)
├── secret.yaml             # Template for credentials (DO NOT commit with real values)
├── job.yaml                # Kubernetes Job manifest
├── cronjob.yaml            # Kubernetes CronJob manifest (for scheduled backups)
├── build-and-push.sh       # Podman build and push script
├── QUICKSTART.md           # Quick start guide (5 steps)
├── DEPLOYMENT.md           # Detailed deployment guide
├── .gitignore              # Git ignore file
└── README-CONTAINER.md     # This file
```

## 🚀 Quick Start

See [QUICKSTART.md](QUICKSTART.md) for a 5-step deployment guide.

### TL;DR

```bash
# 1. Build and push image
./build-and-push.sh --push --ocp --namespace your-namespace

# 2. Edit configmap.yaml with your settings

# 3. Create secret
oc create secret generic milvus-backup-secret \
  --from-literal=milvus-password='password' \
  --from-literal=minio-access-key='key' \
  --from-literal=minio-secret-key='secret' \
  --from-literal=backup-access-key='key' \
  --from-literal=backup-secret-key='secret' \
  --from-file=ca.crt=ca.crt \
  -n your-namespace

# 4. Deploy
oc apply -f configmap.yaml
oc apply -f job.yaml

# 5. Monitor
oc logs -f job/milvus-backup-job
```

## 📚 Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Get started in 5 steps
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Comprehensive deployment guide with troubleshooting

## 🔧 Configuration

### Required Configuration

1. **Milvus Connection** (in `configmap.yaml`):
   - Service address and port
   - Authentication credentials (via Secret)
   - TLS settings (if applicable)

2. **S3 Storage** (in `configmap.yaml`):
   - Milvus data bucket (where Milvus stores its data)
   - Backup bucket (where backups will be stored)
   - S3 credentials (via Secret)

3. **Secrets** (create with `oc create secret`):
   - Milvus password
   - S3 access keys
   - CA certificate (if using TLS)

### Example Configuration

```yaml
# ConfigMap - Milvus connection
milvus:
  address: milvus-proxy.milvus.svc.cluster.local
  port: 19530
  tlsMode: 1
  caCertPath: /opt/milvus-backup/certs/ca.crt

# ConfigMap - S3 storage
minio:
  storageType: s3
  address: s3.amazonaws.com
  bucketName: my-milvus-data
  
  backupStorageType: s3
  backupAddress: s3.amazonaws.com
  backupBucketName: my-milvus-backups
  crossStorage: true
```

## 🏗️ Building the Image

### Using the Build Script (Recommended)

```bash
# Build only
./build-and-push.sh

# Build and push to Quay.io
./build-and-push.sh --push --registry quay.io --org myorg

# Build and push to OpenShift internal registry
./build-and-push.sh --push --ocp --namespace myproject
```

### Manual Build with Podman

```bash
# Build
podman build -t milvus-backup:0.5.10 .

# Tag
podman tag milvus-backup:0.5.10 quay.io/myorg/milvus-backup:0.5.10

# Push
podman push quay.io/myorg/milvus-backup:0.5.10
```

## 📅 Scheduled Backups

Deploy as a CronJob for automated backups:

```bash
# Edit cronjob.yaml to set schedule
# Default: "0 2 * * *" (daily at 2 AM)

oc apply -f cronjob.yaml
```

Schedule examples:
- `"0 2 * * *"` - Daily at 2 AM
- `"0 */6 * * *"` - Every 6 hours
- `"0 0 * * 0"` - Weekly on Sunday
- `"0 3 1 * *"` - Monthly on the 1st

## 🔒 Security Best Practices

1. **Never commit secrets**: Use `oc create secret` instead of YAML files
2. **Use TLS**: Enable TLS for Milvus connections in production
3. **Restrict permissions**: Use RBAC to limit access to secrets
4. **Rotate credentials**: Regularly update S3 and Milvus credentials
5. **Audit logs**: Monitor backup job logs for security events

## 🐛 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Connection refused | Check Milvus service name and port |
| Authentication failed | Verify credentials in secret |
| Certificate error | Ensure CA cert is mounted and tlsMode is correct |
| S3 access denied | Verify S3 credentials and bucket permissions |
| Permission denied | Check OpenShift SecurityContextConstraints |

### Debug Commands

```bash
# Check job status
oc describe job milvus-backup-job

# View logs
oc logs -f job/milvus-backup-job

# Test Milvus connection
oc run -it --rm debug --image=busybox --restart=Never -- \
  nc -zv milvus-proxy.namespace.svc.cluster.local 19530

# Verify secret
oc get secret milvus-backup-secret -o yaml

# Check ConfigMap
oc get configmap milvus-backup-config -o yaml
```

## 📊 Monitoring

Monitor backup jobs:

```bash
# List jobs
oc get jobs

# Watch job status
oc get jobs -w

# View recent logs
oc logs job/milvus-backup-job --tail=50

# Check backup in S3
aws s3 ls s3://your-backup-bucket/backups/
```

## 🔄 Restore Process

To restore from a backup:

1. Update the job command in `job.yaml`:
   ```yaml
   command: ["./milvus-backup", "restore", "--config", "/opt/milvus-backup/configs/backup.yaml"]
   ```

2. Add restore parameters as needed (see Milvus Backup documentation)

3. Deploy the restore job:
   ```bash
   oc apply -f job.yaml
   ```

## 📦 What's Included

### Container Image
- Milvus Backup binary (v0.5.10)
- Red Hat UBI minimal base image
- Non-root user (UID 1001)
- OpenShift compatible security context

### Kubernetes Manifests
- **ConfigMap**: Backup configuration
- **Secret**: Credentials and certificates
- **Job**: One-time backup execution
- **CronJob**: Scheduled backup execution

### Scripts
- **build-and-push.sh**: Automated image build and push

### Documentation
- **QUICKSTART.md**: 5-step quick start
- **DEPLOYMENT.md**: Comprehensive guide
- **README-CONTAINER.md**: This overview

## 🔗 Resources

- [Milvus Backup GitHub](https://github.com/zilliztech/milvus-backup)
- [Milvus Documentation](https://milvus.io/docs)
- [OpenShift Documentation](https://docs.openshift.com/)
- [Podman Documentation](https://podman.io/docs)

## 📝 License

This containerization follows the same license as Milvus Backup (Apache License 2.0).

## 🤝 Contributing

Contributions are welcome! Please ensure:
- Podman compatibility
- OpenShift security compliance
- Documentation updates
- No committed secrets

## 💡 Tips

1. **Test first**: Run a one-time job before setting up CronJob
2. **Monitor S3 costs**: Set up S3 lifecycle policies for old backups
3. **Verify backups**: Periodically test restore procedures
4. **Resource limits**: Adjust CPU/memory based on your data size
5. **Backup retention**: Configure S3 bucket policies for retention

## 📞 Support

For issues:
- **Milvus Backup**: [GitHub Issues](https://github.com/zilliztech/milvus-backup/issues)
- **OpenShift**: Contact your cluster administrator
- **Container**: Check logs and troubleshooting guide

---

**Ready to deploy?** Start with [QUICKSTART.md](QUICKSTART.md)!