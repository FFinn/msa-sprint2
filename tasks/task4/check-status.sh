#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-default}"

echo "Checking booking-service deployment..."
kubectl get pods -n "${namespace}" -l app=booking-service

echo
echo "Checking service..."
kubectl get svc -n "${namespace}" booking-service

echo
echo "Port-forward to test service locally:"
echo "kubectl port-forward -n ${namespace} svc/booking-service 8080:80"
echo "Then:"
echo "curl http://localhost:8080/ping"
