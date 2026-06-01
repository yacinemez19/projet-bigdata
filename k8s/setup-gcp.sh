#!/bin/bash
# =============================================================================
# Phase 1 – Création du cluster de VMs sur GCP
# Infrastructure pour le Cloud et le Big Data – Projet 2026
# =============================================================================
# Prérequis : avoir installé et configuré gcloud CLI
#   https://cloud.google.com/sdk/docs/install
#   gcloud init
#   gcloud auth login
# =============================================================================

set -euo pipefail

# ── Variables à adapter ───────────────────────────────────────────────────────
PROJECT_ID="bigdata-projet-2026"      # Remplace par ton project ID GCP
REGION="europe-west9"                  # Paris
ZONE="europe-west9-a"
MACHINE_TYPE="e2-standard-2"           # 2 vCPU, 8 GB RAM (free tier eligible)
IMAGE_FAMILY="ubuntu-2004-lts"
IMAGE_PROJECT="ubuntu-os-cloud"
DISK_SIZE="50GB"
NETWORK="k8s-network"
SUBNET="k8s-subnet"
MASTER_NAME="k8s-master"
WORKER_NAME="k8s-worker-1"
# ─────────────────────────────────────────────────────────────────────────────

echo "=============================================="
echo "  Déploiement Kubernetes sur GCP"
echo "  Projet : $PROJECT_ID | Zone : $ZONE"
echo "=============================================="

# 1. Définir le projet actif
gcloud config set project "$PROJECT_ID"
gcloud config set compute/zone "$ZONE"

# 2. Activer les APIs nécessaires
echo "[1/6] Activation des APIs GCP..."
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com

# 3. Créer le réseau VPC dédié
echo "[2/6] Création du réseau VPC..."
gcloud compute networks create "$NETWORK" \
    --subnet-mode=custom \
    --bgp-routing-mode=regional 2>/dev/null || echo "  → Réseau déjà existant, on continue."

gcloud compute networks subnets create "$SUBNET" \
    --network="$NETWORK" \
    --region="$REGION" \
    --range=10.0.0.0/24 2>/dev/null || echo "  → Sous-réseau déjà existant, on continue."

# 4. Règles de pare-feu
echo "[3/6] Configuration du pare-feu..."
# Autoriser SSH, API Kubernetes, Prometheus, Grafana, Spark UI
gcloud compute firewall-rules create k8s-allow-internal \
    --network="$NETWORK" \
    --allow=tcp,udp,icmp \
    --source-ranges=10.0.0.0/24 2>/dev/null || true

gcloud compute firewall-rules create k8s-allow-external \
    --network="$NETWORK" \
    --allow=tcp:22,tcp:6443,tcp:8080,tcp:3000,tcp:9090,tcp:8888,tcp:4040,tcp:30000-32767 \
    --source-ranges=0.0.0.0/0 2>/dev/null || true

# 5. Créer la VM Master
echo "[4/6] Création de la VM Master ($MASTER_NAME)..."
gcloud compute instances create "$MASTER_NAME" \
    --machine-type="$MACHINE_TYPE" \
    --image-family="$IMAGE_FAMILY" \
    --image-project="$IMAGE_PROJECT" \
    --boot-disk-size="$DISK_SIZE" \
    --boot-disk-type=pd-ssd \
    --network="$NETWORK" \
    --subnet="$SUBNET" \
    --tags=k8s-master \
    --metadata=startup-script='#!/bin/bash
        echo "root:toto" | chpasswd
        sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
        sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
        systemctl restart sshd' \
    --zone="$ZONE"

# 6. Créer la VM Worker
echo "[5/6] Création de la VM Worker ($WORKER_NAME)..."
gcloud compute instances create "$WORKER_NAME" \
    --machine-type="$MACHINE_TYPE" \
    --image-family="$IMAGE_FAMILY" \
    --image-project="$IMAGE_PROJECT" \
    --boot-disk-size="$DISK_SIZE" \
    --boot-disk-type=pd-ssd \
    --network="$NETWORK" \
    --subnet="$SUBNET" \
    --tags=k8s-worker \
    --metadata=startup-script='#!/bin/bash
        echo "root:toto" | chpasswd
        sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
        sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
        systemctl restart sshd' \
    --zone="$ZONE"

# 7. Récupérer les IPs
echo "[6/6] Récupération des adresses IP..."
MASTER_EXTERNAL_IP=$(gcloud compute instances describe "$MASTER_NAME" \
    --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
MASTER_INTERNAL_IP=$(gcloud compute instances describe "$MASTER_NAME" \
    --zone="$ZONE" --format='get(networkInterfaces[0].networkIP)')
WORKER_EXTERNAL_IP=$(gcloud compute instances describe "$WORKER_NAME" \
    --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
WORKER_INTERNAL_IP=$(gcloud compute instances describe "$WORKER_NAME" \
    --zone="$ZONE" --format='get(networkInterfaces[0].networkIP)')

cat <<EOF

============================================
  VMs GCP créées avec succès !
============================================
  Master  : $MASTER_NAME
    IP externe : $MASTER_EXTERNAL_IP
    IP interne : $MASTER_INTERNAL_IP

  Worker  : $WORKER_NAME
    IP externe : $WORKER_EXTERNAL_IP
    IP interne : $WORKER_INTERNAL_IP

  Connexion SSH :
    ssh ubuntu@$MASTER_EXTERNAL_IP   (master)
    ssh ubuntu@$WORKER_EXTERNAL_IP   (worker)

  Prochaine étape :
    Copier setup-master.sh sur le master, puis l'exécuter :
    scp setup-master.sh ubuntu@$MASTER_EXTERNAL_IP:~
    scp setup-worker.sh ubuntu@$WORKER_EXTERNAL_IP:~

    Sur le MASTER :  sudo bash setup-master.sh $MASTER_INTERNAL_IP $WORKER_INTERNAL_IP
    Sur le WORKER :  sudo bash setup-worker.sh <join_command>
============================================
EOF

# Sauvegarder les IPs pour les scripts suivants
cat > /tmp/gcp-ips.env <<ENV
MASTER_EXTERNAL_IP=$MASTER_EXTERNAL_IP
MASTER_INTERNAL_IP=$MASTER_INTERNAL_IP
WORKER_EXTERNAL_IP=$WORKER_EXTERNAL_IP
WORKER_INTERNAL_IP=$WORKER_INTERNAL_IP
ENV
echo "  IPs sauvegardées dans /tmp/gcp-ips.env"
