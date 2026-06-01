#!/bin/bash
# =============================================================================
# Phase 1 – Installation et initialisation du nœud MASTER Kubernetes
# À exécuter en tant que root sur la VM GCP master
# Usage : sudo bash setup-master.sh <MASTER_INTERNAL_IP> <WORKER_INTERNAL_IP>
# =============================================================================

set -euo pipefail

MASTER_IP="${1:?Usage: $0 <MASTER_IP> <WORKER_IP>}"
WORKER_IP="${2:?Usage: $0 <MASTER_IP> <WORKER_IP>}"
POD_CIDR="10.244.0.0/16"   # Réseau Flannel

echo "=============================================="
echo "  Configuration du nœud Master Kubernetes"
echo "  Master IP : $MASTER_IP | Worker IP : $WORKER_IP"
echo "=============================================="

# ── 1. Mise à jour système ─────────────────────────────────────────────────
echo "[1/9] Mise à jour du système..."
apt-get update -y && apt-get upgrade -y

# ── 2. Hostname et /etc/hosts ─────────────────────────────────────────────
echo "[2/9] Configuration hostname & /etc/hosts..."
hostnamectl set-hostname master
cat >> /etc/hosts <<HOSTS
$MASTER_IP   master
$WORKER_IP   worker
HOSTS

# ── 3. Désactiver le swap (obligatoire pour kubelet) ──────────────────────
echo "[3/9] Désactivation du swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# ── 4. Modules noyau nécessaires ──────────────────────────────────────────
echo "[4/9] Chargement des modules noyau..."
modprobe br_netfilter
modprobe overlay

cat > /etc/modules-load.d/k8s.conf <<EOF
br_netfilter
overlay
EOF

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# ── 5. Installation de containerd (runtime recommandé) ───────────────────
echo "[5/9] Installation de containerd..."
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y containerd.io

# Configurer containerd avec le driver systemd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# ── 6. Installation de kubeadm, kubelet, kubectl ─────────────────────────
echo "[6/9] Installation des outils Kubernetes..."
apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' \
    | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

# ── 7. Initialisation du cluster ──────────────────────────────────────────
echo "[7/9] Initialisation du cluster Kubernetes..."
kubeadm init \
    --pod-network-cidr="$POD_CIDR" \
    --apiserver-advertise-address="$MASTER_IP" \
    --kubernetes-version=1.28.0 \
    | tee /root/kubeadm-init.log

# Configurer kubectl pour l'utilisateur root et ubuntu
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

if id "ubuntu" &>/dev/null; then
    mkdir -p /home/ubuntu/.kube
    cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    chown ubuntu:ubuntu /home/ubuntu/.kube/config
fi

# ── 8. Déploiement du CNI Flannel ────────────────────────────────────────
echo "[8/9] Déploiement du plugin réseau Flannel..."
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "  En attente que le master passe en Ready (30s)..."
sleep 30
kubectl get nodes
kubectl get pods --all-namespaces

# ── 9. Extraire la commande join ──────────────────────────────────────────
echo "[9/9] Génération de la commande join pour le worker..."
JOIN_CMD=$(kubeadm token create --print-join-command)

cat > /root/worker-join.sh <<JOINSCRIPT
#!/bin/bash
# Exécuter ce script sur le nœud WORKER en tant que root
$JOIN_CMD
JOINSCRIPT
chmod +x /root/worker-join.sh

cat <<DONE

============================================
  Master Kubernetes initialisé avec succès !
============================================
  Commande à copier et exécuter sur le WORKER :
  --------------------------------------------------
  $JOIN_CMD
  --------------------------------------------------

  La commande est aussi sauvegardée dans /root/worker-join.sh
  Copie-la sur le worker :
    scp /root/worker-join.sh ubuntu@WORKER_IP:~
    Puis sur le worker : sudo bash worker-join.sh
============================================
DONE
