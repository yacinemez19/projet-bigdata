#!/bin/bash
# =============================================================================
# Phase 1 – Installation et join du nœud WORKER Kubernetes
# À exécuter en tant que root sur la VM GCP worker
# Usage : sudo bash setup-worker.sh <MASTER_IP> "<join_command_complet>"
#   OU copier directement /root/worker-join.sh depuis le master
# =============================================================================

set -euo pipefail

MASTER_IP="${1:?Usage: $0 <MASTER_IP>}"
# Le reste des arguments = la commande kubeadm join
shift
JOIN_ARGS="$@"

echo "=============================================="
echo "  Configuration du nœud Worker Kubernetes"
echo "  Master IP : $MASTER_IP"
echo "=============================================="

# ── 1. Mise à jour système ─────────────────────────────────────────────────
echo "[1/7] Mise à jour du système..."
apt-get update -y && apt-get upgrade -y

# ── 2. Hostname et /etc/hosts ─────────────────────────────────────────────
echo "[2/7] Configuration hostname..."
hostnamectl set-hostname worker
echo "$MASTER_IP   master" >> /etc/hosts

# ── 3. Désactiver le swap ─────────────────────────────────────────────────
echo "[3/7] Désactivation du swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# ── 4. Modules noyau ─────────────────────────────────────────────────────
echo "[4/7] Chargement des modules noyau..."
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

# ── 5. Installation de containerd ─────────────────────────────────────────
echo "[5/7] Installation de containerd..."
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

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# ── 6. Installation de kubeadm, kubelet, kubectl ─────────────────────────
echo "[6/7] Installation des outils Kubernetes..."
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

# ── 7. Rejoindre le cluster ───────────────────────────────────────────────
echo "[7/7] Jointure au cluster Kubernetes..."
if [ -n "$JOIN_ARGS" ]; then
    kubeadm join $JOIN_ARGS
else
    echo "  ATTENTION : Aucune commande join fournie."
    echo "  Récupère la commande depuis le master :"
    echo "    Sur le master : kubeadm token create --print-join-command"
    echo "  puis relance ce script avec la commande complète."
    exit 1
fi

cat <<DONE

============================================
  Worker jointé au cluster avec succès !
============================================
  Vérification depuis le MASTER :
    kubectl get nodes
    → Tu devrais voir 'worker' avec le statut 'Ready'
============================================
DONE
