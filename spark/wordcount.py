#!/usr/bin/env python3
"""
WordCount – Application Spark de référence
==========================================
Compte le nombre d'occurrences de chaque mot dans un fichier texte.
Adapté pour s'exécuter sur un cluster Spark déployé dans Kubernetes.

Usage :
    spark-submit \\
        --master spark://spark-master-service:7077 \\
        --deploy-mode client \\
        wordcount.py <chemin_fichier_entree> [chemin_sortie]

Exemple :
    spark-submit --master spark://localhost:7077 wordcount.py hdfs:///data/input.txt /data/output
"""

import sys
import time
from pyspark import SparkContext, SparkConf
from pyspark.sql import SparkSession


def word_count_rdd(sc: SparkContext, input_path: str, output_path: str | None) -> dict:
    """
    Implémentation WordCount via l'API RDD (bas niveau).
    Reflète l'approche classique MapReduce.
    """
    # Lecture du fichier → chaque ligne = un élément du RDD
    text_rdd = sc.textFile(input_path)

    # MAP : découper chaque ligne en mots, émettre (mot, 1)
    words_rdd = (
        text_rdd
        .flatMap(lambda line: line.lower().split())           # tokenisation
        .filter(lambda word: word.isalpha())                  # supprimer ponctuation
        .map(lambda word: (word, 1))                          # (mot, 1)
    )

    # REDUCE : sommer les occurrences par clé
    counts_rdd = words_rdd.reduceByKey(lambda a, b: a + b)

    # Tri décroissant pour les top-mots
    sorted_counts = counts_rdd.sortBy(lambda x: x[1], ascending=False)

    # Sauvegarde sur HDFS ou système de fichiers local
    if output_path:
        sorted_counts.saveAsTextFile(output_path)
        print(f"[WordCount] Résultats sauvegardés dans : {output_path}")

    # Retourner les 20 mots les plus fréquents pour affichage
    return dict(sorted_counts.take(20))


def word_count_dataframe(spark: SparkSession, input_path: str) -> None:
    """
    Implémentation WordCount via l'API DataFrame/SQL (haut niveau).
    Plus optimisée grâce au Catalyst optimizer.
    """
    from pyspark.sql import functions as F

    df = spark.read.text(input_path)

    result = (
        df
        .select(F.explode(F.split(F.lower(F.col("value")), r"\W+")).alias("word"))
        .filter(F.col("word") != "")
        .filter(F.col("word").rlike("^[a-z]+$"))
        .groupBy("word")
        .agg(F.count("*").alias("count"))
        .orderBy(F.col("count").desc())
    )

    print("\n[WordCount DataFrame] Top 20 mots les plus fréquents :")
    result.show(20, truncate=False)


def main():
    # ── Arguments ───────────────────────────────────────────────────────────
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    input_path  = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else None

    # ── Configuration Spark ─────────────────────────────────────────────────
    conf = (
        SparkConf()
        .setAppName("WordCount-Kubernetes")
        # Métriques Prometheus
        .set("spark.metrics.conf.*.sink.prometheusServlet.class",
             "org.apache.spark.metrics.sink.PrometheusServlet")
        .set("spark.metrics.conf.*.sink.prometheusServlet.path", "/metrics/prometheus")
        .set("spark.metrics.conf.master.sink.prometheusServlet.path", "/metrics/master/prometheus")
        .set("spark.metrics.conf.applications.sink.prometheusServlet.path",
             "/metrics/applications/prometheus")
        # UI
        .set("spark.ui.port", "4040")
        .set("spark.ui.enabled", "true")
    )

    spark = SparkSession.builder.config(conf=conf).getOrCreate()
    sc    = spark.sparkContext
    sc.setLogLevel("WARN")

    print("=" * 60)
    print(f"  WordCount – Cluster Spark sur Kubernetes")
    print(f"  Fichier d'entrée : {input_path}")
    print(f"  Sortie           : {output_path or '(affichage uniquement)'}")
    print(f"  Spark version    : {spark.version}")
    print(f"  Master           : {sc.master}")
    print("=" * 60)

    start = time.time()

    # ── Exécution RDD ────────────────────────────────────────────────────────
    print("\n[1/2] Exécution via l'API RDD...")
    top_words = word_count_rdd(sc, input_path, output_path)

    print("\nTop 20 mots les plus fréquents (RDD) :")
    print(f"{'Mot':<20} {'Occurrences':>12}")
    print("-" * 33)
    for word, count in top_words.items():
        print(f"{word:<20} {count:>12,}")

    # ── Exécution DataFrame ──────────────────────────────────────────────────
    print("\n[2/2] Exécution via l'API DataFrame (Catalyst optimizer)...")
    word_count_dataframe(spark, input_path)

    elapsed = time.time() - start
    print(f"\n✓ WordCount terminé en {elapsed:.2f} secondes")
    print(f"  → Consulte l'interface Spark UI : http://<master-IP>:30080")
    print(f"  → Métriques Prometheus          : http://<master-IP>:30090")
    print(f"  → Tableaux de bord Grafana      : http://<master-IP>:30030")

    spark.stop()


if __name__ == "__main__":
    main()
