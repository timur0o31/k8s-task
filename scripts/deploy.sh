#!/usr/bin/env bash
mkdir -p k8s-task/kubernetes
touch k8s-task/kubernetes/namespace.yaml
mkdir -p k8s-task/nginx
cat > k8s-task/kubernetes/namespace.yaml << "EOF"
apiVersion: v1
kind: Namespace
metadata:
  name: nginx
EOF
touch k8s-task/kubernetes/deployment.yaml
touch k8s-task/nginx/configmap.yaml
cat > k8s-task/nginx/configmap.yaml << "EOF"
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-files
  namespace: nginx
data:
  index.html: |
    Hello World!
EOF
cat > k8s-task/kubernetes/deployment.yaml << "EOF"
apiVersion: app/v1
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
      volumes:
        - name: html
          configMap:
            name: nginx-files
EOF
kubectl apply -f k8s-task/kubernetes/namespace.yaml
kubectl apply -f k8s-task/nginx/configmap.yaml
kubectl apply -f k8s-task/nginx/deployment.yaml

