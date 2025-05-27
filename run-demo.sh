#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display messages with timestamp
log() {
  echo -e "${GREEN}[$(date +"%H:%M:%S")]${NC} $1"
}

# Function to display section headers
section() {
  echo -e "\n${BLUE}========== $1 ==========${NC}"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
section "Checking Prerequisites"

# Check for kubectl
if ! command_exists kubectl; then
  echo -e "${RED}Error: kubectl is not installed. Please install kubectl first.${NC}"
  exit 1
fi

# Check for minikube
if ! command_exists minikube; then
  echo -e "${RED}Error: minikube is not installed. Please install minikube first.${NC}"
  exit 1
fi

# Check if minikube is running
if ! minikube status | grep -q "Running"; then
  log "Minikube is not running. Starting minikube..."
  minikube start
else
  log "Minikube is already running."
fi

# Clean up any existing deployments
section "Cleaning Up Existing Deployments"
log "Removing any existing Jaeger, Prometheus, and HotROD resources..."
kubectl delete deployment jaeger-spm prometheus hotrod 2>/dev/null || true
kubectl delete service jaeger prometheus hotrod 2>/dev/null || true
kubectl delete configmap jaeger-spm-config prometheus-config 2>/dev/null || true
log "Cleanup complete."

# Deploy all components
section "Deploying Jaeger SPM Components"
log "Applying Kubernetes manifests..."
kubectl apply -k $(dirname "$0")/kubernetes/base/jaeger-spm

# Wait for pods to be ready
log "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pods --all --timeout=180s

# Get service details
section "Service Information"
log "Deployed services:"
kubectl get svc

# Setup port forwarding in the background
section "Setting Up Port Forwarding"
log "Setting up port forwarding for Jaeger UI on port 16686..."
kubectl port-forward svc/jaeger 16686:16686 > /dev/null 2>&1 &
JAEGER_PF_PID=$!

log "Setting up port forwarding for Prometheus on port 9090..."
kubectl port-forward svc/prometheus 9090:9090 > /dev/null 2>&1 &
PROM_PF_PID=$!

# Give port forwarding time to establish
sleep 3

# Get HotROD URL
HOTROD_URL=$(minikube service hotrod --url)
HOTROD_HOST=$(echo $HOTROD_URL | sed 's|http://||' | cut -d':' -f1)
HOTROD_PORT=$(echo $HOTROD_URL | sed 's|http://||' | cut -d':' -f2)

# Display access information
section "Access Information"
echo -e "${YELLOW}Jaeger UI:${NC} http://localhost:16686"
echo -e "${YELLOW}Prometheus:${NC} http://localhost:9090"
echo -e "${YELLOW}HotROD Application:${NC} $HOTROD_URL"

# Generate traffic
section "Generating Traffic"
log "Starting traffic generation to create traces and metrics..."
log "Will generate traffic for 60 seconds..."

# Run traffic generator with timeout
HOTROD_HOST=$HOTROD_HOST \
HOTROD_PORT=$HOTROD_PORT \
RUNTIME=60s \
$(dirname "$0")/generate_traffic.sh &
TRAFFIC_PID=$!

# Wait for traffic generation to complete
wait $TRAFFIC_PID

section "Demo Complete"
echo -e "${YELLOW}Demonstration is now running.${NC}"
echo -e "You can access the following UIs to view the SPM functionality:"
echo -e "${GREEN}1. Jaeger UI:${NC} http://localhost:16686"
echo -e "   - Click on the \"Service Performance\" tab to see SPM metrics"
echo -e "${GREEN}2. Prometheus:${NC} http://localhost:9090"
echo -e "   - Try queries like: traces_span_metrics_calls_total"
echo -e "${GREEN}3. HotROD Application:${NC} $HOTROD_URL"
echo -e "   - Generate more traffic by interacting with this application"
echo 
echo -e "${YELLOW}Port forwarding is active in the background.${NC}"
echo -e "When you're done with the demo, run the following commands to clean up:"
echo -e "${RED}kill $JAEGER_PF_PID $PROM_PF_PID${NC} # Stop port forwarding"
echo -e "${RED}kubectl delete -k $(dirname "$0")/kubernetes/base/jaeger-spm${NC} # Remove all resources"
echo
echo -e "${GREEN}Press Ctrl+C to exit this script (port forwarding will continue).${NC}"

# Keep script running until interrupted
wait
