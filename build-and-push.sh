#!/bin/bash

# Milvus Backup Container Build and Push Script
# This script builds the container image using Podman and pushes it to a registry

set -e

# Configuration
IMAGE_NAME="milvus-backup"
IMAGE_VERSION="0.5.10"
REGISTRY="${REGISTRY:-quay.io}"
ORG="${ORG:-your-org}"
NAMESPACE="${NAMESPACE:-default}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if podman is installed
if ! command -v podman &> /dev/null; then
    print_error "Podman is not installed. Please install it first."
    exit 1
fi

# Parse command line arguments
PUSH_TO_REGISTRY=false
USE_OCP_REGISTRY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH_TO_REGISTRY=true
            shift
            ;;
        --ocp)
            USE_OCP_REGISTRY=true
            shift
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --org)
            ORG="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --push              Push image to registry after building"
            echo "  --ocp               Use OpenShift internal registry"
            echo "  --registry REGISTRY Registry URL (default: quay.io)"
            echo "  --org ORG           Organization/username (default: your-org)"
            echo "  --namespace NS      OpenShift namespace (default: default)"
            echo "  --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Build only"
            echo "  $0 --push --registry quay.io --org myorg"
            echo "  $0 --push --ocp --namespace myproject"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Build the image
print_info "Building container image..."
podman build -t ${IMAGE_NAME}:${IMAGE_VERSION} .

if [ $? -ne 0 ]; then
    print_error "Build failed!"
    exit 1
fi

print_info "Build successful: ${IMAGE_NAME}:${IMAGE_VERSION}"

# Push to registry if requested
if [ "$PUSH_TO_REGISTRY" = true ]; then
    if [ "$USE_OCP_REGISTRY" = true ]; then
        # OpenShift internal registry
        print_info "Using OpenShift internal registry..."
        
        # Check if oc is installed
        if ! command -v oc &> /dev/null; then
            print_error "OpenShift CLI (oc) is not installed. Please install it first."
            exit 1
        fi
        
        # Get registry route
        OCP_REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null)
        
        if [ -z "$OCP_REGISTRY" ]; then
            print_error "Could not get OpenShift registry route. Make sure you're logged in to OpenShift."
            exit 1
        fi
        
        FULL_IMAGE_NAME="${OCP_REGISTRY}/${NAMESPACE}/${IMAGE_NAME}:${IMAGE_VERSION}"
        
        print_info "Logging in to OpenShift registry..."
        podman login -u $(oc whoami) -p $(oc whoami -t) ${OCP_REGISTRY}
        
    else
        # External registry (Quay.io, Docker Hub, etc.)
        FULL_IMAGE_NAME="${REGISTRY}/${ORG}/${IMAGE_NAME}:${IMAGE_VERSION}"
        
        print_info "Logging in to ${REGISTRY}..."
        podman login ${REGISTRY}
    fi
    
    print_info "Tagging image as ${FULL_IMAGE_NAME}..."
    podman tag ${IMAGE_NAME}:${IMAGE_VERSION} ${FULL_IMAGE_NAME}
    
    print_info "Pushing image to registry..."
    podman push ${FULL_IMAGE_NAME}
    
    if [ $? -eq 0 ]; then
        print_info "Successfully pushed image: ${FULL_IMAGE_NAME}"
        echo ""
        print_info "Update your job.yaml with:"
        echo "  image: ${FULL_IMAGE_NAME}"
    else
        print_error "Failed to push image!"
        exit 1
    fi
else
    print_warn "Image built but not pushed. Use --push to push to registry."
    echo ""
    print_info "To push manually:"
    echo "  podman tag ${IMAGE_NAME}:${IMAGE_VERSION} ${REGISTRY}/${ORG}/${IMAGE_NAME}:${IMAGE_VERSION}"
    echo "  podman push ${REGISTRY}/${ORG}/${IMAGE_NAME}:${IMAGE_VERSION}"
fi

print_info "Done!"

# Made with Bob
