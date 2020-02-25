#!/bin/bash

# Platform agnostic script used by the other setup_f5_*.sh scripts to perform general K8s and Helm commands to install Fusion.
# This script assumes kubectl is pointing to the right cluster and that the user is already authenticated.

CHART_VERSION="5.0.3-3"
PROVIDER="k8s"
INGRESS_HOSTNAME=""
PROMETHEUS="install"
SCRIPT_CMD="$0"
CLUSTER_NAME=
NAMESPACE=default
UPGRADE=0
PURGE=0
FORCE=0
CUSTOM_MY_VALUES=()
MY_VALUES=()
DRY_RUN=""
SOLR_DISK_GB=50
NODE_POOL=""

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on an existing Kubernetes cluster"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c            Name of the K8s cluster (required)\n"
  echo -e "  -r            Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n            Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  --provider    Lowercase label for your K8s platform provider, e.g. eks, aks, gke; defaults to 'k8s'\n"
  echo -e "  --node-pool   Node pool label to assign pods to specific nodes, this option is only useful for existing clusters"
  echo -e "                where you defined a custom node pool, wrap the arg in double-quotes\n"
  echo -e "  --ingress     Ingress hostname\n"
  echo -e "  --prometheus  Enable Prometheus and Grafana for monitoring Fusion services, pass one of: install, provided, none;"
  echo -e "                defaults to 'install' which installs Prometheus and Grafana from the stable Helm repo,"
  echo -e "                'provided' enables pod annotations on Fusion services to work with Prometheus but does not install anything\n"
  echo -e "  --version     Fusion Helm Chart version; defaults to the latest release from Lucidworks, such as ${CHART_VERSION}\n"
  echo -e "  --values      Custom values file containing config overrides; defaults to gke_<cluster>_<namespace>_fusion_values.yaml"
  echo -e "                (can be specified multiple times to add additional yaml files, see example-values/*.yaml)\n"
  echo -e "  --upgrade     Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --dry-run     Perform a dry-run of the upgrade to see what would change\n"
  echo -e "  --purge       Uninstall and purge all Fusion objects from the specified namespace and cluster."
  echo -e "                Be careful! This operation cannot be undone.\n"
  echo -e "  --force       Force upgrade or purge a deployment if your account is not the value 'owner' label on the namespace\n"
}

if [ $# -gt 0 ]; then
  while true; do
    case "$1" in
        -c)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -c parameter!"
              exit 1
            fi
            CLUSTER_NAME="$2"
            shift 2
        ;;
        -n)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -n parameter!"
              exit 1
            fi
            NAMESPACE="$2"
            shift 2
        ;;
        -r)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -r parameter!"
              exit 1
            fi
            RELEASE="$2"
            shift 2
        ;;
        --provider)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --provider parameter!"
              exit 1
            fi
            PROVIDER="$2"
            shift 2
        ;;
        --ingress)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --ingress parameter!"
              exit 1
            fi
            INGRESS_HOSTNAME="$2"
            shift 2
        ;;
        --prometheus)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --prometheus parameter!"
              exit 1
            fi
            PROMETHEUS="$2"
            shift 2
        ;;
        --node-pool)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --node-pool parameter!"
              exit 1
            fi
            NODE_POOL="$2"
            shift 2
        ;;
        --version)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --version parameter!"
              exit 1
            fi
            CHART_VERSION="$2"
            shift 2
        ;;
        --values)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --values parameter!"
              exit 1
            fi
            CUSTOM_MY_VALUES+=("$2")
            shift 2
        ;;
        --upgrade)
            UPGRADE=1
            shift 1
        ;;
        --dry-run)
            DRY_RUN="--dry-run"
            shift 1
        ;;
        --purge)
            PURGE=1
            shift 1
        ;;
        --force)
            FORCE=1
            shift 1
        ;;
        -help|-usage|--help|--usage)
            print_usage "$SCRIPT_CMD"
            exit 0
        ;;
        --)
            shift
            break
        ;;
        *)
            if [ "$1" != "" ]; then
              print_usage "$SCRIPT_CMD" "Unrecognized or misplaced argument: $1!"
              exit 1
            else
              break # out-of-args, stop looping
            fi
        ;;
    esac
  done
fi

if [ "$CLUSTER_NAME" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Kubernetes cluster name using: -c <cluster>"
  exit 1
fi

valid="0-9a-zA-Z_\-"
if [[ $NAMESPACE =~ [^$valid] ]]; then
  echo -e "\nERROR: Namespace $NAMESPACE must only contain 0-9, a-z, A-Z, underscore or dash!\n"
  exit 1
fi

if [ -z ${RELEASE+x} ]; then
  # keep "f5" as the default for legacy purposes when using the default namespace
  if [ "${NAMESPACE}" == "default" ]; then
    RELEASE="f5"
  else
    RELEASE="$NAMESPACE"
  fi
fi

if [[ $RELEASE =~ [^$valid] ]]; then
  echo -e "\nERROR: Release $RELEASE must only contain 0-9, a-z, A-Z, underscore or dash!\n"
  exit 1
fi

DEFAULT_MY_VALUES="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"

hash kubectl
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install kubectl before proceeding with this script!"
  exit 1
fi

hash helm
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install helm before proceeding with this script! See: https://helm.sh/docs/using_helm/#quickstart"
  exit 1
fi

current=$(kubectl config current-context)
echo -e "\nUsing kubeconfig: $current\n"

is_helm_v3=$(helm version --short | grep v3)

if [ "${is_helm_v3}" == "" ]; then
  # see if Tiller is deployed ...
  kubectl rollout status deployment/tiller-deploy --timeout=10s -n kube-system > /dev/null 2>&1
  rollout_status=$?
  if [ $rollout_status != 0 ]; then
    echo -e "\nSetting up Helm Tiller ..."
    kubectl create serviceaccount --namespace kube-system tiller
    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    helm init --service-account tiller --wait
    helm version
  fi
else
  echo -e "Using Helm v3 ($is_helm_v3)"
fi

if [ "${UPGRADE}" == "1" ]; then

  kubectl get namespace "${NAMESPACE}"
  namespace_exists=$?
  if [ "$namespace_exists" != "0" ]; then
    exit 1
  fi

  # Check if the owner label on the namespace is the same as we are, so we cannot
  # accidentally upgrade a release from someone elses namespace
  namespace_owner=$(kubectl get namespace "${NAMESPACE}" -o 'jsonpath={.metadata.labels.owner}')
  if [ "${namespace_owner}" != "${OWNER_LABEL}" ] && [ "${FORCE}" != "1" ]; then
    echo -e "Namespace "${NAMESPACE}" is owned by: ${namespace_owner}, by we are: "${OWNER_LABEL}" please provide the --force parameter if you are sure you wish to upgrade this namespace"
    exit 1
  fi
elif [ "$PURGE" == "1" ]; then

  kubectl get namespace "${NAMESPACE}"
  namespace_exists=$?
  if [ "$namespace_exists" != "0" ]; then
    exit 1
  fi

  # Check if the owner label on the namespace is the same as we are, so we cannot
  # accidentally purge someone elses release
  namespace_owner=$(kubectl get namespace "${NAMESPACE}" -o 'jsonpath={.metadata.labels.owner}')
  if [ "${namespace_owner}" != "${OWNER_LABEL}" ] && [ "${FORCE}" != "1" ]; then
    echo -e "Namespace "${NAMESPACE}" is owned by: ${namespace_owner}, by we are: "${OWNER_LABEL}" please provide the --force parameter if you are sure you wish to purge this namespace"
    exit 1
  fi

  confirm="Y"
  read -p "Are you sure you want to purge the ${RELEASE} release from the ${NAMESPACE} namespace in: $current? This operation cannot be undone! Y/n " confirm
  if [ "$confirm" == "" ] || [ "$confirm" == "Y" ] || [ "$confirm" == "y" ]; then

    if [ "$is_helm_v3" != "" ]; then
      helm delete ${RELEASE} --namespace ${NAMESPACE}
      helm delete ${RELEASE}-prom --namespace ${NAMESPACE}
      helm delete ${RELEASE}-graf --namespace ${NAMESPACE}
    else
      helm del --purge ${RELEASE}
    fi
    kubectl delete deployments -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete job ${RELEASE}-api-gateway --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=1s
    kubectl delete svc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=2s
    kubectl delete pvc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l release=${RELEASE} --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l app.kubernetes.io/instance=${RELEASE} --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l app=prometheus --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete serviceaccount --namespace "${NAMESPACE}" ${RELEASE}-api-gateway-jks-create
    if [ "${NAMESPACE}" != "default" ] && [ "${NAMESPACE}" != "kube-public" ] && [ "${NAMESPACE}" != "kube-system" ]; then
      kubectl delete namespace "${NAMESPACE}" --grace-period=0 --force --timeout=10s
    fi
  fi
  exit 0
else
  # Check if there is already a release for helm with the release name that we want
  if [ "${is_helm_v3}" == "" ]; then
    if helm status "${RELEASE}" > /dev/null 2>&1 ; then
      echo -e "\nERROR: There is already a release with name: ${RELEASE} installed in the cluster, please choose a different release name or upgrade the release\n"
      exit 1
    fi
  else
     if helm status --namespace "${NAMESPACE}" "${RELEASE}" > /dev/null 2>&1 ; then
       echo -e "\nERROR: There is already a release with name: ${RELEASE} installed in namespace: ${NAMESPACE} in the cluster, please choose a different release name or upgrade the release\n"
       exit 1
     fi
  fi

  # There isn't let's check if there is a fusion deployment in the namespace already
  if ! kubectl get deployment -n "${NAMESPACE}" -l "app.kubernetes.io/component=query-pipeline,app.kubernetes.io/part-of=fusion" 2>&1 | grep -q "No resources"; then
    # There is a fusion deployed into this namespace, try and protect against two releases being installed into
    # The same namespace
    instance=$(kubectl get deployment -n "${NAMESPACE}" -l "app.kubernetes.io/component=query-pipeline,app.kubernetes.io/part-of=fusion" -o "jsonpath={.items[0].metadata.labels['app\.kubernetes\.io/instance']}")
    echo -e "\nERROR: There is already a fusion deployment in namespace: ${NAMESPACE} with release name: ${instance}, please choose a new namespace\n"
    exit 1
  fi
  # We should be good to install now
fi

function report_ns() {
  if [ "${NAMESPACE}" != "default" ]; then
    echo -e "\nNote: Change the default namespace for kubectl to ${NAMESPACE} by doing:\n    kubectl config set-context --current --namespace=${NAMESPACE}\n"
  fi
}

function proxy_url() {

  if [ "${PROVIDER}" == "eks" ]; then
    export PROXY_HOST=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  else
    export PROXY_HOST=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  fi

  export PROXY_PORT=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.spec.ports[?(@.protocol=="TCP")].port}')
  export PROXY_URL="$PROXY_HOST:$PROXY_PORT"

  if [ "$PROXY_URL" != ":" ]; then
    echo -e "\n\nFusion 5 Gateway service exposed at: $PROXY_URL\n"
    echo -e "WARNING: This IP address is exposed to the WWW w/o SSL! This is done for demo purposes and ease of installation.\nYou are strongly encouraged to configure a K8s Ingress with TLS, see:\n   https://cloud.google.com/kubernetes-engine/docs/tutorials/http-balancer"
    echo -e "\nAfter configuring an Ingress, please change the 'proxy' service to be a ClusterIP instead of LoadBalancer\n"
    report_ns
  else
    echo -e "\n\nFailed to get Fusion Gateway service URL! Check console for previous errors.\n"
  fi
}

function ingress_setup() {
  # Patch yaml for now, until fix gets into helm charts
  kubectl patch --namespace "${NAMESPACE}" ingress "${RELEASE}-api-gateway" -p "{\"spec\":{\"rules\":[{\"host\": \"${INGRESS_HOSTNAME}\", \"http\":{\"paths\":[{\"backend\": {\"serviceName\": \"proxy\", \"servicePort\": 6764}, \"path\": \"/*\"}]}}]}}"
  echo -ne "\nWaiting for the Loadbalancer IP to be assigned"
  loops=24
  while (( loops > 0 )); do
    ingressIp=$(kubectl --namespace "${NAMESPACE}" get ingress "${RELEASE}-api-gateway" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [[ ! -z ${ingressIp} ]]; then
      export INGRESS_IP="${ingressIp}"
      break
    fi
    loops=$(( loops - 1 ))
    echo -ne "."
    sleep 5
  done
  echo -e "\n\nFusion 5 Gateway service exposed at: ${INGRESS_HOSTNAME}\n"
  echo -e "Please ensure that the public DNS record for ${INGRESS_HOSTNAME} is updated to point to ${INGRESS_IP}"
  echo -e "An SSL certificate will be automatically generated once the public DNS record has been updated,\nthis may take up to an hour after DNS has updated to be issued.\nYou can use kubectl get managedcertificates -o yaml to check the status of the certificate issue process."
  echo -e "Add the contents of tls-values.yaml to ${DEFAULT_MY_VALUES} under the api-gateway section."
  report_ns
}

lw_helm_repo=lucidworks

if ! helm repo list | grep -q "https://charts.lucidworks.com"; then
  echo -e "\nAdding the Lucidworks chart repo to helm repo list"
  helm repo add ${lw_helm_repo} https://charts.lucidworks.com
fi

if ! helm repo list | grep -q "https://kubernetes-charts.storage.googleapis.com"; then
  echo -e "\nAdding the stable chart repo to helm repo list"
  helm repo add stable https://kubernetes-charts.storage.googleapis.com
fi

# If no custom values are passed, and we are not upgrading, then supply a default values yaml
if [ -z $CUSTOM_MY_VALUES ] && [ "$UPGRADE" != "1" ]; then
  if [ ! -f "${DEFAULT_MY_VALUES}" ]; then

    CREATED_MY_VALUES=1

    PROMETHEUS_ON=true
    if [ "${PROMETHEUS}" == "none" ]; then
      PROMETHEUS_ON=false
    fi

    if [ "${NODE_POOL}" == "" ]; then
      NODE_POOL="{}"
    fi

    source ./customize_fusion_values.sh $DEFAULT_MY_VALUES -c $CLUSTER_NAME -r $RELEASE --provider ${PROVIDER} --prometheus $PROMETHEUS_ON \
      --num-solr $SOLR_REPLICAS --solr-disk-gb $SOLR_DISK_GB --node-pool "${NODE_POOL}"
  else
    echo -e "\nValues file $DEFAULT_MY_VALUES already exists.\n"
  fi
  MY_VALUES=( ${DEFAULT_MY_VALUES} )
fi

if [ ! -z "${CUSTOM_MY_VALUES[*]}" ]; then
  MY_VALUES=(${CUSTOM_MY_VALUES[@]})
fi

# if we're installing, then wait up to 60s to see the metrics server online, which seems to help make installs more robust on new clusters
if [ "$UPGRADE" != "1" ]; then
  metrics_deployment=$(kubectl get deployment -n kube-system | grep metrics-server | cut -d ' ' -f1 -)
  kubectl rollout status deployment/${metrics_deployment} --timeout=60s --namespace "kube-system"
  echo ""
fi

if ! kubectl get namespace "${NAMESPACE}" > /dev/null; then
  if [ "${UPGRADE}" != "1" ]; then
    kubectl create namespace "${NAMESPACE}"
    kubectl label namespace "${NAMESPACE}" "owner=${OWNER_LABEL}"
  fi
fi

# Make sure we have all the updated charts
helm repo update

# Don't mess with upgrading the Prom / Grafana charts during upgrade
# just let the user do that manually with Helm as needed
if [ "$UPGRADE" != "1" ] && [ "${PROMETHEUS}" != "none" ]; then

  if [ "${NODE_POOL}" == "" ]; then
    NODE_POOL="{}"
  fi

  PROMETHEUS_VALUES="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_prom_values.yaml"
  if [ ! -f "${PROMETHEUS_VALUES}" ]; then
    cp example-values/prometheus-values.yaml $PROMETHEUS_VALUES
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
      sed -i -e "s|{NODE_POOL}|${NODE_POOL}|g" "$PROMETHEUS_VALUES"
      sed -i -e "s|{NAMESPACE}|${NAMESPACE}|g" "$PROMETHEUS_VALUES"
    else
      sed -i '' -e "s|{NODE_POOL}|${NODE_POOL}|g" "$PROMETHEUS_VALUES"
      sed -i '' -e "s|{NAMESPACE}|${NAMESPACE}|g" "$PROMETHEUS_VALUES"
    fi
    echo -e "\nCreated Prometheus custom values yaml: ${PROMETHEUS_VALUES}. Keep this file handy as you'll need it to customize your Prometheus installation.\n"
  fi

  GRAFANA_VALUES="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_graf_values.yaml"
  if [ ! -f "${GRAFANA_VALUES}" ]; then
    cp example-values/grafana-values.yaml $GRAFANA_VALUES
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
      sed -i -e "s|{NODE_POOL}|${NODE_POOL}|g" "$GRAFANA_VALUES"
    else
      sed -i ''  -e "s|{NODE_POOL}|${NODE_POOL}|g" "$GRAFANA_VALUES"
    fi
    echo -e "\nCreated Grafana custom values yaml: ${GRAFANA_VALUES}. Keep this file handy as you'll need it to customize your Grafana installation.\n"
  fi

  if [ "${PROMETHEUS}" == "install" ]; then
    echo -e "\nInstalling Prometheus and Grafana for monitoring Fusion metrics ... this can take a few minutes.\n"

    helm upgrade ${RELEASE}-prom stable/prometheus --install --namespace "${NAMESPACE}" -f "$PROMETHEUS_VALUES" --version 10.3.1
    kubectl rollout status statefulsets/${RELEASE}-prom-prometheus-server --timeout=180s --namespace "${NAMESPACE}"

    helm upgrade ${RELEASE}-graf stable/grafana --install --namespace "${NAMESPACE}" -f "$GRAFANA_VALUES" \
      --set-file dashboards.default.dashboard_gateway_metrics.json=monitoring/grafana/dashboard_gateway_metrics.json \
      --set-file dashboards.default.dashboard_indexing_metrics.json=monitoring/grafana/dashboard_indexing_metrics.json \
      --set-file dashboards.default.dashboard_jvm_metrics.json=monitoring/grafana/dashboard_jvm_metrics.json \
      --set-file dashboards.default.dashboard_query_pipeline.json=monitoring/grafana/dashboard_query_pipeline.json \
      --set-file dashboards.default.dashboard_solr_core.json=monitoring/grafana/dashboard_solr_core.json \
      --set-file dashboards.default.dashboard_solr_node.json=monitoring/grafana/dashboard_solr_node.json \
      --set-file dashboards.default.dashboard_solr_system.json=monitoring/grafana/dashboard_solr_system.json \
      --set-file dashboards.default.kube_metrics.json=monitoring/grafana/kube_metrics.json
    kubectl rollout status deployments/${RELEASE}-graf-grafana --timeout=60s --namespace "${NAMESPACE}"

    echo -e "\n\nSuccessfully installed Prometheus (${RELEASE}-prom) and Grafana (${RELEASE}-graf) into the ${NAMESPACE} namespace.\n"
  fi

fi

# build up a list of multiple --values args to pass to Helm
VALUES_STRING=""
for v in "${MY_VALUES[@]}"; do
  if [ ! -f "${v}" ]; then
    echo -e "\nERROR: Custom values file ${v} not found! Please check your --values arg(s)\n"
    exit 1
  fi
  VALUES_STRING="${VALUES_STRING} --values ${v}"
done

if [ "$UPGRADE" == "1" ]; then

  if [ "${VALUES_STRING}" == "" ]; then
    # no values passed to upgrade, but if the default exists, we'll just use it or error out
    if [ -f "${DEFAULT_MY_VALUES}" ]; then
      VALUES_STRING="--values ${DEFAULT_MY_VALUES}"
    else
      echo -e "\nERROR: Missing one or more custom values yaml files for upgrade!\nAt a minimum, you must pass --values ${DEFAULT_MY_VALUES} to upgrade your cluster.\n"
      exit 1
    fi
  fi

  if [ "${DRY_RUN}" == "" ]; then
    echo -e "\nUpgrading the Fusion 5 release ${RELEASE} in namespace ${NAMESPACE} to version ${CHART_VERSION} with custom values from ${MY_VALUES[*]}"
  else
    echo -e "\nSimulating an update of the Fusion ${RELEASE} installation into the ${NAMESPACE} namespace with custom values from ${MY_VALUES[*]}"
  fi

  helm upgrade ${RELEASE} "${lw_helm_repo}/fusion" --namespace "${NAMESPACE}" ${VALUES_STRING} ${DRY_RUN} --version "${CHART_VERSION}"
  upgrade_status=$?
  if [ "${TLS_ENABLED}" == "1" ]; then
    ingress_setup
  else
    proxy_url
  fi
  exit $upgrade_status
fi

echo -e "\nInstalling Fusion 5.0 Helm chart ${CHART_VERSION} into namespace ${NAMESPACE} with release tag: ${RELEASE} using custom values from ${MY_VALUES[*]}"
echo -e "\nNOTE: If this will be a long-running cluster for production purposes, you should save the ${MY_VALUES[*]} file(s) in version control.\n"

# let's exit immediately if the helm install command fails
set -e
if [ "$is_helm_v3" != "" ]; then
  if ! kubectl get namespace "${NAMESPACE}"; then
    kubectl create namespace "${NAMESPACE}"
  fi
  # looks like Helm V3 doesn't like the -n parameter for the release name anymore
  helm install "${RELEASE}" ${lw_helm_repo}/fusion --timeout=240s --namespace "${NAMESPACE}" ${VALUES_STRING} --version "${CHART_VERSION}"
else
  helm install ${lw_helm_repo}/fusion --timeout 240 --namespace "${NAMESPACE}" -n "${RELEASE}" ${VALUES_STRING} --version "${CHART_VERSION}"
fi
set +e

echo -e "\nWaiting up to 10 minutes to see the Fusion API Gateway deployment come online ...\n"
kubectl rollout status deployment/${RELEASE}-api-gateway --timeout=600s --namespace "${NAMESPACE}"
echo -e "\nWaiting up to 2 minutes to see the Fusion Admin deployment come online ...\n"
kubectl rollout status deployment/${RELEASE}-fusion-admin --timeout=120s --namespace "${NAMESPACE}"

echo -e "\nHelm releases:"
helm ls --namespace "${NAMESPACE}"

if [ "${TLS_ENABLED}" == "1" ]; then
  ingress_setup
else
  proxy_url
fi
kubectl config set-context --current --namespace=${NAMESPACE}

UPGRADE_SCRIPT="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_upgrade_fusion.sh"
cp upgrade_fusion.sh.example $UPGRADE_SCRIPT
if [[ "$OSTYPE" == "linux-gnu" ]]; then
  sed -i -e "s|<PROVIDER>|${PROVIDER}|g" "$UPGRADE_SCRIPT"
  sed -i -e "s|<CLUSTER>|${CLUSTER_NAME}|g" "$UPGRADE_SCRIPT"
  sed -i -e "s|<RELEASE>|${RELEASE}|g" "$UPGRADE_SCRIPT"
  sed -i -e "s|<NAMESPACE>|${NAMESPACE}|g" "$UPGRADE_SCRIPT"
  sed -i -e "s|<CHART_VERSION>|${CHART_VERSION}|g" "$UPGRADE_SCRIPT"
else
  sed -i '' -e "s|<PROVIDER>|${PROVIDER}|g" "$UPGRADE_SCRIPT"
  sed -i '' -e "s|<CLUSTER>|${CLUSTER_NAME}|g" "$UPGRADE_SCRIPT"
  sed -i '' -e "s|<RELEASE>|${RELEASE}|g" "$UPGRADE_SCRIPT"
  sed -i '' -e "s|<NAMESPACE>|${NAMESPACE}|g" "$UPGRADE_SCRIPT"
  sed -i '' -e "s|<CHART_VERSION>|${CHART_VERSION}|g" "$UPGRADE_SCRIPT"
fi
echo -e "\nCreating $UPGRADE_SCRIPT for upgrading you Fusion cluster. Please keep this script along with your custom values yaml file(s) in version control.\n"
