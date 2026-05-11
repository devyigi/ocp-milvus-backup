# Use Red Hat UBI (Universal Base Image) for OpenShift compatibility
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Set metadata
LABEL maintainer="Milvus Backup Container" \
      description="Containerized Milvus Backup Tool for OpenShift" \
      version="0.5.10"

# Create a non-root user for security (OpenShift requirement)
RUN microdnf install -y shadow-utils && \
    groupadd -g 1001 milvus && \
    useradd -u 1001 -g milvus -m -s /bin/bash milvus && \
    microdnf clean all

# Set working directory
WORKDIR /opt/milvus-backup

# Copy the binary and configuration files
COPY --chown=milvus:milvus milvus-backup /opt/milvus-backup/
COPY --chown=milvus:milvus LICENSE /opt/milvus-backup/
COPY --chown=milvus:milvus README.md /opt/milvus-backup/

# Create directories for configs, logs, and backups
RUN mkdir -p /opt/milvus-backup/configs \
             /opt/milvus-backup/logs \
             /opt/milvus-backup/backups && \
    chown -R milvus:milvus /opt/milvus-backup

# Make the binary executable
RUN chmod +x /opt/milvus-backup/milvus-backup

# Switch to non-root user
USER 1001

# Expose the API server port
EXPOSE 8080

# Set environment variables
ENV PATH="/opt/milvus-backup:${PATH}"

# Default command - run backup and exit (for Kubernetes Job)
# The config file will be mounted from ConfigMap
CMD ["./milvus-backup", "create", "--config", "/opt/milvus-backup/configs/backup.yaml"]