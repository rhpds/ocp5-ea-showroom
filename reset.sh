#!/usr/bin/env bash
# Reset the OCP5 EA cluster to pre-exercise state.
# Idempotent — safe to run multiple times.
# Does NOT revert BYOM (Bring Your Own Model) changes or cluster upgrades,
# as these are protected by ArgoCD ignoreDifferences.

set -euo pipefail

echo "=== OCP5 EA Environment Reset ==="
echo ""

# ── MCP Server exercises ──
echo "--- Resetting MCP Server exercise state ---"

# Exercise 5: Scale demo workloads back up
oc scale deployment app-api app-worker -n mcp-demo-production --replicas=2 2>/dev/null || true
echo "  Scaled app-api and app-worker back to 2 replicas"

# Exercise 3: Clean up any test ConfigMaps
oc delete cm test-config -n default 2>/dev/null || true
echo "  Removed test-config ConfigMap"

# Exercise 8: Ensure MCP server args are restored (in case read-only wasn't reverted)
oc patch deployment openshift-mcp-server -n openshift-mcp --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["--config","/etc/mcp/config.toml"]}]' 2>/dev/null || true
echo "  Restored MCP server args"

# ── MCP Gateway exercises ──
echo ""
echo "--- Resetting MCP Gateway exercise state ---"

# Exercise 6/8: Delete RateLimitPolicy so ArgoCD recreates it with original values
oc delete ratelimitpolicy mcp-gateway-ratelimit -n mock-mcp-servers 2>/dev/null || true
echo "  Deleted RateLimitPolicy (ArgoCD will recreate)"

# Exercise 8: Ensure inventory MCP server is scaled up
oc scale deployment inventory-mcp -n mock-mcp-servers --replicas=1 2>/dev/null || true
echo "  Ensured inventory-mcp is scaled to 1"

# ── Agentic Troubleshooting exercises ──
echo ""
echo "--- Resetting Agentic Troubleshooting exercise state ---"

# Restore reporting-service to the intentionally bad image (v1.0.2) so the exercise is repeatable
oc -n payments set image deployment/reporting-service \
  reporting-service=quay.io/afalossi/ts01-reporting-service:v1.0.2 2>/dev/null || true
echo "  Restored reporting-service to v1.0.2 (intentionally bad version)"

# Exercise 4: Reset ApprovalPolicy Analysis back to Manual
oc patch approvalpolicy cluster --type merge \
  -p '{"spec":{"stages":[{"name":"Analysis","approval":"Manual"},{"name":"Execution","approval":"Manual"},{"name":"Verification","approval":"Automatic"}]}}' 2>/dev/null || true
echo "  Reset ApprovalPolicy Analysis to Manual"

# Exercise 4: Revert alerts-adapter-config to disable critical alerts
oc get configmap alerts-adapter-config -n openshift-lightspeed -o json 2>/dev/null \
  | jq '.data["config.yaml"] |= gsub("      +- critical"; "      #  - critical")' \
  | oc apply -f - 2>/dev/null || true
echo "  Reverted alerts-adapter-config (critical alerts disabled)"

# Delete all AgenticRuns and AnalysisResults
oc delete agenticrun --all -n openshift-lightspeed 2>/dev/null || true
oc delete analysisresult --all -n openshift-lightspeed 2>/dev/null || true
echo "  Deleted all AgenticRuns and AnalysisResults"

# Delete Perses Investigation Hub dashboard
TOKEN=$(oc create token perses-sa -n openshift-operators 2>/dev/null) || true
if [ -n "${TOKEN}" ]; then
  oc exec -n openshift-operators perses-0 -- curl -sk -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    https://localhost:8080/api/v1/projects/payments/dashboards/investigation_hub 2>/dev/null || true
fi
echo "  Deleted Investigation Hub Perses dashboard"

# ── Kiali/OSSM exercises ──
echo ""
echo "--- Resetting Kiali/OSSM exercise state ---"

# Exercise 15: Reset reviews VirtualService to 100% v1
oc apply -f - <<'EOF' 2>/dev/null || true
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: reviews
  namespace: bookinfo
  labels:
    eap.kiali.io/test: eap-preconditions
spec:
  hosts:
  - reviews.bookinfo.svc.cluster.local
  http:
  - route:
    - destination:
        host: reviews.bookinfo.svc.cluster.local
        subset: v1
      weight: 100
    - destination:
        host: reviews.bookinfo.svc.cluster.local
        subset: v2
      weight: 0
    - destination:
        host: reviews.bookinfo.svc.cluster.local
        subset: v3
      weight: 0
EOF
echo "  Reset reviews VirtualService to 100% v1"

# Exercise 16: Remove details fault injection
oc delete virtualservice details -n bookinfo --ignore-not-found 2>/dev/null || true
oc delete destinationrule details -n bookinfo --ignore-not-found 2>/dev/null || true
echo "  Removed details fault injection"

# Exercise 17/18: Remove test Gateway
oc delete gateway.networking.istio.io eap-test-gateway -n istio-system --ignore-not-found 2>/dev/null || true
echo "  Removed eap-test-gateway"

# ── ACS exercises ──
echo ""
echo "--- Resetting ACS exercise state ---"

# Before You Begin: Delete ACS ConsoleLink
oc delete consolelink acs-console --ignore-not-found 2>/dev/null || true
echo "  Deleted ACS ConsoleLink"

# Before You Begin: Delete demo app namespaces
for ns in juice-shop log4shell webgoat dvwa emojivoto acs-fam-demo acs-init-container-test; do
  oc delete ns "$ns" --ignore-not-found 2>/dev/null || true
done
echo "  Deleted demo app namespaces"

# Exercise 5: Delete demo SecurityPolicy CRs scoped to acs-init-container-test
oc delete securitypolicy eap-init-test-fixable-important-cve eap-init-test-privileged-container -n acs --ignore-not-found 2>/dev/null || true
echo "  Deleted ACS init-container demo policies"
rm -rf ~/ea5-components 2>/dev/null || true
echo "  Deleted ea5-components clone"

# Exercise 1 (optional): Delete rhel-webserver VM and cloud-init secret
oc delete vm rhel-webserver -n acs-virt --ignore-not-found 2>/dev/null || true
oc delete dv rhel-webserver -n acs-virt --ignore-not-found 2>/dev/null || true
oc delete secret rhel-webserver-cloudinit -n acs-virt --ignore-not-found 2>/dev/null || true
echo "  Deleted rhel-webserver VM resources"

# ── Cleanup AgenticRuns ──
echo ""
echo "--- Cleaning up AgenticRuns ---"

# Delete all AgenticRuns (CVO will recreate update-related ones)
oc delete agenticrun --all -n openshift-lightspeed 2>/dev/null || true
oc delete analysisresult --all -n openshift-lightspeed 2>/dev/null || true
echo "  Deleted all AgenticRuns and AnalysisResults"

echo ""
echo "=== Reset complete ==="
echo ""
