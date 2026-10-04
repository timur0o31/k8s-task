#!/usr/bin/env bash
set -eou pipefail
mkdir -p kubernetes nginx
touch kubernetes/namespace.yaml
cat > kubernetes/namespace.yaml << "EOF"
apiVersion: v1
kind: Namespace
metadata:
  name: nginx
EOF

touch nginx/deployment.yaml
cat > nginx/configmap.yaml << "EOF"
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-files
  namespace: nginx
data:
  index.html: |
    Hello world!
  default.conf: |
    server {
      listen 80;
      server_name _;
      root /usr/share/nginx/html;
      index index.html;
      access_log /dev/stdout combined;
      error_log /dev/stderr warn;
      location / {
      }
    }
EOF
cat > nginx/deployment.yaml << "EOF"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.30.5
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true
            - name: config
              mountPath: /etc/nginx/conf.d
              readOnly: true
      volumes:
        - name: html
          configMap:
            name: nginx-files
            items:
              - key: index.html
                path: index.html
        - name: config
          configMap:
            name: nginx-files
            items:
              - key: default.conf
                path: default.conf
EOF
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f nginx/configmap.yaml
kubectl apply -f nginx/deployment.yaml
touch nginx/service.yaml
cat > nginx/service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: nginx
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF
kubectl apply -f nginx/service.yaml
kubectl rollout status deployment/nginx-deployment -n nginx --timeout=180s
