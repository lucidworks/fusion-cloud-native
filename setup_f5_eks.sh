#!/bin/bash

INSTANCE_TYPE="m5.2xlarge"
CHART_VERSION="5.0.2"
NODE_POOL="alpha.eksctl.io/nodegroup-name: standard-workers"
SOLR_REPLICAS=1
PROMETHEUS="install"
SCRIPT_CMD="$0"
AWS_ACCOUNT=
REGION=us-west-2
CLUSTER_NAME=
RELEASE=f5
NAMESPACE=default
UPGRADE=0
CREATE_MODE=
PURGE=0
FORCE=0
AMI="auto"
CUSTOM_MY_VALUES=()
MY_VALUES=()
ML_MODEL_STORE="fusion"
DRY_RUN=""
SOLR_DISK_GB=50

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on EKS; optionally create a EKS cluster in the process. We are using 1 vpc and 2 subnets from different AZs\n"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c          Name of the EKS cluster (required)\n"
  echo -e "  -p          AWS_ACCOUNT - profile (required)\n"
  echo -e "  -r          Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n          Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  -z          AWS Region to launch the cluster in, defaults to 'us-west-2'\n"
  echo -e "  -i          Instance type, defaults to 'm5.2xlarge'\n"
  echo -e "  -a          AMI to use for the nodes, defaults to 'auto'\n"
  echo -e "  --prometheus  Enable Prometheus and Grafana for monitoring Fusion services, pass one of: install, provided, none;"
  echo -e "                defaults to 'install' which installs Prometheus and Grafana from the stable Helm repo,"
  echo -e "                'provided' enables pod annotations on Fusion services to work with Prometheus but does not install anything\n"
  echo -e "  --version   Fusion Helm Chart version, defaults to ${CHART_VERSION}\n"
  echo -e "  --values    Custom values file containing config overrides; defaults to eks_<cluster>_<release>_fusion_values.yaml  (can be specified multiple times)\n"
  echo -e "  --num-solr    Number of Solr pods to deploy, defaults to 1\n"
  echo -e "  --node-pool   Node pool label to assign pods to specific nodes, this option is only useful for existing clusters where you defined a custom node pool;"
  echo -e "                defaults to '${NODE_POOL}', wrap the arg in double-quotes\n"
  echo -e "  --create    Create a cluster in EKS; provide the mode of the cluster to create, one of: demo\n"
  echo -e "  --upgrade   Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --dry-run     Perform a dry-run of the upgrade to see what would change\n"
  echo -e "  --purge     Uninstall and purge all Fusion objects from the specified namespace and cluster\n"
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
        -p)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -p parameter!"
              exit 1
            fi
            AWS_ACCOUNT="$2"
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
            REGION="$2"
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
        -a)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -a parameter!"
              exit 1
            fi
            AMI="$2"
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

#if [ "$CREATE_MODE" != "" ] && [ "$UPGRADE" == "1" ]; then
#  print_usage "$SCRIPT_CMD" "Must specify either the --create or --upgrade options but not both!"
#  exit 1
#fi

if [ "$CLUSTER_NAME" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the EKS cluster name using: -c <cluster>"
  exit 1
fi

if [ "$AWS_ACCOUNT" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the AWS project name using: -p <project>"
  exit 1
fi

DEFAULT_MY_VALUES="eks_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"

hash aws
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install aws cli tools before proceeding with this script! See: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html"
  exit 1
fi

hash eksctl
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install eksctl before proceeding with this script! See: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html"
  exit 1
fi

hash aws-iam-authenticator
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install aws-iam-authenticator before proceeding with this script! See: https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html"
  exit 1
fi

# verify the user is logged in ...
who_am_i=$(aws --profile "${AWS_ACCOUNT}" --region "${REGION}" sts get-caller-identity --query "Arn"  --output text)
if [ "${who_am_i}" == "" ]; then
  echo -e "\nERROR: AWS user unknown, please use: 'aws configure' before proceeding with this script!"
  exit 1
fi

echo -e "\nLogged in as: $who_am_i\n"

hash kubectl
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install kubectl before proceeding with this script! See: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
  exit 1
fi

hash helm
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install helm before proceeding with this script! See: https://helm.sh/docs/using_helm/#quickstart"
  exit 1
fi

aws eks --profile "${AWS_ACCOUNT}" --region "${REGION}" list-clusters --query "clusters" |  grep "${CLUSTER_NAME}" > /dev/null 2>&1
cluster_status=$?
if [ "$cluster_status" != "0" ]; then
  if [ "$CREATE_MODE" == "" ]; then
    CREATE_MODE="demo" # the default ...
  fi

  echo -e "\nLaunching an EKS cluster ${CLUSTER_NAME} ($CREATE_MODE) in project ${AWS_ACCOUNT} for deploying Lucidworks Fusion 5 ...\n"
  if [ "$CREATE_MODE" == "demo" ] || [ "${CREATE_MODE}"  == "multi_az" ]; then
     #Creates EKS cluster
     cat << EOF | eksctl create cluster --profile "${AWS_ACCOUNT}" --config-file -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${REGION}

nodeGroups:
  - name: standard-workers
    instanceType: ${INSTANCE_TYPE}
    desiredCapacity: 3
    iam:
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    ami: ${AMI}
    maxSize: 6
    minSize: 0

EOF

  else
    echo -e "\nNo --create arg provided, assuming you want a multi-AZ, multi-NodePool cluster ..."
    echo -e "Clusters with multiple NodePools not supported by this script yet! Please create the cluster and define the NodePools manually.\n"
    exit 1
  fi

  echo -e "\nCluster '${CLUSTER_NAME}' deployed ... testing if it is healthy"
  cluster_status=$(aws eks --profile "${AWS_ACCOUNT}" --region "${REGION}" describe-cluster --name "${CLUSTER_NAME}" --query "cluster.status" )
  if [ "$cluster_status" != '"ACTIVE"' ]; then
    echo -e "\nERROR: Status of EKS cluster ${CLUSTER_NAME} is suspect, status is: ${cluster_status}, check the AWS console before proceeding!\n"
    exit 1
  fi
else
  if [ "$UPGRADE" == "0" ]; then
    echo -e "\nEKS Cluster '${CLUSTER_NAME}' already exists, proceeding with Fusion 5 install ...\n"
  fi
fi

aws eks --region "${REGION}" update-kubeconfig --name "${CLUSTER_NAME}"
current_cluster=$(kubectl config current-context)

if [ "$PURGE" == "1" ]; then

  FORCE_ARG=""
  if [ "${FORCE}" == "1" ]; then
    FORCE_ARG=" --force"
  fi

  source ./setup_f5_k8s.sh -c ${CLUSTER_NAME} -r ${RELEASE} -n ${NAMESPACE} --purge ${FORCE_ARG}
  exit 0
fi

echo -e "\nConfigured to use EKS cluster: ${current_cluster}"

if [ "$UPGRADE" == "0" ]; then
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin \
    --user="$(aws --profile "${AWS_ACCOUNT}" --region "${REGION}" sts get-caller-identity --query "Arn")"
fi

lw_helm_repo=lucidworks

echo -e "\nAdding the Lucidworks chart repo to helm repo list"
helm repo list | grep "https://charts.lucidworks.com"
if [ $? ]; then
  helm repo add "${lw_helm_repo}" https://charts.lucidworks.com
fi

helm repo update

echo -e "\nInstalling Fusion 5.0 Helm chart ${CHART_VERSION} into namespace ${NAMESPACE} with release tag: ${RELEASE} using custom values from ${MY_VALUES[*]}"

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

if [ -z "${ADDITIONAL_VALUES}" ]; then
  VALUES_STRING="${VALUES_STRING} ${ADDITIONAL_VALUES}"
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

if [ "${NODE_POOL}" == "" ]; then
  # the user did not specify a node pool label, but our templating needs one
  for node in $(kubectl get nodes --namespace="${NAMESPACE}" -o=name); do kubectl label "$node" fusion_node_type=system; done
  NODE_POOL="fusion_node_type: system"
fi

# for debug only
#echo -e "Calling setup_f5_k8s.sh with: ${VALUES_STRING}${INGRESS_ARG}${UPGRADE_ARGS}"
source ./setup_f5_k8s.sh -c $CLUSTER_NAME -r "${RELEASE}" --provider "eks" -n "${NAMESPACE}" --node-pool "${NODE_POOL}" \
  --version ${CHART_VERSION} --prometheus ${PROMETHEUS} ${VALUES_STRING}${INGRESS_ARG}${UPGRADE_ARGS}
setup_result=$?
exit $setup_result

