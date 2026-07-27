#!/usr/bin/env bash
set -euo pipefail

namespace="default"

echo "[INFO] Checking Istio control plane pods..."
kubectl get pods -n istio-system

for pod in $(kubectl get pods -n istio-system -o jsonpath='{.items[*].metadata.name}'); do
  pod_ready="$(
    kubectl get pod -n istio-system "${pod}" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  )"

  if [ "${pod_ready}" != "True" ]; then
    echo "[FAIL] Istio control plane pod ${pod} is not Ready"
    exit 1
  fi
done

echo "[INFO] Checking namespace label..."
label_value="$(kubectl get namespace "${namespace}" -o jsonpath='{.metadata.labels.istio-injection}')"
if [ "${label_value}" != "enabled" ]; then
  echo "[FAIL] Namespace ${namespace} must have istio-injection=enabled, got ${label_value:-<empty>}"
  exit 1
fi

echo "[INFO] Checking booking-service pods for istio-proxy..."
booking_pods="$(kubectl get pods -n "${namespace}" -l app=booking-service -o jsonpath='{.items[*].metadata.name}')"
if [ -z "${booking_pods}" ]; then
  echo "[FAIL] No booking-service pods found in namespace ${namespace}"
  exit 1
fi

for pod in ${booking_pods}; do
  containers="$(kubectl get pod -n "${namespace}" "${pod}" -o jsonpath='{.spec.containers[*].name}')"
  init_containers="$(kubectl get pod -n "${namespace}" "${pod}" -o jsonpath='{.spec.initContainers[*].name}')"
  echo "  ${pod}: containers=[${containers}] initContainers=[${init_containers}]"
  if ! printf '%s\n%s\n' "${containers}" "${init_containers}" | grep -qw istio-proxy; then
    echo "[FAIL] Pod ${pod} does not contain istio-proxy in containers or initContainers"
    exit 1
  fi
done

echo "[INFO] Checking istio-client pod for istio-proxy..."
client_containers="$(kubectl get pod -n "${namespace}" istio-client -o jsonpath='{.spec.containers[*].name}')"
client_init_containers="$(kubectl get pod -n "${namespace}" istio-client -o jsonpath='{.spec.initContainers[*].name}')"
echo "  istio-client: containers=[${client_containers}] initContainers=[${client_init_containers}]"
if ! printf '%s\n%s\n' "${client_containers}" "${client_init_containers}" | grep -qw istio-proxy; then
  echo "[FAIL] Pod istio-client does not contain istio-proxy in containers or initContainers"
  exit 1
fi

echo "[PASS] Istio injection is active for booking-service and istio-client"
