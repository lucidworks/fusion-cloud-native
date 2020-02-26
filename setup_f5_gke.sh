#!/bin/bash

INSTANCE_TYPE="n1-standard-4"
CHART_VERSION="5.0.3-3"
GKE_MASTER_VERSION="-"
NODE_POOL="cloud.google.com/gke-nodepool: default-pool"
PROMETHEUS="install"
SCRIPT_CMD="$0"
GCLOUD_PROJECT=
GCLOUD_REGION=us-west1
CLUSTER_NAME=
NAMESPACE=default
UPGRADE=0
GCS_BUCKET=
CREATE_MODE=
PURGE=0
FORCE=0
CUSTOM_MY_VALUES=()
MY_VALUES=()
ML_MODEL_STORE="fusion"
DRY_RUN=""
SOLR_REPLICAS=1
SOLR_DISK_GB=50

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on GKE; optionally create a GKE cluster in the process"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c            Name of the GKE cluster (required)\n"
  echo -e "  -p            GCP Project ID (required)\n"
  echo -e "  -r            Helm release name for installing Fusion 5; defaults to the namespace, see -n option\n"
  echo -e "  -n            Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  -z            GCP Region to launch the cluster in, defaults to 'us-west1'\n"
  echo -e "  -i            Instance type, defaults to '${INSTANCE_TYPE}'\n"
  echo -e "  -t            Enable TLS for the ingress, requires a hostname to be specified with -h\n"
  echo -e "  -h            Hostname for the ingress to route requests to this Fusion cluster. If used with the -t parameter,"
  echo -e "                then the hostname must be a public DNS record that can be updated to point to the IP of the LoadBalancer\n"
  echo -e "  --prometheus  Enable Prometheus and Grafana for monitoring Fusion services, pass one of: install, provided, none;"
  echo -e "                defaults to 'install' which installs Prometheus and Grafana from the stable Helm repo,"
  echo -e "                'provided' enables pod annotations on Fusion services to work with Prometheus but does not install anything\n"
  echo -e "  --gke         GKE Master version; defaults to '-' which uses the default version for the selected region / zone (differs between zones)\n"
  echo -e "  --version     Fusion Helm Chart version; defaults to the latest release from Lucidworks, such as ${CHART_VERSION}\n"
  echo -e "  --values      Custom values file containing config overrides; defaults to gke_<cluster>_<namespace>_fusion_values.yaml"
  echo -e "                (can be specified multiple times to add additional yaml files, see example-values/*.yaml)\n"
  echo -e "  --num-solr    Number of Solr pods to deploy, defaults to 1\n"
  echo -e "  --node-pool   Node pool label to assign pods to specific nodes, this option is only useful for existing clusters where you defined a custom node pool;"
  echo -e "                defaults to '${NODE_POOL}', wrap the arg in double-quotes\n"
  echo -e "  --create      Create a cluster in GKE; provide the mode of the cluster to create, one of: demo, multi_az\n"
  echo -e "  --upgrade     Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --dry-run     Perform a dry-run of the upgrade to see what would change\n"
  echo -e "  --purge       Uninstall and purge all Fusion objects from the specified namespace and cluster."
  echo -e "                Be careful! This operation cannot be undone.\n"
  echo -e "  --force       Force upgrade or purge a deployment if your account is not the value 'owner' label on the namespace\n"
}

if [ $# -gt 0 ]; then
  while true; do
    case "$1" in
        -b)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -c parameter!"
              exit 1
            fi
            echo -e "\nWARNING: The GCS bucket parameter is no longer supported by this script!\n"
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
            GCLOUD_REGION="$2"
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
        --prometheus)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --prometheus parameter!"
              exit 1
            fi
            PROMETHEUS="$2"
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

if [ "${TLS_ENABLED}" == "1" ] && [ -z "${INGRESS_HOSTNAME}" ]; then
  print_usage "$SCRIPT_CMD" "if -t is specified -h must be specified and a domain that you can update to add an A record to point to the GCP Loadbalancer IP"
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

current_value=$(gcloud config get-value compute/zone)
if [ "${current_value}" != "${GCLOUD_ZONE}" ]; then
  gcloud config set compute/zone "${GCLOUD_REGION}"
fi
current_value=$(gcloud config get-value project)
if [ "${current_value}" != "${GCLOUD_PROJECT}" ]; then
  gcloud config set project "${GCLOUD_PROJECT}"
fi

gcloud beta container clusters list --filter="${CLUSTER_NAME}" | grep "${CLUSTER_NAME}" > /dev/null 2>&1
cluster_status=$?
if [ "$cluster_status" != "0" ]; then
  if [ "$CREATE_MODE" == "" ]; then
    CREATE_MODE="multi_az" # the default ...
  fi

  echo -e "\nLaunching $CREATE_MODE GKE cluster ${CLUSTER_NAME} (K8s Master: ${GKE_MASTER_VERSION}) in project ${GCLOUD_PROJECT} region ${GCLOUD_REGION} for deploying Lucidworks Fusion 5 ...\n"

  if [ "$CREATE_MODE" == "demo" ]; then

    if [ "$GCLOUD_REGION" == "us-west1" ]; then
      GCLOUD_ZONE="us-west1-a"
    fi

    gcloud beta container --project "${GCLOUD_PROJECT}" clusters create "${CLUSTER_NAME}" --region "${GCLOUD_REGION}" --zone "${GCLOUD_ZONE}" \
      --no-enable-basic-auth \
      --cluster-version ${GKE_MASTER_VERSION} \
      --machine-type ${INSTANCE_TYPE} \
      --image-type "COS" \
      --disk-type "pd-standard" --disk-size "100" \
      --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes "1" \
      --no-enable-cloud-logging \
      --no-enable-cloud-monitoring \
      --enable-ip-alias \
      --network "projects/${GCLOUD_PROJECT}/global/networks/default" \
      --subnetwork "projects/${GCLOUD_PROJECT}/regions/${GCLOUD_REGION}/subnetworks/default" \
      --default-max-pods-per-node "110" \
      --enable-autoscaling --min-nodes "0" --max-nodes "3" \
      --addons HorizontalPodAutoscaling,HttpLoadBalancing \
      --no-enable-autoupgrade --enable-autorepair
  elif [ "$CREATE_MODE" == "multi_az" ]; then
    gcloud beta container --project "${GCLOUD_PROJECT}" clusters create "${CLUSTER_NAME}" --region "${GCLOUD_REGION}" --zone "${GCLOUD_ZONE}" \
      --no-enable-basic-auth \
      --cluster-version ${GKE_MASTER_VERSION} \
      --machine-type ${INSTANCE_TYPE} \
      --image-type "COS" \
      --disk-type "pd-standard" --disk-size "100" \
      --metadata disable-legacy-endpoints=true \
      --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes "1" \
      --enable-stackdriver-kubernetes \
      --enable-ip-alias \
      --network "projects/${GCLOUD_PROJECT}/global/networks/default" \
      --subnetwork "projects/${GCLOUD_PROJECT}/regions/${GCLOUD_REGION}/${GCLOUD_ZONE}/subnetworks/default" \
      --default-max-pods-per-node "110" \
      --enable-autoscaling --min-nodes "0" --max-nodes "3" \
      --addons HorizontalPodAutoscaling,HttpLoadBalancing \
      --no-enable-autoupgrade --enable-autorepair
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

INGRESS_VALUES=""
if [ "${TLS_ENABLED}" == "1" ]; then

  # need to create the namespace if it doesn't exist yet
  if ! kubectl get namespace "${NAMESPACE}" > /dev/null 2>&1; then
    if [ "${UPGRADE}" != "1" ]; then
      kubectl create namespace "${NAMESPACE}"
      kubectl label namespace "${NAMESPACE}" "owner=${OWNER_LABEL}"
      echo -e "\nCreated namespace ${NAMESPACE} with owner label ${OWNER_LABEL}\n"
    fi
  fi

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
  INGRESS_VALUES="${INGRESS_VALUES} --values tls-values.yaml"
  tee "${TLS_VALUES}" << END
api-gateway:
  service:
    type: "NodePort"
  ingress:
    enabled: true
    host: "${INGRESS_HOSTNAME}"
    path: "/*"
    tls:
      enabled: true
    annotations:
      "networking.gke.io/managed-certificates": "${RELEASE}-managed-certificate"
      "kubernetes.io/ingress.class": "gce"

END
fi

DEFAULT_MY_VALUES="gke_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"

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

    source ./customize_fusion_values.sh $DEFAULT_MY_VALUES -c $CLUSTER_NAME -r $RELEASE --provider "gke" --prometheus $PROMETHEUS_ON \
      --num-solr $SOLR_REPLICAS --solr-disk-gb $SOLR_DISK_GB --node-pool "${NODE_POOL}"
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

# for debug only
#echo -e "Calling setup_f5_k8s.sh with: ${VALUES_STRING}${INGRESS_ARG}${UPGRADE_ARGS}"
source ./setup_f5_k8s.sh -c $CLUSTER_NAME -r "${RELEASE}" --provider "gke" -n "${NAMESPACE}" --node-pool "${NODE_POOL}" \
  --version ${CHART_VERSION} --prometheus ${PROMETHEUS} ${VALUES_STRING}${INGRESS_ARG}${UPGRADE_ARGS}
setup_result=$?
exit $setup_result
