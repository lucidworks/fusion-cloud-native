#!/bin/bash

# Platform agnostic script used by the other setup_f5_*.sh scripts to perform general K8s and Helm commands to install Fusion.
# This script assumes kubectl is pointing to the right cluster and that the user is already authenticated.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"

CHART_VERSION="5.9.4"
PROVIDER="k8s"
INGRESS_HOSTNAME=""
TLS_ENABLED="0"
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
SOLR_REPLICAS=1
KAFKA_REPLICAS=1
NODE_POOL="{}"

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on an existing Kubernetes cluster"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c                Name of the K8s cluster (required)\n"
  echo -e "  -r                Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n                Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  --provider        Lowercase label for your K8s platform provider, e.g. eks, aks, gke, oc; defaults to 'k8s'\n"
  echo -e "  --node-pool       Node pool label to assign pods to specific nodes, this option is only useful for existing clusters"
  echo -e "                    where you defined a custom node pool, wrap the arg in double-quotes\n"
  echo -e "  --ingress         Ingress hostname\n"
  echo -e "  --tls             Whether tls on the ingress\n"
  echo -e "  --prometheus      Enable Prometheus and Grafana for monitoring Fusion services, pass one of: install, provided, none;"
  echo -e "                    defaults to 'install' which installs Prometheus and Grafana from the stable Helm repo,"
  echo -e "                    'provided' enables pod annotations on Fusion services to work with Prometheus but does not install anything\n"
  echo -e "  --version         Fusion Helm Chart version; defaults to the latest release from Lucidworks, such as ${CHART_VERSION}\n"
  echo -e "  --values          Custom values file containing config overrides in addition to the default gke_<cluster>_<namespace>_fusion_values.yaml"
  echo -e "                    (can be specified multiple times to add additional yaml files, see example-values/*.yaml)\n"
  echo -e "  --upgrade         Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --dry-run         Perform a dry-run of the upgrade to see what would change\n"
  echo -e "  --purge           Uninstall and purge all Fusion objects from the specified namespace and cluster."
  echo -e "                    Be careful! This operation cannot be undone.\n"
  echo -e "  --force           Force upgrade or purge a deployment if your account is not the value 'owner' label on the namespace\n"
  echo -e "  --num-solr        Number of Solr pods to deploy, defaults to 1\n"
  echo -e "  --num-kafka       Number of Kafka pods to deploy, defaults to 1\n"
  echo -e "  --solr-disk-gb    Size (in gigabytes) of the Solr persistent volume claim, defaults to 50\n"
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
        --tls)
            TLS_ENABLED=1
            shift 1
        ;;
        --prometheus)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --prometheus parameter!"
              exit 1
            fi
            PROMETHEUS="$2"
            shift 2
        ;;
        --num-solr)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --num-solr parameter!"
              exit 1
            fi
            SOLR_REPLICAS=$2
            shift 2
        ;;
        --num-kafka)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --num-kafka parameter!"
              exit 1
            fi
            KAFKA_REPLICAS=$2
            shift 2
        ;;
        --solr-disk-gb)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --solr-disk-gb parameter!"
              exit 1
            fi
            SOLR_DISK_GB=$2
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

# Sanity check we have the required variables
if [ "$CLUSTER_NAME" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Kubernetes cluster name using: -c <cluster>"
  exit 1
fi

valid="0-9a-zA-Z\-"
if [[ $NAMESPACE =~ [^$valid] ]]; then
  echo -e "\nERROR: Namespace $NAMESPACE must only contain 0-9, a-z, A-Z, or dash!\n"
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
  echo -e "\nERROR: Release $RELEASE must only contain 0-9, a-z, A-Z, or dash!\n"
  exit 1
fi

# The default values file that will be created for the cluster
DEFAULT_MY_VALUES="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"

# The name of the upgrade script that will be created to upgrade fusion
UPGRADE_SCRIPT="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_upgrade_fusion.sh"

# Check our prerequisites are in place
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

# Log our current kube context for the user
current=$(kubectl config current-context)
echo -e "Using kubeconfig: $current"

# Setup our owner label so we can check ownership of namespaces
if [ "$PROVIDER" == "gke" ]; then
  who_am_i=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
else
  who_am_i=""
fi
OWNER_LABEL="${who_am_i//@/-}"

# Determine if we have helm v3
# TODO drop support for helm v2
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

# If we are upgrading
if [ "${UPGRADE}" == "1" ]; then
  # Make sure the namespace exists
  if ! kubectl get namespace "${NAMESPACE}" > /dev/null 2>&1; then
    echo -e "\nNamespace ${NAMESPACE} not found, if this is a new cluster please run an install first"
    exit 1
  fi

  # Check if the owner label on the namespace is the same as we are, so we cannot
  # accidentally upgrade a release from someone elses namespace
  namespace_owner=$(kubectl get namespace "${NAMESPACE}" -o 'jsonpath={.metadata.labels.owner}')
  if [ "${namespace_owner}" != "${OWNER_LABEL}" ] && [ "${FORCE}" != "1" ]; then
    echo -e "Namespace ${NAMESPACE} is owned by: ${namespace_owner}, by we are: ${OWNER_LABEL} please provide the --force parameter if you are sure you wish to upgrade this namespace"
    exit 1
  fi
elif [ "$PURGE" == "1" ]; then
  kubectl get namespace "${NAMESPACE}"
  namespace_exists=$?
  if [ "$namespace_exists" != "0" ]; then
    echo -e "\nNamespace ${NAMESPACE} not found so assuming ${RELEASE_NAME} has already been purged"
    exit 1
  fi

  # Check if the owner label on the namespace is the same as we are, so we cannot
  # accidentally purge someone elses release
  namespace_owner=$(kubectl get namespace "${NAMESPACE}" -o 'jsonpath={.metadata.labels.owner}')
  if [ "${namespace_owner}" != "${OWNER_LABEL}" ] && [ "${FORCE}" != "1" ]; then
    echo -e "Namespace ${NAMESPACE} is owned by: ${namespace_owner}, by we are: ${OWNER_LABEL} please provide the --force parameter if you are sure you wish to purge this namespace"
    exit 1
  fi

  confirm="Y"
  echo ""
  read -p "Are you sure you want to purge the ${RELEASE} release from the ${NAMESPACE} namespace in: $current? This operation cannot be undone! Y/n " confirm
  if [ "$confirm" == "" ] || [ "$confirm" == "Y" ] || [ "$confirm" == "y" ]; then

    if [ "$is_helm_v3" != "" ]; then
      helm delete "${RELEASE}" --namespace "${NAMESPACE}"
      monitor_chart_checker=$(helm list  | grep -o ${RELEASE}-monitoring)
      if [ "$monitor_chart_checker" == "${RELEASE}-monitoring" ]; then
        helm delete "${RELEASE}-monitoring" --namespace "${NAMESPACE}"
        kubectl delete pvc -l app=prometheus --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
      fi
    else
      helm del --purge "${RELEASE}"
    fi
    kubectl delete deployments -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete svc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=2s
    kubectl delete pvc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l "release=${RELEASE}" --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l "app.kubernetes.io/instance=${RELEASE}" --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
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

# report_ns logs a message to the user informing them how to change the default namespace
function report_ns() {
  if [ "${NAMESPACE}" != "default" ]; then
    echo -e "\nNote: Change the default namespace for kubectl to ${NAMESPACE} by doing:\n    kubectl config set-context --current --namespace=${NAMESPACE}\n"
  fi
}

# proxy_url prints how to access the proxy via a LoadBalancer service
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

# ingress_setup informs the user how to finish setting up the DNS records for their ingress with hostname
function ingress_setup() {
  if [ "${PROVIDER}" != "eks" ]; then
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
      echo -e "\n\nFusion 5 Gateway service exposed at: ${INGRESS_HOSTNAME}\n"
      echo -e "Please ensure that the public DNS record for ${INGRESS_HOSTNAME} is updated to point to ${INGRESS_IP}"
    done
  else
    #EKS setup for supporting ALBs and nginx ingress
    ALB_DNS=$(kubectl get ing ${RELEASE}-api-gateway --output=jsonpath={.status..loadBalancer..ingress[].hostname})

    echo -e "\n\nPlease ensure that the public DNS record for ${INGRESS_HOSTNAME} is updated to point to ${ALB_DNS}\n"
  fi

  if [ "$TLS_ENABLED" == "1" ]; then
  echo -e "An SSL certificate will be automatically generated once the public DNS record has been updated,\nthis may take up to an hour after DNS has updated to be issued.\nYou can use kubectl get managedcertificates -o yaml to check the status of the certificate issue process."
  fi
  report_ns
}

if [ ! -z "${CUSTOM_MY_VALUES[*]}" ]; then
  MY_VALUES=(${CUSTOM_MY_VALUES[@]})
fi

# build up a list of multiple --values args to pass to Helm
VALUES_STRING=""
for v in "${MY_VALUES[@]}"; do
  if [ ! -f "${v}" ]; then
    echo -e "\nERROR: Custom values file ${v} not found! Please check your --values arg(s)\n"
    exit 1
  fi
  VALUES_STRING="${VALUES_STRING} --additional-values ${v}"
done

# If we are not upgrading then generate the values files and upgrade script
if [ "$UPGRADE" != "1" ]; then
  if [ -f "${UPGRADE_SCRIPT}" ]; then
    echo "There is already an upgrade script ${UPGRADE_SCRIPT} present, please use a new release name or upgrade your current release"
    exit 1
  fi
  if [ ! -f "${DEFAULT_MY_VALUES}" ]; then

    PROMETHEUS_ON=true
    if [ "${PROMETHEUS}" == "none" ]; then
      PROMETHEUS_ON=false
    fi

    num_nodes=1
    if [ "${NODE_POOL}" != "" ] && [ "${NODE_POOL}" != "{}" ]; then
      node_selector=$(tr ': ' '=' <<<"${NODE_POOL}")
      #Adding a retry loop because EKS takes more time to create nodes.
      retries=6
      while (( retries > 0 )); do
        find_nodes=$(kubectl get nodes -l "${node_selector}" | grep -i ready)
        has_nodes=$?
        if [ "${has_nodes}" == "0" ]; then
          echo -e "Found at least one healthy node matching nodeSelector: ${NODE_POOL}"
          num_nodes=$(kubectl get nodes -l "${node_selector}" | grep -i ready | wc -l)
          retries=-1
        else
          echo -e "\nERROR: No 'Ready' nodes found matching nodeSelector: ${node_selector}! Retrying in 30 seconds"
          echo -ne "."
          sleep 30
          retries=$(( retries - 1 ))
        fi
      done
      if [ "${retries}" == "0" ]; then
        echo -e "\nERROR: No 'Ready' nodes found matching nodeSelector: ${node_selector}! Check the '--node-pool' parameter and retry running this script!\n"
        exit 1
      fi
    else
      num_nodes=$(kubectl get nodes | grep -i ready | wc -l)
    fi

     ( "${SCRIPT_DIR}/customize_fusion_values.sh" "${DEFAULT_MY_VALUES}" -c "${CLUSTER_NAME}" -n "${NAMESPACE}" -r "${RELEASE}" --provider "${PROVIDER}" --prometheus "${PROMETHEUS_ON}" \
      --num-solr "${SOLR_REPLICAS}" --num-kafka "${KAFKA_REPLICAS}" --solr-disk-gb "${SOLR_DISK_GB}" --node-pool "${NODE_POOL}" --version "${CHART_VERSION}" --output-script "${UPGRADE_SCRIPT}" ${VALUES_STRING} )
  else
    echo -e "\nValues file $DEFAULT_MY_VALUES already exists, not regenerating.\n"
  fi
fi


#Added policy for openshift
if [ "$PROVIDER" == "oc" ]; then
  oc adm policy add-scc-to-group anyuid system:authenticated
fi

# Don't mess with upgrading the Prom / Grafana charts during upgrade
# just let the user do that manually with Helm as needed
if [ "$UPGRADE" != "1" ] && [ "${PROMETHEUS}" != "none" ]; then
  if [ "${PROMETHEUS}" == "install" ]; then
    ( "${SCRIPT_DIR}/install_prom.sh" -c "${CLUSTER_NAME}" -n "${NAMESPACE}" -r "${RELEASE}" --provider "${PROVIDER}" --node-pool "${NODE_POOL}" )
  fi
fi

if [ "$UPGRADE" == "1" ]; then
  if [ ! -f "${SCRIPT_DIR}/${UPGRADE_SCRIPT}" ]; then
    echo -e "\nUpgrade script ${SCRIPT_DIR}/${UPGRADE_SCRIPT} not found, if this is a new cluster please run an install first"
    exit 1
  fi
else
  echo -e "\nInstalling Fusion 5.0 Helm chart ${CHART_VERSION} into namespace ${NAMESPACE} with release tag: ${RELEASE}"
fi

# let's exit immediately if the helm install command fails
set -e
( "${SCRIPT_DIR}/${UPGRADE_SCRIPT}" "${DRY_RUN}" )
set +e

if [ ! -z "${INGRESS_HOSTNAME}" ]; then
  ingress_setup
else
  proxy_url
fi
