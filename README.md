# Projet Infrastructure Cloud & Big Data
## Kubernetes + Prometheus + Spark sur GCP

### Structure du projet
```
projet-bigdata/
├── k8s/                    # Phase 1 – Déploiement Kubernetes sur GCP
│   ├── setup-gcp.sh        # Script de création des VMs GCP
│   ├── setup-master.sh     # Installation & init du nœud master
│   └── setup-worker.sh     # Installation & join du nœud worker
│
├── monitoring/             # Phase 2 – Prometheus + Grafana
│   ├── prometheus-namespace.yaml
│   ├── prometheus-config.yaml
│   ├── prometheus-deployment.yaml
│   ├── prometheus-service.yaml
│   ├── grafana-deployment.yaml
│   └── grafana-service.yaml
│
├── spark/                  # Phase 3 – Spark sur Kubernetes + WordCount
│   ├── spark-master-deployment.yaml
│   ├── spark-master-service.yaml
│   ├── spark-worker-deployment.yaml
│   ├── wordcount.py
│   └── run-wordcount.sh
│
└── rapport/                # Phase 4 – Rapport LaTeX
    └── rapport.tex
```

### Ordre d'exécution
1. `bash k8s/setup-gcp.sh`         → Crée les VMs sur GCP
2. `bash k8s/setup-master.sh`      → Sur la VM master
3. `bash k8s/setup-worker.sh`      → Sur la VM worker
4. `kubectl apply -f monitoring/`  → Déploie Prometheus + Grafana
5. `kubectl apply -f spark/`       → Déploie Spark
6. `bash spark/run-wordcount.sh`   → Lance le WordCount
