#!/bin/bash
# =============================================================================
# Phase 3 – Exécution de l'application WordCount sur le cluster Spark/K8s
# À exécuter depuis le nœud master ou depuis un pod client dans le cluster
# =============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
SPARK_NAMESPACE="spark"
SPARK_MASTER_SVC="spark-master-service"
SPARK_MASTER_URL="spark://${SPARK_MASTER_SVC}.${SPARK_NAMESPACE}.svc.cluster.local:7077"
WORDCOUNT_SCRIPT="$(dirname $0)/wordcount.py"
INPUT_FILE="${1:-/tmp/sample-text.txt}"
OUTPUT_DIR="${2:-/tmp/wordcount-output}"

echo "=============================================="
echo "  Exécution de WordCount sur Spark/Kubernetes"
echo "  Master : $SPARK_MASTER_URL"
echo "  Entrée : $INPUT_FILE"
echo "  Sortie : $OUTPUT_DIR"
echo "=============================================="

# ── 1. Vérification que Spark est bien déployé ────────────────────────────
echo "[1/5] Vérification du déploiement Spark..."
kubectl get pods -n "$SPARK_NAMESPACE" -l app=spark
echo ""

MASTER_POD=$(kubectl get pod -n "$SPARK_NAMESPACE" \
    -l "app=spark,role=master" \
    -o jsonpath='{.items[0].metadata.name}')

echo "  → Pod Master : $MASTER_POD"

# ── 2. Créer un fichier texte de test si non spécifié ────────────────────
if [ ! -f "$INPUT_FILE" ] && [ "$INPUT_FILE" = "/tmp/sample-text.txt" ]; then
    echo "[2/5] Génération d'un fichier texte de test..."
    cat > /tmp/sample-text.txt <<'TEXT'
Apache Spark is a unified analytics engine for large-scale data processing.
Spark provides high-level APIs in Java Scala Python and R and an optimized engine
that supports general execution graphs. It also supports a rich set of higher-level
tools including Spark SQL for SQL and structured data processing MLlib for machine
learning GraphX for graph processing and Structured Streaming for incremental computation
and stream processing.

Kubernetes is an open-source container orchestration system for automating deployment
scaling and management of containerized applications. Kubernetes clusters consist of
a set of worker machines called nodes that run containerized applications. Every cluster
has at least one worker node. The worker nodes host the Pods that are the components
of the application workload. The control plane manages the worker nodes and the Pods
in the cluster. In production environments the control plane usually runs across multiple
computers and a cluster usually runs multiple nodes providing fault-tolerance and high
availability.

Big Data refers to extremely large data sets that may be analyzed computationally to
reveal patterns trends and associations especially relating to human behavior and
interactions. The term big data often refers to the use of predictive analytics user
behavior analytics or certain other advanced data analytics methods that extract value
from data and seldom to a particular size of data set.
TEXT
    echo "  → Fichier de test créé : /tmp/sample-text.txt"
else
    echo "[2/5] Utilisation du fichier : $INPUT_FILE"
fi

# ── 3. Copier le fichier texte dans le pod Spark Master ───────────────────
echo "[3/5] Copie du fichier dans le pod master..."
kubectl cp "$INPUT_FILE" "$SPARK_NAMESPACE/$MASTER_POD:/tmp/input.txt"
kubectl cp "$WORDCOUNT_SCRIPT" "$SPARK_NAMESPACE/$MASTER_POD:/tmp/wordcount.py"

# ── 4. Lancer spark-submit depuis le pod master ───────────────────────────
echo "[4/5] Lancement de spark-submit..."
echo ""

kubectl exec -n "$SPARK_NAMESPACE" "$MASTER_POD" -- \
    spark-submit \
        --master "spark://spark-master-service:7077" \
        --deploy-mode client \
        --name "WordCount-Kubernetes-2026" \
        --conf "spark.ui.port=4040" \
        --conf "spark.executor.memory=512m" \
        --conf "spark.executor.cores=1" \
        --conf "spark.driver.memory=512m" \
        --conf "spark.metrics.conf.*.sink.prometheusServlet.class=org.apache.spark.metrics.sink.PrometheusServlet" \
        --conf "spark.metrics.conf.*.sink.prometheusServlet.path=/metrics/prometheus" \
        /tmp/wordcount.py \
        /tmp/input.txt \
        /tmp/wordcount-output

# ── 5. Récupérer les résultats ────────────────────────────────────────────
echo "[5/5] Récupération des résultats..."
rm -rf "$OUTPUT_DIR"
kubectl cp "$SPARK_NAMESPACE/$MASTER_POD:/tmp/wordcount-output" "$OUTPUT_DIR" 2>/dev/null || true

if ls "$OUTPUT_DIR"/part-* &>/dev/null 2>&1; then
    echo ""
    echo "────────────────────────────────────────────"
    echo "  Résultats (extrait des 30 premiers mots) :"
    echo "────────────────────────────────────────────"
    cat "$OUTPUT_DIR"/part-* 2>/dev/null | head -30
fi

cat <<EOF

============================================
  WordCount exécuté avec succès !
============================================
  Interfaces disponibles :
    Spark Master UI  → http://<MASTER_IP>:30080
    Prometheus       → http://<MASTER_IP>:30090
    Grafana          → http://<MASTER_IP>:30030
                       Login : admin / admin123

  Métriques Spark dans Grafana :
    Dashboard → "Kubernetes & Spark" → "Spark Applications"
    Métriques clés :
      • spark_driver_jvm_memory_heap_used
      • spark_driver_executor_runTime_total
      • container_cpu_usage_seconds_total
      • container_memory_working_set_bytes
============================================
EOF
