#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f monitoring/namespace.yaml
kubectl apply -f monitoring/configmap.yaml
kubectl apply -f monitoring/storage.yaml
kubectl apply -f monitoring/deployment.yaml
kubectl apply -f monitoring/service.yaml

kubectl rollout status deployment/prometheus -n monitoring --timeout=100s

kubectl exec -n monitoring deployment/prometheus -c prometheus -- promtool check config /etc/prometheus/prometheus.yml
