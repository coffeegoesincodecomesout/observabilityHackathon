#!/bin/bash

# Continuous traffic generator for keeping alerts firing
# Usage: ./generate-continuous-traffic.sh [requests_per_second]

RATE=${1:-2}  # Default 2 requests per second
NS1="ns1-uwl"
NS2="ns2-uwl"

echo "Starting continuous traffic generation at $RATE requests/second"
echo "Press Ctrl+C to stop"
echo ""

# Get routes
NS1_ROUTE=$(oc get route threepilar-example-route -n $NS1 -o jsonpath='{.spec.host}')
NS2_ROUTE=$(oc get route threepilar-frontend-route -n $NS2 -o jsonpath='{.spec.host}')

if [ -z "$NS1_ROUTE" ] || [ -z "$NS2_ROUTE" ]; then
    echo "Error: Could not get routes. Ensure you're logged into the cluster."
    exit 1
fi

echo "Targeting:"
echo "  NS1: http://$NS1_ROUTE/ping"
echo "  NS2: http://$NS2_ROUTE/ping"
echo ""

SLEEP_TIME=$(echo "scale=2; 1 / $RATE" | bc)
REQUEST_COUNT=0
START_TIME=$(date +%s)

cleanup() {
    ELAPSED=$(($(date +%s) - START_TIME))
    echo ""
    echo "Stopping traffic generation..."
    echo "Total requests: $REQUEST_COUNT"
    echo "Duration: ${ELAPSED}s"
    echo "Average rate: $(echo "scale=2; $REQUEST_COUNT / $ELAPSED" | bc) req/s"
    exit 0
}

trap cleanup SIGINT SIGTERM

while true; do
    # Hit ns1-uwl app
    curl -s http://$NS1_ROUTE/ping > /dev/null 2>&1 &

    # Hit ns2-uwl frontend
    curl -s http://$NS2_ROUTE/ping > /dev/null 2>&1 &

    REQUEST_COUNT=$((REQUEST_COUNT + 2))

    # Print status every 10 requests
    if [ $((REQUEST_COUNT % 10)) -eq 0 ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        CURRENT_RATE=$(echo "scale=2; $REQUEST_COUNT / $ELAPSED" | bc 2>/dev/null || echo "N/A")
        echo -ne "\rRequests: $REQUEST_COUNT | Elapsed: ${ELAPSED}s | Rate: ${CURRENT_RATE} req/s    "
    fi

    sleep $SLEEP_TIME
done
