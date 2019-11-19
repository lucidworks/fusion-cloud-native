#!/bin/bash

INSTANCE_TYPE="n1-standard-4"
CHART_VERSION="5.0.2-7"
GKE_MASTER_VERSION="-"
NODE_POOL="cloud.google.com/gke-nodepool: default-pool"
SOLR_REPLICAS=1

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on GKE; optionally create a GKE cluster in the process"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c          Name of the GKE cluster (required)\n"
  echo -e "  -p          GCP Project ID (required)\n"
  echo -e "  -r          Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n          Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  -z          GCP Zone to launch the cluster in, defaults to 'us-west1'\n"
  echo -e "  -b          GCS Bucket for storing ML models\n"
  echo -e "  -i          Instance type, defaults to '${INSTANCE_TYPE}'\n"
  echo -e "  -t          Enable TLS for the ingress, requires a hostname to be specified with -h\n"
  echo -e "  -h          Hostname for the ingress to route requests to this Fusion cluster. If used with the -t parameter,\n              then the hostname must be a public DNS record that can be updated to point to the IP of the LoadBalancer\n"
  echo -e "  --gke       GKE Master version; defaults to '-' which uses the default version for the selected region / zone (differs between zones)\n"
  echo -e "  --version   Fusion Helm Chart version; defaults to the latest release from Lucidworks, such as ${CHART_VERSION}\n"
  echo -e "  --values    Custom values file containing config overrides; defaults to <release>_<namespace>_fusion_values.yaml (can be specified multiple times)\n"
  echo -e "  --num-solr  Number of Solr pods to deploy, defaults to 1\n"
  echo -e "  --node-pool Node pool label to assign pods to specific nodes; defaults to '${NODE_POOL}', wrap the arg in double-quotes\n"
  echo -e "  --create    Create a cluster in GKE; provide the mode of the cluster to create, one of: demo, multi_az\n"
  echo -e "  --upgrade   Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --dry-run   Perform a dry-run of the upgrade to see what would change\n"
  echo -e "  --purge     Uninstall and purge all Fusion objects from the specified namespace and cluster.\n              Be careful! This operation cannot be undone.\n"
  echo -e "  --force     Force upgrade or purge a deployment if your account is not the value 'owner' label on the namespace"
}

SCRIPT_CMD="$0"
GCLOUD_PROJECT=
GCLOUD_ZONE=us-west1
CLUSTER_NAME=
RELEASE=f5
NAMESPACE=default
UPGRADE=0
GCS_BUCKET=
CREATE_MODE=
PURGE=0
FORCE=0
ML_MODEL_STORE="fs"
CUSTOM_MY_VALUES=()
MY_VALUES=()
DRY_RUN=""

if [ $# -gt 0 ]; then
  while true; do
    case "$1" in
        -b)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -b parameter!"
              exit 1
            fi
            GCS_BUCKET="$2"
            shift 2
        ;;
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
            GCLOUD_PROJECT="$2"
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
            GCLOUD_ZONE="$2"
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
        --gke)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --gke parameter!"
              exit 1
            fi
            GKE_MASTER_VERSION="$2"
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
        --create)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --create parameter!"
              exit 1
            fi
            CREATE_MODE="$2"
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

if [ "$CREATE_MODE" != "" ] && [ "$UPGRADE" == "1" ]; then
  print_usage "$SCRIPT_CMD" "Must specify either the --create or --upgrade options but not both!"
  exit 1
fi

if [ "$CLUSTER_NAME" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the GKE cluster name using: -c <cluster>"
  exit 1
fi

if [ "$GCLOUD_PROJECT" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the GCP project name using: -p <project>"
  exit 1
fi

DEFAULT_MY_VALUES="gke_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"

if [ "${TLS_ENABLED}" == "1" ] && [ -z "${INGRESS_HOSTNAME}" ]; then
  print_usage "$SCRIPT_CMD" "if -t is specified -h must be specified and a domain that you can update to add an A record to point to the GCP Loadbalancer IP"
  exit 1
fi

gcloud --version > /dev/null 2<&1
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install GCloud command line tools! See https://cloud.google.com/sdk/docs/quickstarts"
  exit 1
fi

# verify the user is logged in ...
who_am_i=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
if [ "$who_am_i" == "" ]; then
  echo -e "\nERROR: GCloud user unknown, please use: 'gcloud auth login <account>' before proceeding with this script!"
  exit 1
fi

OWNER_LABEL="${who_am_i//@/-}"
echo -e "\nLogged in as: $who_am_i\n"

hash kubectl
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install kubectl before proceeding with this script! For GKE, see: https://cloud.google.com/sdk/docs/"
  exit 1
fi

hash helm
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install helm before proceeding with this script! See: https://helm.sh/docs/using_helm/#quickstart"
  exit 1
fi

gcloud config set compute/zone "${GCLOUD_ZONE}"
gcloud config set project "${GCLOUD_PROJECT}"

gcloud beta container clusters list --filter="${CLUSTER_NAME}" | grep "${CLUSTER_NAME}" > /dev/null 2>&1

cluster_status=$?
if [ "$cluster_status" != "0" ]; then
  if [ "$CREATE_MODE" == "" ]; then
    CREATE_MODE="multi_az" # the default ...
  fi

  echo -e "\nLaunching $CREATE_MODE GKE cluster ${CLUSTER_NAME} (gke: ${GKE_MASTER_VERSION}) in project ${GCLOUD_PROJECT} zone ${GCLOUD_ZONE} for deploying Lucidworks Fusion 5 ...\n"

  if [ "$CREATE_MODE" == "demo" ]; then

    if [ "$GCLOUD_ZONE" == "us-west1" ]; then
      echo -e "\nWARNING: Must provide a specific zone for demo clusters instead of a region, such as us-west1-a!\n"
      GCLOUD_ZONE="us-west1-a"
    fi

    # have to cut off the zone part for the --subnetwork arg
    GCLOUD_REGION="$(cut -d'-' -f1 -f2 <<<"$GCLOUD_ZONE")"

    gcloud beta container --project "${GCLOUD_PROJECT}" clusters create "${CLUSTER_NAME}" --zone "${GCLOUD_ZONE}" \
      --no-enable-basic-auth --cluster-version ${GKE_MASTER_VERSION} --machine-type ${INSTANCE_TYPE} --image-type "COS" \
      --disk-type "pd-standard" --disk-size "100" \
      --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes "1" --no-enable-cloud-logging --no-enable-cloud-monitoring --enable-ip-alias \
      --network "projects/${GCLOUD_PROJECT}/global/networks/default" \
      --subnetwork "projects/${GCLOUD_PROJECT}/regions/${GCLOUD_REGION}/subnetworks/default" \
      --default-max-pods-per-node "110" --enable-autoscaling --min-nodes "0" --max-nodes "5" \
      --addons HorizontalPodAutoscaling,HttpLoadBalancing --no-enable-autoupgrade --enable-autorepair
  elif [ "$CREATE_MODE" == "multi_az" ]; then
    gcloud beta container --project "${GCLOUD_PROJECT}" clusters create "${CLUSTER_NAME}" --region "${GCLOUD_ZONE}" \
      --no-enable-basic-auth --cluster-version ${GKE_MASTER_VERSION} --machine-type ${INSTANCE_TYPE} \
      --image-type "COS" --disk-type "pd-standard" --disk-size "100" --metadata disable-legacy-endpoints=true \
      --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes "1" --enable-cloud-logging --enable-cloud-monitoring --enable-ip-alias \
      --network "projects/${GCLOUD_PROJECT}/global/networks/default" \
      --subnetwork "projects/${GCLOUD_PROJECT}/regions/${GCLOUD_ZONE}/subnetworks/default" \
      --default-max-pods-per-node "110" --enable-autoscaling --min-nodes "0" --max-nodes "5" \
      --addons HorizontalPodAutoscaling,HttpLoadBalancing --no-enable-autoupgrade --enable-autorepair
  else
    echo -e "\nNo --create arg provided, assuming you want a multi-AZ, multi-NodePool cluster ..."
    echo -e "Clusters with multiple NodePools not supported by this script yet! Please create the cluster and define the NodePools manually.\n"
    exit 1
  fi

  echo -e "\nCluster '${CLUSTER_NAME}' deployed ... testing if it is healthy"
  gcloud beta container clusters list --filter="${CLUSTER_NAME}" | grep "${CLUSTER_NAME}"
  cluster_status=$?
  if [ "$cluster_status" != "0" ]; then
    echo -e "\nERROR: Status of GKE cluster ${CLUSTER_NAME} is suspect, check the Google Cloud console before proceeding!\n"
    exit 1
  fi

else
  echo -e "\nCluster '${CLUSTER_NAME}' exists, starting to install Lucidworks Fusion"
fi

gcloud container clusters get-credentials $CLUSTER_NAME
current=$(kubectl config current-context)

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
  echo -e "Using Helm V3 ($is_helm_v3), no Tiller to install"
fi


if ! kubectl get namespace "${NAMESPACE}" > /dev/null; then
  kubectl create namespace "${NAMESPACE}"
  kubectl label namespace "${NAMESPACE}" "owner=${OWNER_LABEL}"
fi

if [ "${UPGRADE}" == "1" ]; then
    # Check if the owner label on the namespace is the same as we are, so we cannot
    # accidentally upgrade a release from someone elses namespace
    namespace_owner=$(kubectl get namespace "${NAMESPACE}" -o 'jsonpath={.metadata.labels.owner}')
    if [ "${namespace_owner}" != "${OWNER_LABEL}" ] && [ "${FORCE}" != "1" ]; then
      echo -e "Namespace "${NAMESPACE}" is owned by: ${namespace_owner}, by we are: "${OWNER_LABEL}" please provide the --force parameter if you are sure you wish to upgrade this namespace"
      exit 1
    fi
elif [ "$PURGE" == "1" ]; then
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
      helm delete ${RELEASE}
    else
      helm del --purge ${RELEASE}
    fi
    kubectl delete deployments -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete job ${RELEASE}-api-gateway --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=1s
    kubectl delete svc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=2s
    kubectl delete pvc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l release=${RELEASE} --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l app.kubernetes.io/instance=${RELEASE} --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete serviceaccount --namespace "${NAMESPACE}" ${RELEASE}-api-gateway-jks-create
  fi
  exit 0
else
  # Check if there is already a release for helm with the release name that we want
  if helm status "${RELEASE}" > /dev/null 2>&1 ; then
      echo -e "\nERROR: There is already a release with name: ${RELEASE} installed in the cluster, please choose a different release name or upgrade the release\n"
      exit 1
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
  export PROXY_HOST=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
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
  report_ns
}

if [ "$GCS_BUCKET" != "" ]; then
  echo -e "Creating GCS bucket: $GCS_BUCKET"
  gsutil mb gs://${GCS_BUCKET}
  mb_outcome=$?
  if [ "$mb_outcome" == "0" ]; then
    GCP_SERVICE_ACCOUNT_ID=$(gcloud projects list --filter="${GCLOUD_PROJECT}" --format="value(PROJECT_NUMBER)")
    GCP_SERVICE_ACCOUNT="${GCP_SERVICE_ACCOUNT_ID}-compute@developer.gserviceaccount.com"
    echo -e "Granting default GCP service account ${GCP_SERVICE_ACCOUNT} access to GCS bucket: gs://${GCS_BUCKET}"
    gsutil bucketpolicyonly set on gs://${GCS_BUCKET}
    gsutil iam ch serviceAccount:${GCP_SERVICE_ACCOUNT}:roles/storage.objectAdmin gs://${GCS_BUCKET}
  fi
  ML_MODEL_STORE="gcs"
fi

lw_helm_repo=lucidworks

if ! helm repo list | grep -q "https://charts.lucidworks.com"; then
  echo -e "\nAdding the Lucidworks chart repo to helm repo list"
  helm repo add ${lw_helm_repo} https://charts.lucidworks.com
fi

#If no custom values are passed, and we are not updating
if [ -z $CUSTOM_MY_VALUES ] && [ "$UPGRADE" != "1" ]; then
  if [ ! -f "${DEFAULT_MY_VALUES}" ]; then

    CREATED_MY_VALUES=1

    tee $DEFAULT_MY_VALUES << END
sql-service:
  enabled: false
  nodeSelector:
    ${NODE_POOL}
  replicaCount: 0
  service:
    thrift:
      type: "ClusterIP"

solr:
  nodeSelector:
    ${NODE_POOL}
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
    nodeSelector:
      ${NODE_POOL}
    replicaCount: ${SOLR_REPLICAS}
    persistence:
      size: 15Gi
    resources: {}
    env:
      ZK_HEAP_SIZE: 1G
      ZK_PURGE_INTERVAL: 1

ml-model-service:
  image:
    imagePullPolicy: "IfNotPresent"
  nodeSelector:
    ${NODE_POOL}
  modelRepoImpl: ${ML_MODEL_STORE}
  gcsBucketName: ${GCS_BUCKET}
  gcsBaseDirectoryName: ${RELEASE}

fusion-admin:
  nodeSelector:
    ${NODE_POOL}
  readinessProbe:
    initialDelaySeconds: 180

fusion-indexing:
  nodeSelector:
    ${NODE_POOL}
  readinessProbe:
    initialDelaySeconds: 180

query-pipeline:
  nodeSelector:
    ${NODE_POOL}
  javaToolOptions: "-Dlogging.level.com.lucidworks.cloud=INFO"

admin-ui:
  nodeSelector:
    ${NODE_POOL}

api-gateway:
  nodeSelector:
    ${NODE_POOL}

auth-ui:
  nodeSelector:
    ${NODE_POOL}

classic-rest-service:
  nodeSelector:
    ${NODE_POOL}

devops-ui:
  nodeSelector:
    ${NODE_POOL}

fusion-resources:
  nodeSelector:
    ${NODE_POOL}

insights:
  nodeSelector:
    ${NODE_POOL}

job-launcher:
  nodeSelector:
    ${NODE_POOL}

job-rest-server:
    ${NODE_POOL}

logstash:
  nodeSelector:
    ${NODE_POOL}

rest-service:
  nodeSelector:
    ${NODE_POOL}

rpc-service:
  nodeSelector:
    ${NODE_POOL}

rules-ui:
  nodeSelector:
    ${NODE_POOL}

webapps:
  nodeSelector:
    ${NODE_POOL}

END

    echo -e "\nCreated $DEFAULT_MY_VALUES with default custom value overrides. Please save this file for customizing your Fusion installation and upgrading to a newer version.\n"
  else
    echo -e "\nValues file $DEFAULT_MY_VALUES already exists, using this values file.\n"
  fi
  MY_VALUES=( ${DEFAULT_MY_VALUES} )
fi

if [ ! -z "${CUSTOM_MY_VALUES[*]}" ]; then
  MY_VALUES=(${CUSTOM_MY_VALUES[@]})
fi

helm repo update

ADDITIONAL_VALUES=""
if [ "${TLS_ENABLED}" == "1" ]; then
  cat <<EOF | kubectl -n "${NAMESPACE}" apply -f -
apiVersion: networking.gke.io/v1beta1
kind: ManagedCertificate
metadata:
  name: "${RELEASE}-managed-certificate"
spec:
  domains:
  - "${INGRESS_HOSTNAME}"
EOF

  TLS_VALUES="tls-values.yaml"
  ADDITIONAL_VALUES="${ADDITIONAL_VALUES} --values tls-values.yaml"
  tee "${TLS_VALUES}" << END
api-gateway:
  service:
    type: "NodePort"
  ingress:
    enabled: true
    host: "${INGRESS_HOSTNAME}"
    tls:
      enabled: true
    annotations:
      "networking.gke.io/managed-certificates": "${RELEASE}-managed-certificate"
      "kubernetes.io/ingress.class": "gce"

END
fi

if [ "$UPGRADE" == "1" ]; then
  VALUES_STRING=""
  for v in "${MY_VALUES[@]}"; do
    if [ ! -f "${v}" ]; then
      echo -e "\nWARNING: Custom values file ${v} not found!\nYou need to provide the same custom values you provided when creating the cluster in order to upgrade.\n"
      exit 1
    fi
    VALUES_STRING="${VALUES_STRING} --values ${v}"
  done

  if [ "${DRY_RUN}" == "" ]; then
    echo -e "\nUpgrading the Fusion 5 release ${RELEASE} in namespace ${NAMESPACE} to version ${CHART_VERSION} with custom values from ${MY_VALUES[*]} ${ADDITIONAL_VALUES}"
  else
    echo -e "\nSimulating an update of the Fusion ${RELEASE} installation into the ${NAMESPACE} namespace with custom values from ${MY_VALUES[*]} ${ADDITIONAL_VALUES}"
  fi

  helm upgrade ${RELEASE} "${lw_helm_repo}/fusion" --namespace "${NAMESPACE}" ${VALUES_STRING} ${ADDITIONAL_VALUES} ${DRY_RUN} --version "${CHART_VERSION}"
  upgrade_status=$?
  if [ "${TLS_ENABLED}" == "1" ]; then
    ingress_setup
  else
    proxy_url
  fi
  exit $upgrade_status
fi

echo -e "\nInstalling Fusion 5.0 Helm chart ${CHART_VERSION} into namespace ${NAMESPACE} with release tag: ${RELEASE} using custom values from ${MY_VALUES[*]}"

VALUES_STRING=""
for v in "${MY_VALUES[@]}"; do
  if [ ! -f "${v}" ]; then
    echo -e "\nWARNING: Custom values file ${v} not found!\nPlease check the path to the custom values file is correct.\n"
    exit 1
  fi
  VALUES_STRING="${VALUES_STRING} --values ${v}"
done

if [ -n "$CREATED_MY_VALUES" ]; then
  echo -e "\nNOTE: If this will be a long-running cluster for production purposes, you should save the ${DEFAULT_MY_VALUES} file in version control.\n"
fi

# wait up to 60s to see the metrics server online
metrics_deployment=$(kubectl get deployment -n kube-system | grep metrics-server | cut -d ' ' -f1 -)
kubectl rollout status deployment/${metrics_deployment} --timeout=60s --namespace "kube-system"

# let's exit immediately if the helm install command fails
set -e
if [ "$is_helm_v3" != "" ]; then
  if ! kubectl get namespace "${NAMESPACE}"; then
    kubectl create namespace "${NAMESPACE}"
  fi
  # looks like Helm V3 doesn't like the -n parameter for the release name anymore
  helm install "${RELEASE}" ${lw_helm_repo}/fusion --timeout=240s --namespace "${NAMESPACE}" ${VALUES_STRING} ${ADDITIONAL_VALUES} --version "${CHART_VERSION}"
else
  helm install ${lw_helm_repo}/fusion --timeout 240 --namespace "${NAMESPACE}" -n "${RELEASE}" ${VALUES_STRING} ${ADDITIONAL_VALUES} --version "${CHART_VERSION}"
fi
set +e

kubectl rollout status deployment/${RELEASE}-api-gateway --timeout=600s --namespace "${NAMESPACE}"
kubectl rollout status deployment/${RELEASE}-fusion-admin --timeout=600s --namespace "${NAMESPACE}"

if [ "${TLS_ENABLED}" == "1" ]; then
  ingress_setup
else
  proxy_url
fi
