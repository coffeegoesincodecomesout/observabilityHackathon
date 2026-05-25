#!/bin/bash

# Quick script to check alert status via Thanos

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Alert Status Check (via Thanos)${NC}"
echo -e "${BLUE}======================================${NC}\n"

# Get authentication token and route (Red Hat documentation method)
TOKEN=$(oc whoami -t)
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')

if [ -z "$THANOS_HOST" ]; then
    echo -e "${RED}Error: Cannot get Thanos Querier route${NC}"
    exit 1
fi

echo -e "${YELLOW}Querying Thanos via external route: https://$THANOS_HOST${NC}\n"

# Get all alerts from Thanos Querier (includes user workload alerts)
ALERTS_JSON=$(curl -k -s -H "Authorization: Bearer $TOKEN" "https://$THANOS_HOST/api/v1/alerts")

echo -e "${BLUE}=== User Workload Metric Alerts (from Thanos Querier) ===${NC}"

# Check specific alerts
for ALERT in "TestappConnectionCount" "TestappFrontendConnectionCount" "TestappBackendResponseCount"; do
    echo -n "  $ALERT: "
    # Use python to parse JSON properly
    ALERT_INFO=$(echo "$ALERTS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    alerts = data.get('data', {}).get('alerts', [])
    for alert in alerts:
        if alert.get('labels', {}).get('alertname') == '$ALERT':
            state = alert.get('state', 'unknown')
            value = alert.get('value', 'N/A')
            print(f'{state}|{value}')
            break
except Exception as e:
    print(f'error|{str(e)}', file=sys.stderr)
")

    if [ -n "$ALERT_INFO" ]; then
        STATE=$(echo "$ALERT_INFO" | cut -d'|' -f1)
        VALUE=$(echo "$ALERT_INFO" | cut -d'|' -f2)
        if [ "$STATE" = "firing" ]; then
            echo -e "${GREEN}FIRING${NC} (value: $VALUE)"
        elif [ "$STATE" = "pending" ]; then
            echo -e "${YELLOW}PENDING${NC} (value: $VALUE)"
        elif [ "$STATE" = "error" ]; then
            echo -e "${RED}ERROR${NC} ($VALUE)"
        else
            echo -e "${BLUE}$STATE${NC} (value: $VALUE)"
        fi
    else
        echo -e "${RED}NOT FOUND${NC}"
    fi
done

echo -e "\n${BLUE}=== Current Metric Values (from Thanos Querier) ===${NC}"

# Query metrics via external route with URL encoding
echo -n "  ns1-uwl ping_request_count: "
VALUE=$(curl -k -s -H "Authorization: Bearer $TOKEN" \
    "https://$THANOS_HOST/api/v1/query?query=ping_request_count%7Bjob%3D%22threepilar-example-service%22%7D" | \
    python3 -c "import sys, json; data=json.load(sys.stdin); print(data['data']['result'][0]['value'][1] if data.get('data', {}).get('result') else '0')" 2>/dev/null || echo "0")
echo -e "${GREEN}$VALUE${NC}"

echo -n "  ns2-uwl frontend ping_request_count: "
VALUE=$(curl -k -s -H "Authorization: Bearer $TOKEN" \
    "https://$THANOS_HOST/api/v1/query?query=ping_request_count%7Bjob%3D%22threepilar-frontend-service%22%7D" | \
    python3 -c "import sys, json; data=json.load(sys.stdin); print(data['data']['result'][0]['value'][1] if data.get('data', {}).get('result') else '0')" 2>/dev/null || echo "0")
echo -e "${GREEN}$VALUE${NC}"

echo -n "  ns2-uwl backend ping_response_request_count: "
VALUE=$(curl -k -s -H "Authorization: Bearer $TOKEN" \
    "https://$THANOS_HOST/api/v1/query?query=ping_response_request_count%7Bjob%3D%22threepilar-backend-service%22%7D" | \
    python3 -c "import sys, json; data=json.load(sys.stdin); print(data['data']['result'][0]['value'][1] if data.get('data', {}).get('result') else '0')" 2>/dev/null || echo "0")
echo -e "${GREEN}$VALUE${NC}"

echo -e "\n${BLUE}=== Platform Metric Alerts (from Platform Prometheus) ===${NC}"

# Get platform Prometheus route
PROM_HOST=$(oc get route prometheus-k8s -n openshift-monitoring -o jsonpath='{.spec.host}')

if [ -z "$PROM_HOST" ]; then
    echo -e "${YELLOW}  Platform Prometheus route not available${NC}"
else
    # Check NetObserv alert (monitored by platform Prometheus)
    echo -n "  TestappNetObservIncomingBandwidth: "
    PLATFORM_ALERTS=$(curl -k -s -H "Authorization: Bearer $TOKEN" "https://$PROM_HOST/api/v1/alerts")

    NETOBSERV_ALERT=$(echo "$PLATFORM_ALERTS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    alerts = data.get('data', {}).get('alerts', [])
    for alert in alerts:
        if alert.get('labels', {}).get('alertname') == 'TestappNetObservIncomingBandwidth':
            state = alert.get('state', 'unknown')
            value = alert.get('value', 'N/A')
            print(f'{state}|{value}')
            break
except Exception as e:
    pass
")

    if [ -n "$NETOBSERV_ALERT" ]; then
        STATE=$(echo "$NETOBSERV_ALERT" | cut -d'|' -f1)
        VALUE=$(echo "$NETOBSERV_ALERT" | cut -d'|' -f2)
        if [ "$STATE" = "firing" ]; then
            echo -e "${GREEN}FIRING${NC} (value: $VALUE)"
        elif [ "$STATE" = "pending" ]; then
            echo -e "${YELLOW}PENDING${NC} (value: $VALUE)"
        else
            echo -e "${BLUE}$STATE${NC}"
        fi
    else
        echo -e "${YELLOW}Not firing (needs ingress traffic > 1 MBps)${NC}"
    fi
fi

echo -e "\n${BLUE}=== Loki Log-Based Alerts ===${NC}"

# Check Loki alerts
echo "  TestappLogRallyCount (ns1-uwl): "
oc get alertingrule threepilars-logging-alert -n ns1-uwl -o yaml 2>/dev/null | grep -A 5 "TestappLogRallyCount" | head -6

echo -e "\n  TestappFrontendLogRallyCount (ns2-uwl): "
oc get alertingrule threepilars-ns2-logging-alert -n ns2-uwl -o yaml 2>/dev/null | grep -A 5 "TestappFrontendLogRallyCount" | head -6

echo -e "\n  TestappBackendLogResponseCount (ns2-uwl): "
oc get alertingrule threepilars-ns2-logging-alert -n ns2-uwl -o yaml 2>/dev/null | grep -A 5 "TestappBackendLogResponseCount" | head -6

echo -e "\n${BLUE}=== Quick Tips ===${NC}"
echo -e "  ${YELLOW}Alert Architecture:${NC}"
echo -e "    • This script uses Red Hat's recommended method (external routes with token auth)"
echo -e "    • Thanos Querier aggregates metrics and alerts from all Prometheus instances"
echo -e "    • User workload alerts are evaluated by Thanos Ruler and visible via Thanos Querier"
echo -e "    • Platform alerts are evaluated by Platform Prometheus"
echo ""
echo -e "  ${YELLOW}Access UIs:${NC}"
echo -e "    • Thanos Querier: oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091"
echo -e "    •   Then visit: http://localhost:9091"
echo -e "    • OpenShift Console: Navigate to Observe → Alerting"
echo ""
echo -e "  ${YELLOW}Generate Traffic:${NC}"
echo -e "    • ./generate-continuous-traffic.sh"
echo ""
echo -e "  ${YELLOW}Manual Query Example:${NC}"
echo -e "    • TOKEN=\$(oc whoami -t)"
echo -e "    • THANOS_HOST=\$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')"
echo -e "    • curl -k -H \"Authorization: Bearer \$TOKEN\" \"https://\$THANOS_HOST/api/v1/alerts\""
echo ""
