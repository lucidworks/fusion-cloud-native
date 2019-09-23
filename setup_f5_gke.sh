#!/bin/bash

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on GKE; optionally create a GKE cluster in the process\n"
  echo -e "\nUsage: $CMD -c <cluster> -r <release> -n <namespace> -p <project> -z <zone> -i <instance_type> --values <values> --create <mode> --upgrade --purge\n"
  echo -e "  -c          Name of the GKE cluster (required)\n"
  echo -e "  -p          GCP Project ID (required)\n"
  echo -e "  -r          Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n          Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  -z          GCP Zone to launch the cluster in, defaults to 'us-west1'\n"
  echo -e "  -b          GCS Bucket for storing ML models\n"
  echo -e "  -i          Instance type, defaults to 'n1-standard-4'\n"
  echo -e "  --version   Fusion Helm Chart version\n"
  echo -e "  --values    Custom values file containing config overrides; defaults to custom_fusion_values.yaml\n"
  echo -e "  --create    Create a cluster in GKE; provide the mode of the cluster to create, one of: demo, multi_az, node_pools\n"
  echo -e "  --upgrade   Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --purge     Uninstall and purge all Fusion objects from the specified namespace and cluster\n"
}

SCRIPT_CMD="$0"
GCLOUD_PROJECT=
GCLOUD_ZONE=us-west1
CLUSTER_NAME=
RELEASE=f5
NAMESPACE=default
MY_VALUES=${NAMESPACE}_fusion_values.yaml
UPGRADE=0
GCS_BUCKET=
CREATE_MODE=
PURGE=0
INSTANCE_TYPE="n1-standard-4"
CHART_VERSION="5.0.0"
SOLR_REPLICAS=3
ML_MODEL_STORE="fs"

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
            MY_VALUES=${NAMESPACE}_fusion_values.yaml
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
        -i)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -i parameter!"
              exit 1
            fi
            INSTANCE_TYPE="$2"
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
            MY_VALUES="$2"
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
        --purge)
            PURGE=1
            shift 1
        ;;
        -help|-usage)
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

# verify the user is logged in ...
who_am_i=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
if [ "$who_am_i" == "" ]; then
  echo -e "\nERROR: GCloud user unknown, please use: 'gcloud auth login <account>' before proceeding with this script!"
  exit 1
fi

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

gcloud config set compute/zone $GCLOUD_ZONE
gcloud config set project $GCLOUD_PROJECT

if [ "$PURGE" == "1" ]; then
  gcloud container clusters get-credentials $CLUSTER_NAME
  current=$(kubectl config current-context)
  read -p "Are you sure you want to purge the ${RELEASE} release from the ${NAMESPACE} in: $current? This operation cannot be undone! y/n " confirm
  if [ "$confirm" == "y" ]; then
    helm del --purge ${RELEASE}
    kubectl delete deployments -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete job ${RELEASE}-api-gateway --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=1s
    kubectl delete svc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=2s
    kubectl delete pvc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l release=${RELEASE} --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l app.kubernetes.io/instance=${RELEASE} --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
  fi
  exit 0
fi

gcloud beta container clusters list --filter=${CLUSTER_NAME} | grep ${CLUSTER_NAME} > /dev/null 2>&1
cluster_status=$?
if [ "$cluster_status" != "0" ]; then
  if [ "$CREATE_MODE" == "" ]; then
    CREATE_MODE="multi_az" # the default ...
  fi

  echo -e "\nLaunching GKE cluster ${CLUSTER_NAME} ($CREATE_MODE) in project ${GCLOUD_PROJECT} zone ${GCLOUD_ZONE} for deploying Lucidworks Fusion 5 ...\n"

  if [ "$CREATE_MODE" == "demo" ]; then
    SOLR_REPLICAS=1
    # have to cut off the zone part for the --subnetwork arg
    GCLOUD_REGION="$(cut -d'-' -f1 -f2 <<<"$GCLOUD_ZONE")"
    gcloud beta container --project "${GCLOUD_PROJECT}" clusters create "${CLUSTER_NAME}" --zone "${GCLOUD_ZONE}" \
      --no-enable-basic-auth --cluster-version "1.12.8-gke.10" --machine-type "${INSTANCE_TYPE}" --image-type "COS" \
      --disk-type "pd-standard" --disk-size "100" \
      --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes "1" --no-enable-cloud-logging --no-enable-cloud-monitoring --enable-ip-alias \
      --network "projects/${GCLOUD_PROJECT}/global/networks/default" \
      --subnetwork "projects/${GCLOUD_PROJECT}/regions/${GCLOUD_REGION}/subnetworks/default" \
      --default-max-pods-per-node "110" --enable-autoscaling --min-nodes "1" --max-nodes "2" \
      --addons HorizontalPodAutoscaling,HttpLoadBalancing --no-enable-autoupgrade --enable-autorepair
  elif [ "$CREATE_MODE" == "multi_az" ]; then
    gcloud beta container --project "${GCLOUD_PROJECT}" clusters create "${CLUSTER_NAME}" --region "${GCLOUD_ZONE}" \
      --no-enable-basic-auth --cluster-version "1.12.8-gke.10" --machine-type "${INSTANCE_TYPE}" \
      --image-type "COS" --disk-type "pd-standard" --disk-size "100" --metadata disable-legacy-endpoints=true \
      --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes "1" --enable-cloud-logging --enable-cloud-monitoring --enable-ip-alias \
      --network "projects/${GCLOUD_PROJECT}/global/networks/default" \
      --subnetwork "projects/${GCLOUD_PROJECT}/regions/${GCLOUD_ZONE}/subnetworks/default" \
      --default-max-pods-per-node "110" --enable-autoscaling --min-nodes "1" --max-nodes "2" \
      --addons HorizontalPodAutoscaling,HttpLoadBalancing --no-enable-autoupgrade --enable-autorepair
  else
    echo -e "\nNo --create arg provided, assuming you want a multi-AZ, multi-NodePool cluster ..."
    echo -e "Clusters with multiple NodePools not supported by this script yet! Please create the cluster and define the NodePools manually.\n"
    exit 1
  fi

  echo -e "\nCluster '${CLUSTER_NAME}' deployed ... testing if it is healthy"
  gcloud beta container clusters list --filter=${CLUSTER_NAME} | grep ${CLUSTER_NAME}
  cluster_status=$?
  if [ "$cluster_status" != "0" ]; then
    echo -e "\nERROR: Status of GKE cluster ${CLUSTER_NAME} is suspect, check the Google Cloud console before proceeding!\n"
    exit 1
  fi
else
  if [ "$UPGRADE" == "0" ]; then
    echo -e "\nGKE Cluster '${CLUSTER_NAME}' already exists, proceeding with Fusion 5 install ...\n"
  fi
fi

gcloud container clusters get-credentials $CLUSTER_NAME
kubectl config current-context

function proxy_url() {
  export PROXY_HOST=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  export PROXY_PORT=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.spec.ports[?(@.protocol=="TCP")].port}')
  export PROXY_URL=$PROXY_HOST:$PROXY_PORT
  echo -e "\n\nFusion 5 Gateway service exposed at: $PROXY_URL\n"
  echo -e "WARNING: This IP address is exposed to the WWW w/o SSL! This is done for demo purposes and ease of installation.\nYou are strongly encouraged to configure a K8s Ingress with TLS, see:\n   https://cloud.google.com/kubernetes-engine/docs/tutorials/http-balancer"
  echo -e "\nAfter configuring an Ingress, please change the 'proxy' service to be a ClusterIP instead of LoadBalancer\n"
}

if [ "$GCS_BUCKET" != "" ]; then
  echo -e "Creating GCS bucket: $GCS_BUCKET"
  gsutil mb gs://${GCS_BUCKET}
  ML_MODEL_STORE="gcs"
fi

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
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account)
fi

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

lw_helm_repo=lucidworks

echo -e "\nAdding the Lucidworks chart repo to helm repo list"
helm repo list | grep "https://charts.lucidworks.com"
if [ $? ]; then
  helm repo add ${lw_helm_repo} https://charts.lucidworks.com
fi

if [ ! -f $MY_VALUES ]; then
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
    replicaCount: ${SOLR_REPLICAS}
    resources: {}
    env:
      ZK_HEAP_SIZE: 1G

ml-model-service:
  modelRepository:
    impl: ${ML_MODEL_STORE}
    gcs:
      bucketName: ${GCS_BUCKET}
      baseDirectoryName: dev

fusion-admin:
  readinessProbe:
    initialDelaySeconds: 180

fusion-indexing:
  readinessProbe:
    initialDelaySeconds: 180

query-pipeline:
  javaToolOptions: "-Dlogging.level.com.lucidworks.cloud=INFO"

END
fi

helm repo update

if [ "$UPGRADE" == "1" ]; then
  echo -e "\nUpgrading the Fusion 5.0 release  ${RELEASE} in namespace ${NAMESPACE} using custom values from ${MY_VALUES}"
  helm upgrade ${RELEASE} "${lw_helm_repo}/fusion" --timeout 180 --namespace "${NAMESPACE}" --values "${MY_VALUES}" --version ${CHART_VERSION}
  upgrade_status=$?
  proxy_url
  exit $upgrade_status
fi

echo -e "\nInstalling Fusion 5.0 Helm chart ${CHART_VERSION} into namespace ${NAMESPACE} with release tag: ${RELEASE} using custom values from ${MY_VALUES}"
helm install --timeout 240 --namespace "${NAMESPACE}" -n "${RELEASE}" --values "${MY_VALUES}" ${lw_helm_repo}/fusion --version ${CHART_VERSION}
kubectl rollout status deployment/${RELEASE}-api-gateway --timeout=600s --namespace "${NAMESPACE}"
kubectl rollout status deployment/${RELEASE}-fusion-admin --timeout=600s --namespace "${NAMESPACE}"

proxy_url
