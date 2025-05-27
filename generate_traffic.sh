#!/bin/bash

# Script to generate continuous traffic to HotROD for SPM demo
# This sends requests to various HotROD endpoints at regular intervals

HOTROD_HOST=${HOTROD_HOST:-localhost}
HOTROD_PORT=${HOTROD_PORT:-8080}
HOTROD_URL="http://${HOTROD_HOST}:${HOTROD_PORT}"
DELAY=${DELAY:-1}  # Delay between requests in seconds
RUNTIME=${RUNTIME:-24h}  # How long to run (can be "infinite" for continuous)

# Customer IDs to use in requests
CUSTOMER_IDS=("123" "392" "731" "567" "111" "222" "333" "444")

# Color for log output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting HotROD traffic generator${NC}"
echo -e "HotROD URL: ${YELLOW}${HOTROD_URL}${NC}"
echo -e "Request delay: ${YELLOW}${DELAY}s${NC}"

if [ "$RUNTIME" != "infinite" ]; then
    echo -e "Running for: ${YELLOW}${RUNTIME}${NC}"
    # Convert runtime to seconds for timeout
    TIMEOUT=$(echo $RUNTIME | sed 's/h/*3600+/g' | sed 's/m/*60+/g' | sed 's/s/+/g' | sed 's/+$//' | bc)
    ENDTIME=$(($(date +%s) + $TIMEOUT))
else
    echo -e "Running ${YELLOW}indefinitely${NC}. Press Ctrl+C to stop."
    ENDTIME=0
fi

# Function to make a request and log the result
make_request() {
    local url=$1
    local description=$2
    
    echo -e "${YELLOW}Requesting:${NC} $description"
    
    status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    
    if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 300 ]; then
        echo -e "${GREEN}Success:${NC} $description (Status: $status_code)"
    else
        echo -e "${RED}Failed:${NC} $description (Status: $status_code)"
    fi
}

# Main loop
while true; do
    # Check if we've reached the endtime
    if [ $ENDTIME -ne 0 ] && [ $(date +%s) -ge $ENDTIME ]; then
        echo -e "${YELLOW}Reached end time. Stopping.${NC}"
        break
    fi
    
    # Randomly select a customer ID
    random_index=$((RANDOM % ${#CUSTOMER_IDS[@]}))
    customer_id=${CUSTOMER_IDS[$random_index]}
    
    # Home page - always hit this
    make_request "${HOTROD_URL}/" "Homepage"
    sleep $DELAY
    
    # Get customer info (with random customer ID)
    make_request "${HOTROD_URL}/customer?customer=$customer_id" "Customer info for $customer_id"
    sleep $DELAY
    
    # Different endpoints with some randomness to create variety in traces
    case $((RANDOM % 4)) in
        0)
            # Find a nearby driver 
            make_request "${HOTROD_URL}/dispatch?customer=$customer_id" "Dispatch for customer $customer_id"
            ;;
        1)
            # Direct driver call
            driver_id=$((RANDOM % 50 + 1))
            make_request "${HOTROD_URL}/driver?driver=$driver_id" "Driver info for driver $driver_id"
            ;;
        2)
            # Book a ride (GET request for simplicity)
            make_request "${HOTROD_URL}/route?pickup=123&dropoff=456" "Route calculation"
            ;;
        3)
            # Get dispatch ETA with specific customer
            make_request "${HOTROD_URL}/dispatch?customer=$customer_id" "Dispatch ETA for customer $customer_id"
            ;;
    esac
    
    # Sleep between iterations
    sleep $((DELAY * 2))
    echo "------------------------------------"
done

echo -e "${GREEN}Traffic generation complete${NC}"
