#!/bin/bash

# Quick verification of the entire observability stack components

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

check_component() {
    local name=$1
    local namespace=$2
    local resource_type=$3
    local resource_name=$4

    echo -n "  $name: "
    if oc get $resource_type $resource_name -n $namespace > /dev/null 2>&1; then
        if [ "$resource_type" = "deployment" ] || [ "$resource_type" = "statefulset" ]; then
            READY=$(oc get $resource_type $resource_name -n $namespace -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            DESIRED=$(oc get $resource_type $resource_name -n $namespace -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
            if [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
                echo -e "${GREEN}✓${NC} ($READY/$DESIRED ready)"
            else
                echo -e "${YELLOW}⚠${NC} ($READY/$DESIRED ready)"
            fi
        else
            echo -e "${GREEN}✓${NC}"
        fi
    else
        echo -e "${RED}✗ NOT FOUND${NC}"
    fi
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenShift Observability Stack Verification${NC}"
echo -e "${BLUE}========================================${NC}"

print_header "Storage (ODF/Noobaa)"
check_component "Noobaa" "openshift-storage" "noobaa" "noobaa"
check_component "ODF Operator" "openshift-storage" "deployment" "odf-operator-controller-manager"

print_header "Logging Stack"
check_component "Cluster Logging Operator" "openshift-logging" "deployment" "cluster-logging-operator"
check_component "Collector DaemonSet" "openshift-logging" "daemonset" "collector"
check_component "Loki" "openshift-logging" "deployment" "logging-loki-distributor"

print_header "Metrics Stack (User Workload Monitoring)"
check_component "Prometheus (User Workload)" "openshift-user-workload-monitoring" "prometheus" "user-workload"
check_component "Thanos Ruler" "openshift-user-workload-monitoring" "statefulset" "thanos-ruler-user-workload"

print_header "Tracing Stack"
check_component "OpenTelemetry Operator" "openshift-opentelemetry-operator" "deployment" "opentelemetry-operator-controller-manager"
check_component "OTEL Collector" "opentelemetry" "deployment" "otel-collector"
check_component "Tempo Distributor" "tempo" "deployment" "tempo-distributor"
check_component "Tempo Ingester" "tempo" "statefulset" "tempo-ingester"
check_component "Tempo Querier" "tempo" "deployment" "tempo-querier"

print_header "Observability UI"
check_component "Cluster Observability Operator" "openshift-observability-operator" "deployment" "cluster-observability-operator"

print_header "Application Namespaces"
check_component "ns1-uwl namespace" "ns1-uwl" "namespace" "ns1-uwl"
check_component "ns1-uwl app" "ns1-uwl" "deployment" "threepilar-uwl-example-app"
check_component "ns1-uwl ServiceMonitor" "ns1-uwl" "servicemonitor" "threepilar-uwl-example-monitor"
check_component "ns1-uwl PrometheusRule" "ns1-uwl" "prometheusrule" "example-alert"
check_component "ns1-uwl AlertingRule (Loki)" "ns1-uwl" "alertingrule" "threepilars-logging-alert"

echo ""
check_component "ns2-uwl namespace" "ns2-uwl" "namespace" "ns2-uwl"
check_component "ns2-uwl frontend" "ns2-uwl" "deployment" "threepilar-uwl-frontend"
check_component "ns2-uwl backend" "ns2-uwl" "deployment" "threepilar-uwl-backend"
check_component "ns2-uwl ServiceMonitor" "ns2-uwl" "servicemonitor" "threepilar-frontend-monitor"
check_component "ns2-uwl PrometheusRule" "ns2-uwl" "prometheusrule" "example-alert"
check_component "ns2-uwl AlertingRule (Loki)" "ns2-uwl" "alertingrule" "threepilars-ns2-logging-alert"

print_header "Network Observability"
check_component "FlowCollector" "openshift-netobserv-operator" "flowcollector" "cluster"
check_component "NetObserv PrometheusRule" "openshift-monitoring" "prometheusrule" "netobserv-alerts"
check_component "FlowLogs Pipeline" "netobserv" "deployment" "flowlogs-pipeline"

print_header "Application Routes"
NS1_ROUTE=$(oc get route threepilar-example-route -n ns1-uwl -o jsonpath='{.spec.host}' 2>/dev/null)
NS2_ROUTE=$(oc get route threepilar-frontend-route -n ns2-uwl -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -n "$NS1_ROUTE" ]; then
    echo -e "  ns1-uwl: ${GREEN}http://$NS1_ROUTE/ping${NC}"
else
    echo -e "  ns1-uwl: ${RED}Route not found${NC}"
fi

if [ -n "$NS2_ROUTE" ]; then
    echo -e "  ns2-uwl: ${GREEN}http://$NS2_ROUTE/ping${NC}"
else
    echo -e "  ns2-uwl: ${RED}Route not found${NC}"
fi

print_header "Quick Access Commands"
echo -e "  ${YELLOW}Prometheus UI:${NC}"
echo -e "    oc port-forward -n openshift-user-workload-monitoring prometheus-user-workload-0 9090:9090"
echo -e "    Open: http://localhost:9090"
echo ""
echo -e "  ${YELLOW}Tempo Query UI:${NC}"
echo -e "    oc port-forward -n tempo svc/tempo-query-frontend 3200:3200"
echo -e "    Open: http://localhost:3200"
echo ""
echo -e "  ${YELLOW}OpenShift Console (Observe):${NC}"
echo -e "    oc get console cluster -o jsonpath='{.status.consoleURL}'"
echo ""
echo -e "  ${YELLOW}Generate Traffic:${NC}"
echo -e "    ./generate-continuous-traffic.sh"
echo ""
echo -e "  ${YELLOW}Check Alerts:${NC}"
echo -e "    ./check-alerts.sh"
echo ""
echo -e "  ${YELLOW}Full Test Suite:${NC}"
echo -e "    ./test-observability.sh"

echo -e "\n${GREEN}Stack verification complete!${NC}\n"
