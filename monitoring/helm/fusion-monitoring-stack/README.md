# Fusion Monitoring-Stack Helm Chart

## Prerequisites

Make sure you have Helm installed: <https://helm.sh/docs/using_helm/#installing-helm>

## Deploy Grafana, Prometheus Loki and Promtail to your Fusion cluster

### Deploy with default config

```bash
helm upgrade --install monitoring .
```

### Deploy in a custom namespace

```bash
helm upgrade --install monitoring --namespace=infrastructure .
```

### Deploy with custom config

```bash
helm upgrade --install . grafana/loki-stack --set "key1=val1,key2=val2,..."
```

## Deploy Grafana to your cluster

To get the admin password for the Grafana pod, run the following command:

```bash
kubectl get secret --namespace <YOUR-NAMESPACE> loki-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

To access the Grafana UI, run the following command:

```bash
kubectl port-forward --namespace <YOUR-NAMESPACE> service/monitoring-grafana 3000:80
```

Navigate to <http://localhost:3000> and login with `admin` and the password output above.
