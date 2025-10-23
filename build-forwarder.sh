#!/bin/bash
#
# Build and push the UDP forwarder Docker image on production cluster
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

REGISTRY="registry.olympusdrive.com"
IMAGE_NAME="weatherflow-udp-forwarder"
GIT_SHA=$(git rev-parse --short HEAD)
TAG="${GIT_SHA}"
PROD_NODE="dgorman@192.168.2.22"  # node01

echo "Building UDP Forwarder Docker image on production..."
echo "Registry: ${REGISTRY}"
echo "Image: ${IMAGE_NAME}"
echo "Tag: ${TAG}"
echo ""

# Create a temporary directory on production node
echo "Preparing build context on ${PROD_NODE}..."
ssh "${PROD_NODE}" "mkdir -p /tmp/weatherflow-forwarder-build"

# Copy files to production node
echo "Copying files to production..."
scp Dockerfile.forwarder udp_interface_forwarder.py "${PROD_NODE}:/tmp/weatherflow-forwarder-build/"

# Build the image on production node
echo "Building image..."
ssh "${PROD_NODE}" "cd /tmp/weatherflow-forwarder-build && docker build -f Dockerfile.forwarder -t ${REGISTRY}/${IMAGE_NAME}:${TAG} ."

# Tag as latest
echo "Tagging as latest..."
ssh "${PROD_NODE}" "docker tag ${REGISTRY}/${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:latest"

# Push to registry
echo "Pushing to registry..."
ssh "${PROD_NODE}" "docker push ${REGISTRY}/${IMAGE_NAME}:${TAG}"
ssh "${PROD_NODE}" "docker push ${REGISTRY}/${IMAGE_NAME}:latest"

# Cleanup
echo "Cleaning up..."
ssh "${PROD_NODE}" "rm -rf /tmp/weatherflow-forwarder-build"

echo ""
echo "✓ Image built and pushed successfully!"
echo ""
echo "Image: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
echo ""
echo "To deploy:"
echo "  cd argo && ./trigger-deploy.sh"

