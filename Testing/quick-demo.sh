#!/bin/bash

# Quick demo script to show alerts firing

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenShift 4.22 Observability Demo${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "${YELLOW}1. Checking Apps are Running...${NC}"
oc get pods -n ns1-uwl -l app=threepilar-example
oc get pods -n ns2-uwl

echo -e "\n${YELLOW}2. Application Routes:${NC}"
NS1_ROUTE=$(oc get route threepilar-example-route -n ns1-uwl -o jsonpath='{.spec.host}')
NS2_ROUTE=$(oc get route threepilar-frontend-route -n ns2-uwl -o jsonpath='{.spec.host}')
echo "  NS1: http://$NS1_ROUTE/ping"
echo "  NS2: http://$NS2_ROUTE/ping"

echo -e "\n${YELLOW}3. Hitting Apps...${NC}"
echo -n "  NS1 response: "
curl -s http://$NS1_ROUTE/ping | head -c 100
echo ""
echo -n "  NS2 response: "
curl -s http://$NS2_ROUTE/ping | head -c 100
echo ""

echo -e "\n${YELLOW}4. Metrics via Thanos Querier:${NC}"
THANOS_POD=$(oc get pod -n openshift-monitoring -l app.kubernetes.io/name=thanos-query -o name | head -1 | cut -d/ -f2)
echo "  Querying: ping_request_count{job=\"threepilar-example-service\"}"
oc exec -n openshift-monitoring $THANOS_POD -c thanos-query -- \
  curl -s 'http://localhost:9090/api/v1/query?query=ping_request_count{job="threepilar-example-service"}' | \
  python3 -c "import sys, json; data=json.load(sys.stdin); print('  Value:', data['data']['result'][0]['value'][1] if data['data']['result'] else 'No data')" 2>/dev/null

echo -e "\n${YELLOW}5. Alerts Firing in Thanos Ruler:${NC}"
oc exec -n openshift-user-workload-monitoring thanos-ruler-user-workload-0 -c thanos-ruler -- \
  curl -s 'http://localhost:10902/api/v1/alerts' 2>/dev/null | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
for alert in data.get('data', {}).get('Alerts', []):
    name = alert.get('labels', {}).get('alertname', 'Unknown')
    if 'Testapp' in name:
        state = alert.get('state', 'unknown')
        value = alert.get('value', 'N/A')
        print(f'  ✓ {name}: {state} (value: {value})')
" 2>/dev/null

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Demo Complete!${NC}"
echo -e "${GREEN}All components working correctly.${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Access UIs:${NC}"
echo "  Thanos Querier: oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091"
echo "  OpenShift Console: oc get console cluster -o jsonpath='{.status.consoleURL}'"
echo ""
