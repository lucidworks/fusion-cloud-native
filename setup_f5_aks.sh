#!/bin/bash

INSTANCE_TYPE="Standard_D4_v3"
CHART_VERSION="5.0.2-6"
NODE_COUNT=3
AKS_MASTER_VERSION="1.13.11"
CERT_CLUSTER_ISSUER="letsencrypt"
AKS_KUBE_CONFIG="${KUBECONFIG:-~/.kube/config}"

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on AKS; optionally create a AKS cluster in the process"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c          Name of the AKS cluster (required)\n"
  echo -e "  -p          Azure resource group (required)\n                  If the given group doesn't exist, this script creates it using:\n                  az group create --name <GROUP_NAME> --location <LOCATION>\n"
  echo -e "  -r          Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n          Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  -z          Azure location to launch the cluster in, defaults to the location for your Resource Group\n"
  echo -e "  -i          Instance type, defaults to '${INSTANCE_TYPE}'\n"
  echo -e "  -y          Initial node count, defaults to '${NODE_COUNT}'\n"
  echo -e "  -t          Enable TLS for the ingress, requires a hostname to be specified with -h\n"
  echo -e "  -h          Hostname for the ingress to route requests to this Fusion cluster. If used with the -t parameter,\n              then the hostname must be a public DNS record that can be updated to point to the IP of the LoadBalancer\n"
  echo -e "  --aks       AKS Kubernetes version; defaults to ${AKS_MASTER_VERSION}\n"
  echo -e "  --preview   Enable PREVIEW mode when creating the cluster to experiment with unreleased options\n"
  echo -e "  --version   Fusion Helm Chart version; defaults to the latest release from Lucidworks, such as ${CHART_VERSION}\n"
  echo -e "  --values    Custom values file containing config overrides; defaults to aks_<cluster>_<release>_fusion_values.yaml\n"
  echo -e "  --upgrade   Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --purge     Uninstall and purge all Fusion objects from the specified namespace and cluster.\n              Be careful! This operation cannot be undone.\n"
}

# prep for helm 3
helm=`which helm`

SCRIPT_CMD="$0"
AZURE_RESOURCE_GROUP=
CLUSTER_NAME=
RELEASE=f5
NAMESPACE=default
UPGRADE=0
PURGE=0
ML_MODEL_STORE="fusion"
CUSTOM_MY_VALUES=""
PREVIEW=0
AZURE_LOCATION=""

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
            CUSTOM_MY_VALUES="$2"
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

MY_VALUES="aks_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"
if [ -n "$CUSTOM_MY_VALUES" ]; then
  MY_VALUES=$CUSTOM_MY_VALUES
fi

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
    AZURE_LOCATION="useast2"
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

  current=$(kubectl config current-context)
  confirm="Y"
  read -p "Are you sure you want to purge the ${RELEASE} release from the ${NAMESPACE} namespace in: $current? This operation cannot be undone! Y/n " confirm
  if [ "$confirm" == "" ] || [ "$confirm" == "Y" ] || [ "$confirm" == "y" ]; then
    ${helm} del --purge ${RELEASE}
    kubectl delete deployments -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete job ${RELEASE}-api-gateway --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=1s
    kubectl delete svc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=2s
    kubectl delete pvc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l release=${RELEASE} --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l app.kubernetes.io/instance=${RELEASE} --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
  fi
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

function report_ns() {
  if [ "${NAMESPACE}" != "default" ]; then
    echo -e "\nNote: Change the default namespace for kubectl to ${NAMESPACE} by doing:\n    kubectl config set-context --current --namespace=${NAMESPACE}\n"
  fi
}

function proxy_url() {
  PROXY_HOST=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  PROXY_PORT=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.spec.ports[?(@.protocol=="TCP")].port}')
  PROXY_URL="$PROXY_HOST:$PROXY_PORT"
  if [ "$PROXY_URL" != ":" ]; then
    echo -e "\n\nFusion 5 Gateway service exposed at: $PROXY_URL\n"
    echo -e "WARNING: This IP address is exposed to the WWW w/o SSL! This is done for demo purposes and ease of installation.\nYou are strongly encouraged to configure a K8s Ingress with TLS, see:\n   https://docs.microsoft.com/en-us/azure/aks/ingress-basic"
    echo -e "\nAfter configuring an Ingress, please change the 'proxy' service to be a ClusterIP instead of LoadBalancer\n"
    report_ns
  else
    echo -e "\n\nFailed to get Fusion Gateway service URL! Check console for previous errors.\n"
  fi
}

function ingress_setup() {

  export INGRESS_IP=$(kubectl --namespace "${ingress_namespace}" get service "nginx-ingress-controller-controller" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo -e "\n\nFusion 5 Gateway service exposed at: ${INGRESS_HOSTNAME}\n"
  echo -e "Please ensure that the public DNS record for ${INGRESS_HOSTNAME} is updated to point to ${INGRESS_IP}"
  echo -e "An SSL certificate will be automatically generated once the public DNS record has been updated, this may take up to an hour after DNS has updated to be issued"
}

kubectl rollout status deployment/${RELEASE}-query-pipeline -n ${NAMESPACE} --timeout=10s > /dev/null 2>&1
rollout_status=$?
if [ $rollout_status == 0 ]; then
  if [ "$UPGRADE" == "0" ]; then
    echo -e "\nLooks like Fusion is already running ..."
    proxy_url
    exit 0
  fi
fi

if [ "$UPGRADE" == "0" ]; then
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=${who_am_i}
fi

is_helm_v3=$(${helm} version --short | grep v3)

if [ "${is_helm_v3}" == "" ]; then
  # see if Tiller is deployed if using Helm V2
  kubectl rollout status deployment/tiller-deploy --timeout=10s -n kube-system > /dev/null 2>&1
  rollout_status=$?
  if [ $rollout_status != 0 ]; then
    echo -e "\nSetting up Helm Tiller ..."
    kubectl create serviceaccount --namespace kube-system tiller
    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    ${helm} init --service-account tiller --wait
    ${helm} version
  fi
else
  echo -e "Using Helm V3 ($is_helm_v3), no Tiller to install"
fi

lw_helm_repo=lucidworks

echo -e "\nAdding the Lucidworks chart repo to helm repo list"
helm repo list | grep "https://charts.lucidworks.com"
if [ $? ]; then
  ${helm} repo add ${lw_helm_repo} https://charts.lucidworks.com

fi

if [ ! -f $MY_VALUES ] && [ "$UPGRADE" != "1" ]; then

  CREATED_MY_VALUES=1
  SOLR_REPLICAS=3
  ZK_REPLICAS=3
  if [ "$NODE_COUNT" == "1" ]; then
    SOLR_REPLICAS=1
    ZK_REPLICAS=1
  elif [ "$NODE_COUNT" == "2" ]; then
    SOLR_REPLICAS=2
    ZK_REPLICAS=1
  fi

  tee $MY_VALUES << END
cx-ui:
  replicaCount: 1
  resources:
    limits:
      cpu: "200m"
      memory: 64Mi
    requests:
      cpu: "100m"
      memory: 64Mi

cx-api:
  replicaCount: 1
  volumeClaimTemplates:
    storageSize: "5Gi"

kafka:
  replicaCount: 1
  resources: {}
  kafkaHeapOptions: "-Xmx512m"

sql-service:
  enabled: false
  replicaCount: 0
  service:
    thrift:
      type: "ClusterIP"

solr:
  image:
    tag: 8.2.0
  updateStrategy:
    type: "RollingUpdate"
  javaMem: "-Xmx3g"
  volumeClaimTemplates:
    storageSize: "50Gi"
  replicaCount: ${SOLR_REPLICAS}
  resources: {}
  zookeeper:
    replicaCount: ${ZK_REPLICAS}
    resources: {}
    persistence:
      size: 15Gi
    env:
      ZK_HEAP_SIZE: 1G
      ZK_PURGE_INTERVAL: 1

ml-model-service:
  image:
    imagePullPolicy: "IfNotPresent"
  modelRepoImpl: ${ML_MODEL_STORE}
  fs:
    enabled: true

fusion-admin:
  readinessProbe:
    initialDelaySeconds: 180

fusion-indexing:
  readinessProbe:
    initialDelaySeconds: 180

query-pipeline:
  javaToolOptions: "-Dlogging.level.com.lucidworks.cloud=INFO"

END
  echo -e "\nCreated $MY_VALUES with default custom value overrides. Please save this file for customizing your Fusion installation and upgrading to a newer version.\n"
fi

${helm} repo update

ADDITIONAL_VALUES=""
if [ "${TLS_ENABLED}" == "1" ]; then
  TLS_VALUES="tls-values.yaml"
  ADDITIONAL_VALUES="${ADDITIONAL_VALUES} --values tls-values.yaml"
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
  apiVersion: certmanager.k8s.io/v1alpha1
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

if [ "$UPGRADE" == "1" ]; then

  if [ ! -f "${MY_VALUES}" ]; then
    echo -e "\nWARNING: Custom values file ${MY_VALUES} not found!\nYou need to provide the same custom values you provided when creating the cluster in order to upgrade.\n"
    exit 1
  fi
  VALUES_ARG="--values ${MY_VALUES}"

  if [ "${DRY_RUN}" == "" ]; then
    echo -e "\nUpgrading the Fusion 5 release ${RELEASE} in namespace ${NAMESPACE} to version ${CHART_VERSION} using ${VALUES_ARG} ${ADDITIONAL_VALUES}"
  else
    echo -e "\nSimulating an update of the Fusion ${RELEASE} installation into the ${NAMESPACE} namespace using ${VALUES_ARG} ${ADDITIONAL_VALUES}"
  fi
  if [ "$is_helm_v3" != "" ]; then
    ${helm} upgrade ${RELEASE} "${lw_helm_repo}/fusion" --timeout=180s --namespace "${NAMESPACE}" ${VALUES_ARG} ${ADDITIONAL_VALUES} --version ${CHART_VERSION}
  else
    ${helm} upgrade ${RELEASE} "${lw_helm_repo}/fusion" --timeout=180 --namespace "${NAMESPACE}" ${VALUES_ARG} ${ADDITIONAL_VALUES} --version ${CHART_VERSION}
  fi
  upgrade_status=$?
  if [ "${TLS_ENABLED}" == "1" ]; then
    ingress_setup
  else
    proxy_url
  fi
  exit $upgrade_status
fi

echo -e "\nInstalling Fusion 5.0 Helm chart ${CHART_VERSION} into namespace ${NAMESPACE} with release tag: ${RELEASE} using custom values from ${MY_VALUES}"

if [ -n "$CREATED_MY_VALUES" ]; then
  echo -e "\nNOTE: If this will be a long-running cluster for production purposes, you should save the ${MY_VALUES} file in version control.\n"
fi

if [ "$is_helm_v3" != "" ]; then
  if ! kubectl get namespace "${NAMESPACE}"; then
    kubectl create namespace "${NAMESPACE}"
  fi
  # looks like Helm V3 doesn't like the -n parameter for the release name anymore
  ${helm} install ${RELEASE} ${lw_helm_repo}/fusion --timeout=240s --namespace "${NAMESPACE}" --values "${MY_VALUES}" ${ADDITIONAL_VALUES} --version ${CHART_VERSION}
else
  ${helm} install ${lw_helm_repo}/fusion --timeout 240 --namespace "${NAMESPACE}" -n "${RELEASE}" --values "${MY_VALUES}" ${ADDITIONAL_VALUES} --version ${CHART_VERSION}
fi

kubectl rollout status deployment/${RELEASE}-api-gateway --timeout=600s --namespace "${NAMESPACE}"
kubectl rollout status deployment/${RELEASE}-fusion-admin --timeout=600s --namespace "${NAMESPACE}"

if [ "${TLS_ENABLED}" == "1" ]; then
  ingress_setup
else
  proxy_url
fi
