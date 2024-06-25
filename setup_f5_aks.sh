#!/bin/bash

INSTANCE_TYPE="Standard_D4_v3"
CHART_VERSION="5.9.4"
NODE_COUNT=3
AKS_MASTER_VERSION="1.29.6"
CERT_CLUSTER_ISSUER="letsencrypt"
AKS_KUBE_CONFIG="${KUBECONFIG:-~/.kube/config}"
SCRIPT_CMD="$0"
AZURE_RESOURCE_GROUP=
CLUSTER_NAME=
NAMESPACE=default
UPGRADE=0
PURGE=0
ML_MODEL_STORE="fusion"
CUSTOM_MY_VALUES=()
MY_VALUES=()
PREVIEW=0
AZURE_LOCATION=""
PROMETHEUS="install"
NODE_POOL=""
SOLR_REPLICAS=1
KAFKA_REPLICAS=1
SOLR_DISK_GB=50

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on AKS; optionally create a AKS cluster in the process"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c                Name of the AKS cluster (required)\n"
  echo -e "  -p                Azure resource group (required). If the given group doesn't exist, this script creates it using:"
  echo -e "                        az group create --name <GROUP_NAME> --location <LOCATION>\n"
  echo -e "  -r                Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n                Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  -z                Azure location to launch the cluster in, defaults to the location for your Resource Group\n"
  echo -e "  -i                Instance type, defaults to '${INSTANCE_TYPE}'\n"
  echo -e "  -y                Initial node count, defaults to '${NODE_COUNT}'\n"
  echo -e "  -t                Enable TLS for the ingress, requires a hostname to be specified with -h\n"
  echo -e "  -h                Hostname for the ingress to route requests to this Fusion cluster. If used with the -t parameter,"
  echo -e "                    then the hostname must be a public DNS record that can be updated to point to the IP of the LoadBalancer\n"
  echo -e "  --prometheus      Enable Prometheus and Grafana for monitoring Fusion services, pass one of: install, provided, none;"
  echo -e "                    defaults to 'install' which installs Prometheus and Grafana from the stable Helm repo,"
  echo -e "                    'provided' enables pod annotations on Fusion services to work with Prometheus but does not install anything\n"
  echo -e "  --num-solr        Number of Solr pods to deploy, defaults to 1\n"
  echo -e "  --num-kafka       Number of Kafka pods to deploy, defaults to 1\n"
  echo -e "  --solr-disk-gb    Size (in gigabytes) of the Solr persistent volume claim, defaults to 50\n"
  echo -e "  --node-pool       Node pool label to assign pods to specific nodes, this option is only useful for existing clusters"
  echo -e "                    where you defined a custom node pool, wrap the arg in double-quotes\n"
  echo -e "  --aks             AKS Kubernetes version; defaults to ${AKS_MASTER_VERSION}\n"
  echo -e "  --preview         Enable PREVIEW mode when creating the cluster to experiment with unreleased options\n"
  echo -e "  --version         Fusion Helm Chart version; defaults to the latest release from Lucidworks, such as ${CHART_VERSION}\n"
  echo -e "  --values          Custom values file containing config overrides; defaults to aks_<cluster>_<release>_fusion_values.yaml\n"
  echo -e "  --upgrade         Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --purge           Uninstall and purge all Fusion objects from the specified namespace and cluster."
  echo -e "                    Be careful! This operation cannot be undone.\n"
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
        -p)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -p parameter!"
              exit 1
            fi
            AZURE_RESOURCE_GROUP="$2"
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
        -z)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -z parameter!"
              exit 1
            fi
            AZURE_LOCATION="$2"
            shift 2
        ;;
        -t)
            TLS_ENABLED=1
            shift 1
        ;;
        -h)
            if [[ -h "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -h parameter!"
              exit 1
            fi
            INGRESS_HOSTNAME="$2"
            shift 2
        ;;
        -i)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -i parameter!"
              exit 1
            fi
            INSTANCE_TYPE="$2"
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
              print_usage "$SCRIPT_CMD" "Missing value for the --num-solr parameter!"
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
        --prometheus)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --prometheus parameter!"
              exit 1
            fi
            PROMETHEUS="$2"
            shift 2
        ;;
        --aks)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --aks parameter!"
              exit 1
            fi
            AKS_MASTER_VERSION="$2"
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
        -y)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -y parameter!"
              exit 1
            fi
            NODE_COUNT="$2"
            shift 2
        ;;
        --preview)
            PREVIEW=1
            shift 1
        ;;
        --upgrade)
            UPGRADE=1
            shift 1
        ;;
        --purge)
            PURGE=1
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
  print_usage "$SCRIPT_CMD" "Please provide the cluster name using: -c <cluster>"
  exit 1
fi

if [ "$AZURE_RESOURCE_GROUP" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Azure Resource Group name using: -p <azure resource group>\n   To create a new Resource Group you can do: az group create --name myResourceGroup --location eastus2"
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

DEFAULT_MY_VALUES="aks_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"

if [ "${TLS_ENABLED}" == "1" ] && [ -z "${INGRESS_HOSTNAME}" ]; then
  print_usage "$SCRIPT_CMD" "if -t is specified -h must be specified and a domain that you can update to add an A record to point to the Loadbalancer IP"
  exit 1
fi

hash az
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install the Azure CLI (az) before proceeding with this script!\n     See: https://docs.microsoft.com/en-us/cli/azure/?view=azure-cli-latest\n"
  exit 1
fi

# verify the user is logged in ...
who_am_i=$(az account show --query 'user.name'| sed -e 's/"//g')
if [ "$who_am_i" == "" ]; then
  echo -e "\nERROR: Azure user unknown, please use: 'az login' before proceeding with this script!"
  exit 1
fi

echo -e "\nLogged in as: $who_am_i\n"

hash kubectl
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install kubectl before proceeding with this script! For AKS, run 'az aks install-cli'"
  exit 1
fi

hash helm
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install helm before proceeding with this script! See: https://helm.sh/docs/using_helm/#quickstart"
  exit 1
fi

is_helm_v3=$(helm version --short | grep v3)

# check to see if the resource group exists
LISTOUT=`az group list --query "[?name=='${AZURE_RESOURCE_GROUP}']"`
rglist_worked=$?
if [ $rglist_worked == 1 ]; then
  echo -e "\nERROR: listing for resource group failed. Check that az tool is properly installed."
  exit 1
fi

# Create the resource group if it doesn't exist
if [ "${LISTOUT}" == "[]" ]; then

  if [ "$AZURE_LOCATION" == "" ]; then
    AZURE_LOCATION="eastus2"
    echo -e "\nWARNING: ${AZURE_RESOURCE_GROUP} not found! Creating new with default location ${AZURE_LOCATION}\n"
  fi

  az group create -g $AZURE_RESOURCE_GROUP -l $AZURE_LOCATION
  azgroupcreate=$?
  if [ $azgroupcreate == 1 ]; then
    echo -e "\nERROR: Unable to create resource group: ${AZURE_RESOURCE_GROUP} in azure location: ${AZURE_LOCATION} check account permissions!\n"
    exit 1
  fi
fi

# The location value should come from the Resource Group settings if not specified by the user
if [ "$AZURE_LOCATION" == "" ]; then
  AZURE_LOCATION=$(az group show --name ${AZURE_RESOURCE_GROUP} --query location | tr -d '"')
fi

if [ "$PURGE" == "1" ]; then
  az aks get-credentials -n "${CLUSTER_NAME}" -g "${AZURE_RESOURCE_GROUP}" -f "${AKS_KUBE_CONFIG}"
  getcreds=$?
  if [ "$getcreds" != "0" ]; then
    echo -e "\nERROR: Can't find kubernetes cluster: ${CLUSTER_NAME} in Azure resource group ${AZURE_RESOURCE_GROUP} to purge!"
    exit 1
  fi

  FORCE_ARG=""
  if [ "${FORCE}" == "1" ]; then
    FORCE_ARG=" --force"
  fi

  source ./setup_f5_k8s.sh -c ${CLUSTER_NAME} -r ${RELEASE} -n ${NAMESPACE} --purge ${FORCE_ARG}
  exit 0
fi

LISTOUT=`az aks list --query "[?name=='${CLUSTER_NAME}']"`
cluster_status=$?
if [ $cluster_status == 1 ]; then
  echo -e "\nERROR: error listing clusters"
  exit 1
fi

if [ "$LISTOUT" == "[]" ]; then
  echo -e "\nLaunching AKS cluster ${CLUSTER_NAME} in resource group ${AZURE_RESOURCE_GROUP} in location ${AZURE_LOCATION} for deploying Lucidworks Fusion 5 ...\n"

  PREVIEW_OPTS=""
  if [ "${PREVIEW}" == "1" ]; then

    min_count=3
    if [ "${NODE_COUNT}" == "1" ]; then
      min_count=1
    elif [ "${NODE_COUNT}" == "2" ]; then
      min_count=2
    fi

    PREVIEW_OPTS="--enable-vmss --node-zones 1 2 3 --enable-cluster-autoscaler --min-count ${min_count} --max-count 3"
    echo -e "\nEnabling AKS preview extension with the following PREVIEW options: ${PREVIEW_OPTS}\n"
    az extension add --name aks-preview
    az extension update --name aks-preview > /dev/null 2>&1
    az feature register --name AvailabilityZonePreview --namespace Microsoft.ContainerService
    az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/AvailabilityZonePreview')].{Name:name,State:properties.state}"
    az provider register --namespace Microsoft.ContainerService
    echo -e "\nEnabled the AvailabilityZonePreview feature\n"
  fi

  az aks create ${PREVIEW_OPTS} \
      --enable-addons http_application_routing,monitoring \
      --resource-group ${AZURE_RESOURCE_GROUP} \
      --name ${CLUSTER_NAME} \
      --node-count ${NODE_COUNT} \
      --node-vm-size ${INSTANCE_TYPE} \
      --kubernetes-version ${AKS_MASTER_VERSION} \
      --generate-ssh-keys
  cluster_created=$?

  if [ "$cluster_created" != "0" ]; then
    echo -e "\nERROR: Create AKS cluster ${CLUSTER_NAME} failed! Look for previously reported errors or check the Azure portal before proceeding!\n"
    exit 1
  fi
  echo -e "\nCluster '${CLUSTER_NAME}' deployed ... testing if it is healthy"

  az aks list --query "[].name" | grep ${CLUSTER_NAME} > /dev/null 2>&1
  cluster_status=$?
  if [ "$cluster_status" != "0" ]; then
    echo -e "\nERROR: Status of AKS cluster ${CLUSTER_NAME} is suspect, check the state of the cluster in the Azure portal before proceeding!\n"
    exit 1
  fi
else
  if [ "$UPGRADE" == "0" ]; then
    echo -e "\nAKS Cluster '${CLUSTER_NAME}' already exists, proceeding with Fusion 5 install ...\n"
  fi
fi

az aks get-credentials -n "${CLUSTER_NAME}" -g "${AZURE_RESOURCE_GROUP}" -f "${AKS_KUBE_CONFIG}" --admin
kubectl config current-context

kubectl rollout status deployment/${RELEASE}-query-pipeline -n ${NAMESPACE} --timeout=10s > /dev/null 2>&1
rollout_status=$?
if [ $rollout_status == 0 ]; then
  if [ "$UPGRADE" == "0" ]; then
    echo -e "\nLooks like Fusion is already running ..."
    exit 0
  fi
fi

if [ "$UPGRADE" == "0" ]; then
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=${who_am_i}
fi

if [ "${is_helm_v3}" == "" ]; then
  # see if Tiller is deployed if using Helm V2
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
  echo -e "Using Helm V3 ($is_helm_v3)"
fi

INGRESS_VALUES=""
if [ "${TLS_ENABLED}" == "1" ]; then
  TLS_VALUES="tls-values.yaml"
  INGRESS_VALUES="${INGRESS_VALUES} --values tls-values.yaml"
  tee "${TLS_VALUES}" << END
api-gateway:
  service:
    type: "NodePort"
  ingress:
    path: "/"
    enabled: true
    host: "${INGRESS_HOSTNAME}"
    tls:
      enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
      certmanager.k8s.io/cluster-issuer: ${CERT_CLUSTER_ISSUER}

END

  ingress_namespace="internal-ingress"
  # First we install the nginx ingress controller
  if ! kubectl get namespace "${ingress_namespace}"; then
    kubectl create namespace "${ingress_namespace}"
    if [ "$is_helm_v3" != "" ]; then
      helm install "nginx-ingress-controller" stable/nginx-ingress \
        --namespace "${ingress_namespace}" \
        --set controller.replicaCount=2 \
        --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
        --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux
    else
      helm install stable/nginx-ingress --name "nginx-ingress-controller" \
        --namespace "${ingress_namespace}" \
        --set controller.replicaCount=2 \
        --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
        --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux
    fi
  fi

  certmanager_namespace="cert-manager"
  if ! kubectl get namespace "${certmanager_namespace}"; then
    kubectl create namespace "${certmanager_namespace}"
    kubectl label namespace "${certmanager_namespace}" certmanager.k8s.io/disable-validation=true

    kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.8/deploy/manifests/00-crds.yaml

    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    if [ "$is_helm_v3" != "" ]; then
      helm install --wait cert-manager --namespace "${certmanager_namespace}" --version v0.8.0 jetstack/cert-manager
    else
      helm install --wait -n cert-manager --namespace "${certmanager_namespace}" --version v0.8.0 jetstack/cert-manager
    fi
    echo -e "Waiting for certmanager to be registered"
    loops=24
    while (( loops > 0 )); do
      cat <<EOF | kubectl -n "${certmanager_namespace}" apply -f -
  apiVersion: certmanager.k8s.io/v1
  kind: ClusterIssuer
  metadata:
    name: "${CERT_CLUSTER_ISSUER}"
    namespace: "${certmanager_namespace}"
  spec:
    acme:
      server: https://acme-v02.api.letsencrypt.org/directory
      email: "${who_am_i}"
      privateKeySecretRef:
        name: "${CERT_CLUSTER_ISSUER}"
      http01: {}
EOF
      rc=$?
      if (( ${rc} == 0 )); then
        echo "ClusterIssuer setup"
        break
      fi
      loops=$(( loops - 1 ))
      sleep 10
    done
  fi
fi

if [ ! -z "${CUSTOM_MY_VALUES[*]}" ]; then
  MY_VALUES=(${CUSTOM_MY_VALUES[@]})
fi

VALUES_STRING=""
if [ "${UPGRADE}" == "1" ] && [ -z "$MY_VALUES" ] && [ -f "${DEFAULT_MY_VALUES}" ]; then
  MY_VALUES=( ${DEFAULT_MY_VALUES} )
fi

for v in "${MY_VALUES[@]}"; do
  if [ ! -f "${v}" ]; then
    echo -e "\nWARNING: Custom values file ${v} not found!\nYou need to provide the same custom values you provided when creating the cluster in order to upgrade.\n"
    exit 1
  fi
  VALUES_STRING="${VALUES_STRING} --values ${v}"
done

if [ ! -z "${INGRESS_VALUES}" ]; then
  # since we're passing INGRESS_VALUES to the setup_f5_k8s script,
  # we might need to create the default from the template too
  if [ -z "${VALUES_STRING}" ] && [ "${UPGRADE}" != "1" ] && [ ! -f "${DEFAULT_MY_VALUES}" ]; then

    PROMETHEUS_ON=true
    if [ "${PROMETHEUS}" == "none" ]; then
      PROMETHEUS_ON=false
    fi

    source ./customize_fusion_values.sh $DEFAULT_MY_VALUES -c $CLUSTER_NAME -n $NAMESPACE -r $RELEASE --version "${CHART_VERSION}" --provider "aks" --prometheus $PROMETHEUS_ON \
      --num-solr $SOLR_REPLICAS --num-kafka $KAFKA_REPLICAS --solr-disk-gb $SOLR_DISK_GB --node-pool "${NODE_POOL}"
    VALUES_STRING="--values ${DEFAULT_MY_VALUES}"
  fi

  VALUES_STRING="${VALUES_STRING} ${INGRESS_VALUES}"
fi

# Invoke the generic K8s setup script to complete the install/upgrade
INGRESS_ARG=""
if [ ! -z "${INGRESS_HOSTNAME}" ]; then
  INGRESS_ARG=" --ingress ${INGRESS_HOSTNAME}"
fi

UPGRADE_ARGS=""
if [ "${UPGRADE}" == "1" ]; then
  UPGRADE_ARGS=" --upgrade"
  if [ "${FORCE}" == "1" ]; then
    UPGRADE_ARGS="$UPGRADE_ARGS --force"
  fi
  if [ "${DRY_RUN}" != "" ]; then
    UPGRADE_ARGS="$UPGRADE_ARGS --dry-run"
  fi
else
  if [ "${PURGE}" == "1" ]; then
    UPGRADE_ARGS=" --purge"
    if [ "${FORCE}" == "1" ]; then
      UPGRADE_ARGS="$UPGRADE_ARGS --force"
    fi
  fi
fi

if [ "${NODE_POOL}" == "" ] || [ "${NODE_POOL}" == "fusion_node_type: system" ]; then
  # the user did not specify a node pool label, but our templating needs one
  for node in $(kubectl get nodes --namespace="${NAMESPACE}" -o=name); do kubectl label "$node" fusion_node_type=system; done
  NODE_POOL="fusion_node_type: system"
fi

# for debug only
#echo -e "Calling setup_f5_k8s.sh with: ${VALUES_STRING}${INGRESS_ARG}${UPGRADE_ARGS}"
source ./setup_f5_k8s.sh -c $CLUSTER_NAME -r "${RELEASE}" --provider "aks" -n "${NAMESPACE}" --node-pool "${NODE_POOL}" \
  --version ${CHART_VERSION} --prometheus ${PROMETHEUS} --num-solr "${SOLR_REPLICAS}" --num-kafka "${KAFKA_REPLICAS}"  --solr-disk-gb  "${SOLR_DISK_GB}" ${VALUES_STRING}${INGRESS_ARG}${UPGRADE_ARGS}
setup_result=$?
exit $setup_result
