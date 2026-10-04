#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f logging/namespace.yaml
kubectl apply -f logging/configmap.yaml
kubectl apply -f logging/daemonset.yaml

kubectl rollout status daemonset/filebeat -n logging --timeout=180s
