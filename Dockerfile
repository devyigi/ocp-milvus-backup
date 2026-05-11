# Use Red Hat UBI (Universal Base Image) for OpenShift compatibility
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Set metadata
LABEL maintainer="IBM - Yiğithan Osmanoğlu" \
      description="Containerized Milvus Backup Tool for OpenShift" \
      version="0.5.10"

# Create a non-root user for security (OpenShift requirement)
RUN microdnf install -y shadow-utils && \
    groupadd -g 1001 milvus && \
    useradd -u 1001 -g milvus -m -s /bin/bash milvus && \
    microdnf clean all

# Set working directory
WORKDIR /opt/backup

# Copy the binary
COPY --chown=milvus:milvus milvus-backup /opt/backup/

# Create directories for configs, logs, and backups
RUN mkdir -p /opt/backup/configs \
             /opt/backup/logs \
             /opt/backup/backups && \
    chown -R milvus:milvus /opt/backup

# Make the binary executable
RUN chmod +x /opt/backup/milvus-backup

# Switch to non-root user
USER 1001

# Expose the API server port
EXPOSE 8080

# Set environment variables
ENV PATH="/opt/backup:${PATH}"

# Default command - run backup and exit (for Kubernetes Job)
# The config file will be mounted from ConfigMap
CMD ["./milvus-backup", "create", "--config", "/opt/backup/configs/backup.yaml"]