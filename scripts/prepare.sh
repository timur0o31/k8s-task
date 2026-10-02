#!/usr/bin/env bash

set -euo pipefail
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
sudo apt-get install -y containerd
sudo systemctl enable --now containerd
sudo mkdir -p /etc/containerd
sudo tee /etc/containerd/config.toml >/dev/null << "EOF"
version=3
[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc.options]
  SystemdCgroup = true
EOF
sudo systemctl restart containerd
sudo tee /etc/modules-load.d/k8s.conf >/dev/null << "EOF"
br_netfilter
EOF
sudo modprobe br_netfilter
sudo tee /etc/sysctl.d/k8s.conf >/dev/null << "EOF"
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl -p /etc/sysctl.d/k8s.conf
sudo kubeadm init \
  --kubernetes-version=v1.37.1 \
  --apiserver-advertise-address=10.0.2.15 \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://github.com/flannel-io/flannel/releases/download/v0.28.9/kube-flannel.yml
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
