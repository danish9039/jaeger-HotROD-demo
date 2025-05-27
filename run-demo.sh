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

# Function to display errors
error() {
  echo -e "${RED}[ERROR] $1${NC}"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check if a port is in use
port_in_use() {
  lsof -i:"$1" >/dev/null 2>&1
}

# Function to verify port forwarding is working
verify_port_forward() {
  local service=$1
  local port=$2
  local max_attempts=$3
  local attempt=1
  
  log "Verifying $service port forwarding on port $port..."
  while [ $attempt -le $max_attempts ]; do
    if curl -s http://localhost:$port >/dev/null; then
      log "$service port forwarding is working!"
      return 0
    fi
    log "Waiting for $service port forwarding (attempt $attempt/$max_attempts)..."
    sleep 2
    attempt=$((attempt+1))
  done
  
  error "$service port forwarding failed after $max_attempts attempts"
  return 1
}

# Function to clean up resources on exit
cleanup() {
  log "Cleaning up resources..."
  # Kill port forwarding processes if they exist
  if [ ! -z "$JAEGER_PF_PID" ] && ps -p $JAEGER_PF_PID > /dev/null; then
    kill $JAEGER_PF_PID 2>/dev/null || true
  fi
  if [ ! -z "$PROM_PF_PID" ] && ps -p $PROM_PF_PID > /dev/null; then
    kill $PROM_PF_PID 2>/dev/null || true
  fi
  log "Cleanup complete"
}

# Set up trap to clean up on script exit
trap cleanup EXIT

# Check prerequisites
section "Checking Prerequisites"

# Check for kubectl
if ! command_exists kubectl; then
  error "kubectl is not installed. Please install kubectl first."
  exit 1
fi

# Check for minikube
if ! command_exists minikube; then
  error "minikube is not installed. Please install minikube first."
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

# Define ports with defaults and alternatives
JAEGER_PORT=16686
PROM_PORT=9091  # Changed from 9090 to avoid conflict with system Prometheus

# Check for port conflicts and use alternatives if needed
section "Checking for Port Conflicts"
if port_in_use $JAEGER_PORT; then
  log "Port $JAEGER_PORT is already in use. Trying alternative port 16687..."
  JAEGER_PORT=16687
  if port_in_use $JAEGER_PORT; then
    error "Alternative port $JAEGER_PORT is also in use. Please free a port manually."
    exit 1
  fi
fi

if port_in_use $PROM_PORT; then
  log "Port $PROM_PORT is already in use. Trying alternative port 9092..."
  PROM_PORT=9092
  if port_in_use $PROM_PORT; then
    error "Alternative port $PROM_PORT is also in use. Please free a port manually."
    exit 1
  fi
fi

# Deploy all components
section "Deploying Jaeger SPM Components"
log "Applying Kubernetes manifests..."
kubectl apply -k $(dirname "$0")/kubernetes/base/jaeger-spm

# Wait for pods to be ready with better error handling
log "Waiting for pods to be ready..."
if ! kubectl wait --for=condition=Ready pods --all --timeout=180s; then
  error "Not all pods are ready. Checking pod status:"
  kubectl get pods
  log "Continuing anyway, but some features may not work properly."
fi

# Get service details
section "Service Information"
log "Deployed services:"
kubectl get svc

# Setup port forwarding with verification
section "Setting Up Port Forwarding"

# Function to set up port forwarding with retries
setup_port_forward() {
  local service=$1
  local local_port=$2
  local remote_port=$3
  local max_attempts=3
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    log "Setting up port forwarding for $service on port $local_port (attempt $attempt/$max_attempts)..."
    kubectl port-forward svc/$service $local_port:$remote_port > /dev/null 2>&1 &
    local pid=$!
    
    # Give port forwarding time to establish
    sleep 3
    
    # Check if process is still running
    if ps -p $pid > /dev/null; then
      log "Port forwarding for $service established successfully."
      echo $pid
      return 0
    else
      log "Port forwarding for $service failed. Retrying..."
      attempt=$((attempt+1))
    fi
  done
  
  error "Failed to set up port forwarding for $service after $max_attempts attempts."
  return 1
}

# Set up Jaeger port forwarding
JAEGER_PF_PID=$(setup_port_forward jaeger $JAEGER_PORT 16686)
if [ $? -ne 0 ]; then
  error "Could not set up Jaeger port forwarding. Demo may not work correctly."
else
  # Verify Jaeger port forwarding
  verify_port_forward "Jaeger" $JAEGER_PORT 5
fi

# Set up Prometheus port forwarding
PROM_PF_PID=$(setup_port_forward prometheus $PROM_PORT 9090)
if [ $? -ne 0 ]; then
  error "Could not set up Prometheus port forwarding. Demo may not work correctly."
else
  # Verify Prometheus port forwarding
  verify_port_forward "Prometheus" $PROM_PORT 5
fi

# Get HotROD URL with error handling
log "Getting HotROD URL..."
HOTROD_URL=$(minikube service hotrod --url 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$HOTROD_URL" ]; then
  error "Could not get HotROD URL. Using default values."
  HOTROD_HOST="192.168.49.2"
  HOTROD_PORT="8080"
  HOTROD_URL="http://$HOTROD_HOST:$HOTROD_PORT"
else
  HOTROD_HOST=$(echo $HOTROD_URL | sed 's|http://||' | cut -d':' -f1)
  HOTROD_PORT=$(echo $HOTROD_URL | sed 's|http://||' | cut -d':' -f2)
fi

# Display access information
section "Access Information"
echo -e "${YELLOW}Jaeger UI:${NC} http://localhost:$JAEGER_PORT"
echo -e "${YELLOW}Prometheus:${NC} http://localhost:$PROM_PORT"
echo -e "${YELLOW}HotROD Application:${NC} $HOTROD_URL"

# Generate traffic
section "Generating Traffic"
log "Starting traffic generation to create traces and metrics..."
log "Will generate traffic for 60 seconds..."

# Run traffic generator with timeout and error handling
HOTROD_HOST=$HOTROD_HOST \
HOTROD_PORT=$HOTROD_PORT \
RUNTIME=60s \
$(dirname "$0")/generate_traffic.sh &
TRAFFIC_PID=$!

# Wait for traffic generation to complete with timeout
wait_timeout=70  # Slightly longer than traffic runtime
log "Waiting for traffic generation to complete (timeout: ${wait_timeout}s)..."
timeout $wait_timeout tail --pid=$TRAFFIC_PID -f /dev/null
if [ $? -eq 124 ]; then
  error "Traffic generation timed out. Continuing anyway."
fi

# Verify services are still accessible
section "Verifying Services"
log "Checking if Jaeger UI is accessible..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:$JAEGER_PORT; then
  log "Jaeger UI is accessible."
else
  error "Jaeger UI is not accessible. Port forwarding may have failed."
  # Try to restart port forwarding
  kill $JAEGER_PF_PID 2>/dev/null || true
  log "Restarting Jaeger port forwarding..."
  kubectl port-forward svc/jaeger $JAEGER_PORT:16686 > /dev/null 2>&1 &
  JAEGER_PF_PID=$!
fi

log "Checking if Prometheus is accessible..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:$PROM_PORT; then
  log "Prometheus is accessible."
else
  error "Prometheus is not accessible. Port forwarding may have failed."
  # Try to restart port forwarding
  kill $PROM_PF_PID 2>/dev/null || true
  log "Restarting Prometheus port forwarding..."
  kubectl port-forward svc/prometheus $PROM_PORT:9090 > /dev/null 2>&1 &
  PROM_PF_PID=$!
fi

section "Demo Complete"
echo -e "${YELLOW}Demonstration is now running.${NC}"
echo -e "You can access the following UIs to view the SPM functionality:"
echo -e "${GREEN}1. Jaeger UI:${NC} http://localhost:$JAEGER_PORT"
echo -e "   - Click on the \"Service Performance\" tab to see SPM metrics"
echo -e "${GREEN}2. Prometheus:${NC} http://localhost:$PROM_PORT"
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
