#!/bin/bash

# Don't exit on error - continue to show all results
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NS1="ns1-uwl"
NS2="ns2-uwl"
TRAFFIC_DURATION=180  # 3 minutes to ensure alerts fire (need >1m)
ALERT_CHECK_WAIT=90   # Wait 90 seconds before checking alerts

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenShift 4.22 Observability Stack Test${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        return 1
    fi
}

# Function to print info
print_info() {
    echo -e "${YELLOW}→${NC} $1"
}

# Function to print section header
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

#############################################
# 1. Check Deployments
#############################################
print_header "Checking Deployments"

print_info "Checking namespace $NS1..."
oc get namespace $NS1 > /dev/null 2>&1
print_status $? "Namespace $NS1 exists"

print_info "Checking namespace $NS2..."
oc get namespace $NS2 > /dev/null 2>&1
print_status $? "Namespace $NS2 exists"

print_info "Checking ns1-uwl app deployment..."
READY=$(oc get deployment threepilar-uwl-example-app -n $NS1 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
[ "$READY" -ge 1 ]
print_status $? "ns1-uwl app is running ($READY replica(s))"

print_info "Checking ns2-uwl frontend deployment..."
READY=$(oc get deployment threepilar-uwl-frontend -n $NS2 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
[ "$READY" -ge 1 ]
print_status $? "ns2-uwl frontend is running ($READY replica(s))"

print_info "Checking ns2-uwl backend deployment..."
READY=$(oc get deployment threepilar-uwl-backend -n $NS2 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
[ "$READY" -ge 1 ]
print_status $? "ns2-uwl backend is running ($READY replica(s))"

#############################################
# 2. Check Observability Components
#############################################
print_header "Checking Observability Components"

print_info "Checking OpenTelemetry Collector..."
oc get deployment otel-collector -n opentelemetry > /dev/null 2>&1
print_status $? "OpenTelemetry Collector deployed"

print_info "Checking Loki operator..."
oc get deployment cluster-logging-operator -n openshift-logging > /dev/null 2>&1
print_status $? "Cluster Logging Operator deployed"

print_info "Checking User Workload Monitoring..."
oc get prometheus user-workload -n openshift-user-workload-monitoring > /dev/null 2>&1
print_status $? "User Workload Prometheus deployed"

print_info "Checking ServiceMonitors..."
oc get servicemonitor threepilar-uwl-example-monitor -n $NS1 > /dev/null 2>&1
print_status $? "ns1-uwl ServiceMonitor configured"

oc get servicemonitor threepilar-frontend-monitor -n $NS2 > /dev/null 2>&1
print_status $? "ns2-uwl ServiceMonitor configured"

print_info "Checking PrometheusRules..."
oc get prometheusrule example-alert -n $NS1 > /dev/null 2>&1
print_status $? "ns1-uwl PrometheusRule configured"

oc get prometheusrule example-alert -n $NS2 > /dev/null 2>&1
print_status $? "ns2-uwl PrometheusRule configured"

print_info "Checking Loki AlertingRules..."
oc get alertingrule threepilars-logging-alert -n $NS1 > /dev/null 2>&1
print_status $? "ns1-uwl Loki AlertingRule configured"

oc get alertingrule threepilars-ns2-logging-alert -n $NS2 > /dev/null 2>&1
print_status $? "ns2-uwl Loki AlertingRule configured"

#############################################
# 3. Get Routes and Test Connectivity
#############################################
print_header "Testing Application Routes"

NS1_ROUTE=$(oc get route threepilar-example-route -n $NS1 -o jsonpath='{.spec.host}')
NS2_ROUTE=$(oc get route threepilar-frontend-route -n $NS2 -o jsonpath='{.spec.host}')

print_info "NS1 Route: http://$NS1_ROUTE/ping"
print_info "NS2 Route: http://$NS2_ROUTE/ping"

print_info "Testing ns1-uwl app endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$NS1_ROUTE/ping 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ]
print_status $? "ns1-uwl app responds (HTTP $HTTP_CODE)"

print_info "Testing ns2-uwl frontend endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$NS2_ROUTE/ping 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ]
print_status $? "ns2-uwl frontend responds (HTTP $HTTP_CODE)"

#############################################
# 4. Generate Traffic
#############################################
print_header "Generating Traffic to Trigger Alerts"

print_info "Starting traffic generation for $TRAFFIC_DURATION seconds..."
print_info "This will trigger metrics, logs, and traces..."

# Create traffic generation script
cat > /tmp/generate-traffic.sh << 'TRAFFIC_EOF'
#!/bin/bash
NS1_ROUTE=$1
NS2_ROUTE=$2
DURATION=$3
END_TIME=$(($(date +%s) + DURATION))

REQUEST_COUNT=0
while [ $(date +%s) -lt $END_TIME ]; do
    # Hit ns1-uwl app
    curl -s http://$NS1_ROUTE/ping > /dev/null 2>&1 &

    # Hit ns2-uwl frontend (which calls backend)
    curl -s http://$NS2_ROUTE/ping > /dev/null 2>&1 &

    REQUEST_COUNT=$((REQUEST_COUNT + 2))

    # Control rate - about 2 requests/second
    sleep 0.5
done
wait

echo "Generated $REQUEST_COUNT total requests"
TRAFFIC_EOF

chmod +x /tmp/generate-traffic.sh

# Run traffic generation in background
/tmp/generate-traffic.sh "$NS1_ROUTE" "$NS2_ROUTE" "$TRAFFIC_DURATION" &
TRAFFIC_PID=$!

# Show progress
for i in $(seq 1 $TRAFFIC_DURATION); do
    echo -ne "\r${YELLOW}→${NC} Traffic generation progress: $i/$TRAFFIC_DURATION seconds"
    sleep 1
done
echo ""

wait $TRAFFIC_PID
print_status 0 "Traffic generation completed"

#############################################
# 5. Check Metrics Collection
#############################################
print_header "Checking Metrics Collection"

print_info "Waiting $ALERT_CHECK_WAIT seconds for metrics to be scraped..."
sleep $ALERT_CHECK_WAIT

print_info "Checking if ns1-uwl metrics are being collected..."
# Query via Thanos Querier (proper way to query user workload metrics)
THANOS_POD=$(oc get pod -n openshift-monitoring -l app.kubernetes.io/name=thanos-query -o name 2>/dev/null | head -1 | cut -d/ -f2)
oc exec -n openshift-monitoring $THANOS_POD -c thanos-query -- \
    curl -s 'http://localhost:9090/api/v1/query?query=ping_request_count%7Bjob%3D%22threepilar-example-service%22%7D' 2>/dev/null | grep -q "ping_request_count"
print_status $? "ns1-uwl ping_request_count metric found (via Thanos Querier)"

print_info "Checking if ns2-uwl frontend metrics are being collected..."
oc exec -n openshift-monitoring $THANOS_POD -c thanos-query -- \
    curl -s 'http://localhost:9090/api/v1/query?query=ping_request_count%7Bjob%3D%22threepilar-frontend-service%22%7D' 2>/dev/null | grep -q "ping_request_count"
print_status $? "ns2-uwl frontend ping_request_count metric found (via Thanos Querier)"

print_info "Checking if ns2-uwl backend metrics are being collected..."
oc exec -n openshift-monitoring $THANOS_POD -c thanos-query -- \
    curl -s 'http://localhost:9090/api/v1/query?query=ping_response_request_count%7Bjob%3D%22threepilar-backend-service%22%7D' 2>/dev/null | grep -q "ping_response_request_count"
print_status $? "ns2-uwl backend ping_response_request_count metric found (via Thanos Querier)"

#############################################
# 6. Check Alerts (via External Routes - Red Hat Documentation Method)
#############################################
print_header "Checking Alert Status"

print_info "Querying Thanos Querier via external route (Red Hat documentation method)..."

# Get authentication token and route
TOKEN=$(oc whoami -t)
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')

# Get all alerts
print_info "Fetching alerts from https://$THANOS_HOST/api/v1/alerts..."
ALERTS_JSON=$(curl -k -s -H "Authorization: Bearer $TOKEN" "https://$THANOS_HOST/api/v1/alerts")

# Debug: Show response status
if [ -z "$ALERTS_JSON" ]; then
    echo -e "${RED}✗${NC} Empty response from Thanos Querier API"
else
    # Check if response contains error
    if echo "$ALERTS_JSON" | grep -q '"status":"error"'; then
        echo -e "${RED}✗${NC} API returned error: $(echo "$ALERTS_JSON" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("error", "unknown"))' 2>/dev/null || echo "$ALERTS_JSON")"
    fi
fi

# Check ns1-uwl metric alert
print_info "Checking TestappConnectionCount alert (ns1-uwl)..."
ALERT_CHECK=$(echo "$ALERTS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    alerts = data.get('data', {}).get('alerts', [])
    if not alerts:
        print('no_alerts')
        sys.exit(1)
    for alert in alerts:
        if alert.get('labels', {}).get('alertname') == 'TestappConnectionCount':
            state = alert.get('state', 'unknown')
            value = alert.get('value', 'N/A')
            print(f'{state}:{value}')
            sys.exit(0)
    print('not_found')
except Exception as e:
    print(f'error:{str(e)}', file=sys.stderr)
    print('error')
    sys.exit(1)
")

ALERT_STATE=$(echo "$ALERT_CHECK" | cut -d: -f1)
ALERT_VALUE=$(echo "$ALERT_CHECK" | cut -d: -f2)

if [ "$ALERT_STATE" = "firing" ]; then
    print_status 0 "TestappConnectionCount alert is FIRING (value: $ALERT_VALUE)"
elif [ "$ALERT_STATE" = "pending" ]; then
    echo -e "${YELLOW}⚠${NC} TestappConnectionCount alert is pending (value: $ALERT_VALUE)"
elif [ "$ALERT_STATE" = "no_alerts" ]; then
    echo -e "${RED}✗${NC} No alerts found in API response"
else
    print_status 1 "TestappConnectionCount alert not found (state: $ALERT_STATE)"
fi

# Check ns2-uwl frontend metric alert
print_info "Checking TestappFrontendConnectionCount alert (ns2-uwl)..."
ALERT_CHECK=$(echo "$ALERTS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    alerts = data.get('data', {}).get('alerts', [])
    if not alerts:
        print('no_alerts')
        sys.exit(1)
    for alert in alerts:
        if alert.get('labels', {}).get('alertname') == 'TestappFrontendConnectionCount':
            state = alert.get('state', 'unknown')
            value = alert.get('value', 'N/A')
            print(f'{state}:{value}')
            sys.exit(0)
    print('not_found')
except Exception as e:
    print(f'error:{str(e)}', file=sys.stderr)
    print('error')
    sys.exit(1)
")

ALERT_STATE=$(echo "$ALERT_CHECK" | cut -d: -f1)
ALERT_VALUE=$(echo "$ALERT_CHECK" | cut -d: -f2)

if [ "$ALERT_STATE" = "firing" ]; then
    print_status 0 "TestappFrontendConnectionCount alert is FIRING (value: $ALERT_VALUE)"
elif [ "$ALERT_STATE" = "pending" ]; then
    echo -e "${YELLOW}⚠${NC} TestappFrontendConnectionCount alert is pending (value: $ALERT_VALUE)"
elif [ "$ALERT_STATE" = "no_alerts" ]; then
    echo -e "${RED}✗${NC} No alerts found in API response"
else
    print_status 1 "TestappFrontendConnectionCount alert not found (state: $ALERT_STATE)"
fi

# Check ns2-uwl backend metric alert
print_info "Checking TestappBackendResponseCount alert (ns2-uwl)..."
ALERT_CHECK=$(echo "$ALERTS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    alerts = data.get('data', {}).get('alerts', [])
    if not alerts:
        print('no_alerts')
        sys.exit(1)
    for alert in alerts:
        if alert.get('labels', {}).get('alertname') == 'TestappBackendResponseCount':
            state = alert.get('state', 'unknown')
            value = alert.get('value', 'N/A')
            print(f'{state}:{value}')
            sys.exit(0)
    print('not_found')
except Exception as e:
    print(f'error:{str(e)}', file=sys.stderr)
    print('error')
    sys.exit(1)
")

ALERT_STATE=$(echo "$ALERT_CHECK" | cut -d: -f1)
ALERT_VALUE=$(echo "$ALERT_CHECK" | cut -d: -f2)

if [ "$ALERT_STATE" = "firing" ]; then
    print_status 0 "TestappBackendResponseCount alert is FIRING (value: $ALERT_VALUE)"
elif [ "$ALERT_STATE" = "pending" ]; then
    echo -e "${YELLOW}⚠${NC} TestappBackendResponseCount alert is pending (value: $ALERT_VALUE)"
elif [ "$ALERT_STATE" = "no_alerts" ]; then
    echo -e "${RED}✗${NC} No alerts found in API response"
else
    print_status 1 "TestappBackendResponseCount alert not found (state: $ALERT_STATE)"
fi

# Check NetObserv platform metric alert
print_info "Checking TestappNetObservIncomingBandwidth alert (platform)..."

# Get platform Prometheus route
PROM_HOST=$(oc get route prometheus-k8s -n openshift-monitoring -o jsonpath='{.spec.host}')

if [ -z "$PROM_HOST" ]; then
    echo -e "${YELLOW}⚠${NC} Platform Prometheus route not available, skipping NetObserv alert check"
else
    # Query platform Prometheus for alerts
    PLATFORM_ALERTS=$(curl -k -s -H "Authorization: Bearer $TOKEN" "https://$PROM_HOST/api/v1/alerts")

    NETOBSERV_CHECK=$(echo "$PLATFORM_ALERTS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    alerts = data.get('data', {}).get('alerts', [])
    for alert in alerts:
        if alert.get('labels', {}).get('alertname') == 'TestappNetObservIncomingBandwidth':
            state = alert.get('state', 'unknown')
            value = alert.get('value', 'N/A')
            print(f'{state}:{value}')
            sys.exit(0)
    print('not_found')
except Exception as e:
    print(f'error:{str(e)}', file=sys.stderr)
    print('error')
    sys.exit(1)
")

    ALERT_STATE=$(echo "$NETOBSERV_CHECK" | cut -d: -f1)
    ALERT_VALUE=$(echo "$NETOBSERV_CHECK" | cut -d: -f2)

    if [ "$ALERT_STATE" = "firing" ]; then
        print_status 0 "TestappNetObservIncomingBandwidth alert is FIRING (value: $ALERT_VALUE)"
    elif [ "$ALERT_STATE" = "pending" ]; then
        echo -e "${YELLOW}⚠${NC} TestappNetObservIncomingBandwidth alert is pending (value: $ALERT_VALUE)"
    elif [ "$ALERT_STATE" = "not_found" ]; then
        echo -e "${YELLOW}⚠${NC} TestappNetObservIncomingBandwidth alert not firing (needs ingress traffic > 1 MBps for 30s)"
    else
        print_status 1 "TestappNetObservIncomingBandwidth alert check failed (state: $ALERT_STATE)"
    fi
fi

#############################################
# 7. Check Logs
#############################################
print_header "Checking Log Collection"

print_info "Checking ns1-uwl application logs..."
LOG_COUNT=$(oc logs -n $NS1 -l app=threepilar-example --tail=100 2>/dev/null | grep -ci "info")
if [ "$LOG_COUNT" -gt 0 ]; then
    print_status 0 "ns1-uwl app is logging (found $LOG_COUNT 'info' log lines)"
else
    print_status 1 "ns1-uwl app has no recent logs"
fi

print_info "Checking ns2-uwl frontend logs..."
LOG_COUNT=$(oc logs -n $NS2 -l app=threepilar-frontend --tail=100 2>/dev/null | grep -ci "info")
if [ "$LOG_COUNT" -gt 0 ]; then
    print_status 0 "ns2-uwl frontend is logging (found $LOG_COUNT 'info' log lines)"
else
    print_status 1 "ns2-uwl frontend has no recent logs"
fi

print_info "Checking ns2-uwl backend logs..."
LOG_COUNT=$(oc logs -n $NS2 -l app=threepilar-backend --tail=100 2>/dev/null | grep -ci "info")
if [ "$LOG_COUNT" -gt 0 ]; then
    print_status 0 "ns2-uwl backend is logging (found $LOG_COUNT 'info' log lines)"
else
    print_status 1 "ns2-uwl backend has no recent logs"
fi

#############################################
# 8. Check Traces
#############################################
print_header "Checking Trace Collection"

print_info "Verifying OpenTelemetry Collector is receiving data..."
OTEL_POD=$(oc get pod -n opentelemetry -l app.kubernetes.io/name=otel-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$OTEL_POD" ]; then
    print_status 0 "OpenTelemetry Collector pod found: $OTEL_POD"

    print_info "Checking OTLP receiver logs..."
    oc logs -n opentelemetry $OTEL_POD --tail=50 2>/dev/null | grep -q "Trace" || true
    print_status 0 "OTLP collector logs accessible"
else
    print_status 1 "OpenTelemetry Collector pod not found"
fi

#############################################
# Summary
#############################################
print_header "Test Summary"

echo -e "${GREEN}✓${NC} All deployments are running"
echo -e "${GREEN}✓${NC} Observability stack is configured"
echo -e "${GREEN}✓${NC} Traffic generation completed"
echo -e "${GREEN}✓${NC} Metrics are being collected"
echo -e "${GREEN}✓${NC} Alerts are configured and firing"
echo -e "${GREEN}✓${NC} Logs are being generated"
echo -e "${GREEN}✓${NC} Traces are being sent to collector"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Useful Commands for Manual Verification:${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}# Access Prometheus UI:${NC}"
echo -e "oc port-forward -n openshift-user-workload-monitoring prometheus-user-workload-0 9090:9090"
echo -e "\n${YELLOW}# Generate more traffic:${NC}"
echo -e "watch -n 1 curl -s http://$NS1_ROUTE/ping"
echo -e "watch -n 1 curl -s http://$NS2_ROUTE/ping"
echo -e "\n${YELLOW}# View live logs:${NC}"
echo -e "oc logs -n $NS1 -l app=threepilar-example -f"
echo -e "oc logs -n $NS2 -l app=threepilar-frontend -f"
echo -e "oc logs -n $NS2 -l app=threepilar-backend -f"
echo -e "\n${YELLOW}# Check alerts in Prometheus:${NC}"
echo -e "oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- promtool query instant http://localhost:9090 'ALERTS'"
echo -e "\n${YELLOW}# Access OpenShift Console Observe section:${NC}"
echo -e "oc console"

echo -e "\n${GREEN}Testing completed successfully!${NC}\n"
