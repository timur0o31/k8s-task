#!/usr/bin/env bash
set -euo pipefail
# Запускать в Ubuntu из корня репозитория k8s-task.
NGF_VERSION="2.7.2"
mkdir -p gateway
curl -fL \
  --connect-timeout 10 \
  --max-time 180 \
  --retry 3 \
  --retry-delay 2 \
  -o gateway/gateway-api-crds.yaml \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml"

kubectl apply --server-side -f gateway/gateway-api-crds.yaml
kubectl apply --server-side -f "https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v${NGF_VERSION}/deploy/crds.yaml"

kubectl wait --for=condition=Established --timeout=120s \
  crd/gatewayclasses.gateway.networking.k8s.io \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io \
  crd/nginxgateways.gateway.nginx.org \
  crd/nginxproxies.gateway.nginx.org

kubectl apply -f "https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v${NGF_VERSION}/deploy/nodeport/deploy.yaml"

mkdir -p gateway
if [[ ! -f gateway/gateway.yaml ]]; then
  cat > gateway/gateway.yaml <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
  namespace: nginx
spec:
  gatewayClassName: nginx
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx-route
  namespace: nginx
spec:
  parentRefs:
    - name: web-gateway
      sectionName: http
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: nginx-service
          port: 80
EOF
fi

kubectl apply -f gateway/gateway.yaml

kubectl wait gateway/web-gateway -n nginx --for=condition=Programmed --timeout=100s
kubectl rollout status deployment/web-gateway-nginx  -n nginx --timeout=100s

NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
GATEWAY_PORT="$(kubectl get service web-gateway-nginx -n nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')"
echo "Проверяем http://${NODE_IP}:${GATEWAY_PORT}/"
curl -fsS -i --max-time 10 "http://${NODE_IP}:${GATEWAY_PORT}/?check=gateway"
