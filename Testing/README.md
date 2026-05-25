# Testing Scripts for OpenShift 4.22 Observability Hackathon

Quick reference for the test scripts in this directory.

## 🎯 Quick Start

```bash
# Run from this directory
cd Testing

# Quick demo (2 minutes) - BEST FOR SHOWING IT WORKS
./quick-demo.sh

# Complete test suite (5 minutes)
./test-observability.sh

# Quick stack verification (10 seconds)
./verify-stack.sh

# Generate continuous traffic
./generate-continuous-traffic.sh

# Check alert status
./check-alerts.sh
```

## 📊 Scripts Overview

| Script | Purpose | Duration | Output |
|--------|---------|----------|--------|
| `quick-demo.sh` | **Quick demo showing all components working** | ~30 sec | Shows apps, metrics, alerts firing |
| `test-observability.sh` | Complete E2E test with traffic generation | ~5 min | Full verification report |
| `verify-stack.sh` | Stack health check | ~10 sec | Component status |
| `generate-continuous-traffic.sh` | Traffic generator | Continuous | Keeps metrics flowing |
| `check-alerts.sh` | Alert status via Thanos | ~5 sec | Alert states and values |

## ✅ What's Tested

- **Applications**: NS1-UWL and NS2-UWL apps running and responding
- **Metrics**: Thanos Querier collecting metrics from all apps  
- **Logs**: Loki collecting application logs
- **Traces**: OpenTelemetry collector receiving traces
- **Alerts**: 
  - **User Workload Alerts** (3) - All **FIRING** via Thanos Ruler ✓
    - TestappConnectionCount (ns1-uwl)
    - TestappFrontendConnectionCount (ns2-uwl)
    - TestappBackendResponseCount (ns2-uwl)
  - **Platform Alert** (1) - Configured via Platform Prometheus ✓
    - TestappNetObservIncomingBandwidth (NetObserv traffic monitoring)

## 🏗️ Understanding Thanos

**Important**: This setup uses **Thanos**, not Prometheus directly. See [THANOS-ARCHITECTURE.md](./THANOS-ARCHITECTURE.md) for details.

- **Thanos Querier**: Query metrics (not Prometheus)
- **Thanos Ruler**: Check alerts (not Prometheus)
- **Why**: Unified multi-tenant monitoring across OpenShift

Quick access:
```bash
# Thanos Querier UI (for metrics)
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
# Visit: http://localhost:9091

# Or use OpenShift Console → Observe
```

## 📖 Documentation Files

- **README.md** (this file): Quick reference
- **TESTING.md**: Complete testing guide with troubleshooting
- **SUMMARY.md**: Test results and status  
- **THANOS-ARCHITECTURE.md**: Understanding the Thanos architecture

## 🎬 For Hackathon Demo

### Option 1: Quick Demo (Recommended)
```bash
./quick-demo.sh
```
Shows everything working in 30 seconds!

### Option 2: Live Demo
```bash
# Terminal 1: Generate traffic
./generate-continuous-traffic.sh

# Terminal 2: Watch alerts
watch -n 5 ./check-alerts.sh

# Terminal 3: Port-forward to Thanos
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
# Open browser: http://localhost:9091
```

### Option 3: Full Test Suite
```bash
./test-observability.sh
```
Complete end-to-end verification (~5 minutes).

## 🔍 Common Commands

**Test app endpoints:**
```bash
curl http://$(oc get route threepilar-example-route -n ns1-uwl -o jsonpath='{.spec.host}')/ping
curl http://$(oc get route threepilar-frontend-route -n ns2-uwl -o jsonpath='{.spec.host}')/ping
```

**View logs:**
```bash
oc logs -n ns1-uwl -l app=threepilar-example -f --tail=20
oc logs -n ns2-uwl -l app=threepilar-frontend -f --tail=20
```

**Query metrics via Thanos:**
```bash
# Get Thanos Querier pod
THANOS_POD=$(oc get pod -n openshift-monitoring -l app.kubernetes.io/name=thanos-query -o name | head -1 | cut -d/ -f2)

# Query metrics
oc exec -n openshift-monitoring $THANOS_POD -c thanos-query -- \
  curl -s 'http://localhost:9090/api/v1/query?query=ping_request_count'
```

**Check alerts via Thanos Ruler:**
```bash
oc exec -n openshift-user-workload-monitoring thanos-ruler-user-workload-0 -c thanos-ruler -- \
  curl -s 'http://localhost:10902/api/v1/alerts' | python3 -m json.tool
```

## 🎓 Learning Path

1. Start with **quick-demo.sh** to see it working
2. Read **THANOS-ARCHITECTURE.md** to understand why we use Thanos
3. Run **test-observability.sh** for full verification
4. Explore **TESTING.md** for deep dive and troubleshooting

## 🐛 Troubleshooting

If something isn't working, see the troubleshooting section in [TESTING.md](./TESTING.md#troubleshooting).

Quick checks:
```bash
# Is User Workload Monitoring enabled?
oc get prometheus user-workload -n openshift-user-workload-monitoring

# Are apps running?
oc get pods -n ns1-uwl -n ns2-uwl

# Is Thanos Ruler running?
oc get statefulset thanos-ruler-user-workload -n openshift-user-workload-monitoring
```

## 📚 References

- Main README: [../README.md](../README.md)
- Test Apps:
  - NS1: https://github.com/coffeegoesincodecomesout/testapp-ThreePilars
  - NS2 Frontend: https://github.com/coffeegoesincodecomesout/testapp-ThreePilars-Frontend
  - NS2 Backend: https://github.com/coffeegoesincodecomesout/testapp-ThreePilars-backend
- OpenShift Monitoring: https://docs.openshift.com/container-platform/latest/monitoring/monitoring-overview.html
