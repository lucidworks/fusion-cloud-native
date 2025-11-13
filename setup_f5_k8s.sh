#!/bin/bash

# Platform agnostic script used by the other setup_f5_*.sh scripts to perform general K8s and Helm commands to install Fusion.
# This script assumes kubectl is pointing to the right cluster and that the user is already authenticated.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"

CHART_VERSION="5.9.15"
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
IS_CRC=0

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
  echo -e "  --values          Custom values file containing config overrides in addition to the default <provider>_<cluster>_<release>_fusion_values.yaml"
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
            if [ ! -z "$1" ]; then
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

# Log our current kube context for the user
current=$(kubectl config current-context)
echo -e "Using kubeconfig: $current"

# Setup our owner label so we can check ownership of namespaces
if [ "$PROVIDER" == "gke" ]; then
  who_am_i=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "")
else
  who_am_i=""
fi
OWNER_LABEL="${who_am_i//@/-}"

# Determine if we have helm v3
is_helm_v3=$(helm version --short 2>/dev/null | grep v3)

if [ "${is_helm_v3}" == "" ]; then
  echo -e "\nWARNING: Helm v2 detected. Helm v3 is recommended."
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

# Detect CRC environment
IS_CRC=0
if [ "$PROVIDER" == "oc" ]; then
  # Try to detect if we're running on CRC
  crc_info=$(kubectl get nodes -o jsonpath='{.items[0].metadata.labels.node\.kubernetes\.io/instance-type}' 2>/dev/null)
  if [[ "$crc_info" == *"crc"* ]] || [[ $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) == *"crc-"* ]]; then
    IS_CRC=1
    echo "Detected CodeReady Containers (CRC) environment"
  fi
fi

# If we are upgrading
if [ "${UPGRADE}" == "1" ]; then
  # Make sure the namespace exists
  if ! kubectl get namespace "${NAMESPACE}" > /dev/null 2>&1; then
    echo -e "\nNamespace ${NAMESPACE} not found, if this is a new cluster please run an install first"
    exit 1
  fi

  # Check if the owner label on the namespace is the same as we are
  namespace_owner=$(kubectl get namespace "${NAMESPACE}" -o 'jsonpath={.metadata.labels.owner}' 2>/dev/null)
  if [ "${namespace_owner}" != "" ] && [ "${namespace_owner}" != "${OWNER_LABEL}" ] && [ "${FORCE}" != "1" ]; then
    echo -e "Namespace ${NAMESPACE} is owned by: ${namespace_owner}, but we are: ${OWNER_LABEL}"
    echo -e "Please provide the --force parameter if you are sure you wish to upgrade this namespace"
    exit 1
  fi
elif [ "$PURGE" == "1" ]; then
  kubectl get namespace "${NAMESPACE}"
  namespace_exists=$?
  if [ "$namespace_exists" != "0" ]; then
    echo -e "\nNamespace ${NAMESPACE} not found so assuming ${RELEASE} has already been purged"
    exit 1
  fi

  # Check if the owner label on the namespace is the same as we are
  namespace_owner=$(kubectl get namespace "${NAMESPACE}" -o 'jsonpath={.metadata.labels.owner}' 2>/dev/null)
  if [ "${namespace_owner}" != "" ] && [ "${namespace_owner}" != "${OWNER_LABEL}" ] && [ "${FORCE}" != "1" ]; then
    echo -e "Namespace ${NAMESPACE} is owned by: ${namespace_owner}, but we are: ${OWNER_LABEL}"
    echo -e "Please provide the --force parameter if you are sure you wish to purge this namespace"
    exit 1
  fi

  confirm="Y"
  echo ""
  read -p "Are you sure you want to purge the ${RELEASE} release from the ${NAMESPACE} namespace in: $current? This operation cannot be undone! Y/n " confirm
  if [ "$confirm" == "" ] || [ "$confirm" == "Y" ] || [ "$confirm" == "y" ]; then

    if [ "$is_helm_v3" != "" ]; then
      helm delete "${RELEASE}" --namespace "${NAMESPACE}"
      monitor_chart_checker=$(helm list --namespace "${NAMESPACE}" | grep -o ${RELEASE}-monitoring)
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
      echo -e "\nERROR: There is already a release with name: ${RELEASE} installed in the cluster"
      echo -e "Please choose a different release name or upgrade the release\n"
      exit 1
    fi
  else
     if helm status --namespace "${NAMESPACE}" "${RELEASE}" > /dev/null 2>&1 ; then
       echo -e "\nERROR: There is already a release with name: ${RELEASE} installed in namespace: ${NAMESPACE}"
       echo -e "Please choose a different release name or upgrade the release\n"
       exit 1
     fi
  fi

  # Check if there is a fusion deployment in the namespace already
  if ! kubectl get deployment -n "${NAMESPACE}" -l "app.kubernetes.io/component=query-pipeline,app.kubernetes.io/part-of=fusion" 2>&1 | grep -q "No resources"; then
    instance=$(kubectl get deployment -n "${NAMESPACE}" -l "app.kubernetes.io/component=query-pipeline,app.kubernetes.io/part-of=fusion" -o "jsonpath={.items[0].metadata.labels['app\.kubernetes\.io/instance']}" 2>/dev/null)
    echo -e "\nERROR: There is already a fusion deployment in namespace: ${NAMESPACE} with release name: ${instance}"
    echo -e "Please choose a new namespace\n"
    exit 1
  fi
fi

# report_ns logs a message to the user informing them how to change the default namespace
function report_ns() {
  if [ "${NAMESPACE}" != "default" ]; then
    echo -e "\nNote: Change the default namespace for kubectl to ${NAMESPACE} by doing:"
    echo -e "    kubectl config set-context --current --namespace=${NAMESPACE}\n"
  fi
}

# proxy_url prints how to access the proxy via a LoadBalancer service
function proxy_url() {
  if [ "${PROVIDER}" == "eks" ]; then
    export PROXY_HOST=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  else
    export PROXY_HOST=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  fi

  export PROXY_PORT=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.spec.ports[?(@.protocol=="TCP")].port}' 2>/dev/null)
  export PROXY_URL="$PROXY_HOST:$PROXY_PORT"

  if [ "$PROXY_URL" != ":" ]; then
    echo -e "\n\nFusion 5 Gateway service exposed at: $PROXY_URL\n"
    echo -e "WARNING: This IP address is exposed to the WWW w/o SSL!"
    echo -e "You are strongly encouraged to configure a K8s Ingress with TLS\n"
    report_ns
  else
    echo -e "\n\nFailed to get Fusion Gateway service URL! Check console for previous errors.\n"
  fi
}

# ingress_setup informs the user how to finish setting up the DNS records for their ingress
function ingress_setup() {
  if [ "${PROVIDER}" != "eks" ]; then
    echo -ne "\nWaiting for the Loadbalancer IP to be assigned"
    loops=24
    while (( loops > 0 )); do
      ingressIp=$(kubectl --namespace "${NAMESPACE}" get ingress "${RELEASE}-api-gateway" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
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
  else
    ALB_DNS=$(kubectl get ing ${RELEASE}-api-gateway --output=jsonpath={.status..loadBalancer..ingress[].hostname} 2>/dev/null)
    echo -e "\n\nPlease ensure that the public DNS record for ${INGRESS_HOSTNAME} is updated to point to ${ALB_DNS}\n"
  fi

  if [ "$TLS_ENABLED" == "1" ]; then
    echo -e "An SSL certificate will be automatically generated once the public DNS record has been updated"
  fi
  report_ns
}

# Build the list of custom values files
if [ ! -z "${CUSTOM_MY_VALUES[*]}" ]; then
  MY_VALUES=(${CUSTOM_MY_VALUES[@]})
fi

# Validate custom values files exist
for v in "${MY_VALUES[@]}"; do
  if [ ! -f "${v}" ]; then
    echo -e "\nERROR: Custom values file ${v} not found! Please check your --values arg(s)\n"
    exit 1
  fi
  echo "Using custom values file: $v"
done

# If we are not upgrading, generate the values files and upgrade script
if [ "$UPGRADE" != "1" ]; then
  if [ -f "${UPGRADE_SCRIPT}" ]; then
    echo "There is already an upgrade script ${UPGRADE_SCRIPT} present"
    echo "Please use a new release name or upgrade your current release"
    exit 1
  fi
  
  if [ ! -f "${DEFAULT_MY_VALUES}" ]; then
    PROMETHEUS_ON=true
    if [ "${PROMETHEUS}" == "none" ]; then
      PROMETHEUS_ON=false
    fi

    # Count nodes matching node pool if specified
    num_nodes=1
    if [ "${NODE_POOL}" != "" ] && [ "${NODE_POOL}" != "{}" ]; then
      node_selector=$(tr ': ' '=' <<<"${NODE_POOL}")
      retries=6
      while (( retries > 0 )); do
        find_nodes=$(kubectl get nodes -l "${node_selector}" 2>/dev/null | grep -i ready)
        has_nodes=$?
        if [ "${has_nodes}" == "0" ]; then
          echo -e "Found at least one healthy node matching nodeSelector: ${NODE_POOL}"
          num_nodes=$(kubectl get nodes -l "${node_selector}" | grep -i ready | wc -l)
          retries=-1
        else
          echo -e "\nWARNING: No 'Ready' nodes found matching nodeSelector: ${node_selector}! Retrying in 30 seconds"
          echo -ne "."
          sleep 30
          retries=$(( retries - 1 ))
        fi
      done
      if [ "${retries}" == "0" ]; then
        echo -e "\nERROR: No 'Ready' nodes found matching nodeSelector: ${node_selector}!"
        echo -e "Check the '--node-pool' parameter and retry running this script!\n"
        exit 1
      fi
    else
      num_nodes=$(kubectl get nodes 2>/dev/null | grep -i ready | wc -l)
    fi

    # Check if customize_fusion_values.sh exists
    if [ -f "${SCRIPT_DIR}/customize_fusion_values.sh" ]; then
      # Build VALUES_STRING for customize script using --additional-values
      VALUES_STRING=""
      for v in "${MY_VALUES[@]}"; do
        VALUES_STRING="${VALUES_STRING} --additional-values ${v}"
      done

      echo "Generating values file: ${DEFAULT_MY_VALUES}"
      ( "${SCRIPT_DIR}/customize_fusion_values.sh" "${DEFAULT_MY_VALUES}" \
        -c "${CLUSTER_NAME}" \
        -n "${NAMESPACE}" \
        -r "${RELEASE}" \
        --provider "${PROVIDER}" \
        --prometheus "${PROMETHEUS_ON}" \
        --num-solr "${SOLR_REPLICAS}" \
        --num-kafka "${KAFKA_REPLICAS}" \
        --solr-disk-gb "${SOLR_DISK_GB}" \
        --node-pool "${NODE_POOL}" \
        --version "${CHART_VERSION}" \
        --output-script "${UPGRADE_SCRIPT}" \
        ${VALUES_STRING} )
    else
      # If customize script doesn't exist, create a basic values file
      echo "Warning: customize_fusion_values.sh not found, creating basic values file"
      cat > "${DEFAULT_MY_VALUES}" <<EOF
# Fusion values for ${CLUSTER_NAME}
# Generated: $(date)

solr:
  replicaCount: ${SOLR_REPLICAS}
  volumeClaimTemplates:
    storageSize: ${SOLR_DISK_GB}Gi

kafka:
  replicaCount: ${KAFKA_REPLICAS}

prometheus:
  enabled: ${PROMETHEUS_ON}
EOF

      # Create a basic upgrade script
      cat > "${UPGRADE_SCRIPT}" <<EOF
#!/bin/bash
SCRIPT_DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" > /dev/null && pwd )"

helm upgrade ${RELEASE} lucidworks/fusion \\
  --namespace ${NAMESPACE} \\
  --version ${CHART_VERSION} \\
  --values ${DEFAULT_MY_VALUES} \\
  \$@
EOF
      chmod +x "${UPGRADE_SCRIPT}"
    fi
  else
    echo -e "\nValues file $DEFAULT_MY_VALUES already exists, not regenerating.\n"
  fi
fi

# Verify kubectl is connected to a cluster
kubectl cluster-info > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "\nERROR: kubectl cannot connect to a Kubernetes cluster!"
  echo "Please ensure kubectl is configured correctly."
  exit 1
fi

# Get owner label if available
OWNER_LABEL="${OWNER_LABEL:-${USER:-unknown}}"

# Check if namespace exists
kubectl get namespace "$NAMESPACE" > /dev/null 2>&1
ns_exists=$?

if [ $ns_exists -eq 0 ]; then
  echo "Using existing namespace: $NAMESPACE"
  
  # Check namespace ownership if not forcing
  if [ "$FORCE" != "1" ]; then
    current_owner=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.owner}' 2>/dev/null)
    if [ "$current_owner" != "" ] && [ "$current_owner" != "$OWNER_LABEL" ]; then
      echo -e "\nWARNING: Namespace $NAMESPACE is owned by: $current_owner"
      echo "You are: $OWNER_LABEL"
      echo "Use --force to override this check if needed."
    fi
  fi
else
  echo -e "\nCreating namespace ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}"
  
  # Add owner label
  if [ "${OWNER_LABEL}" != "" ]; then
    kubectl label namespace "${NAMESPACE}" "owner=${OWNER_LABEL}"
  fi
fi

# OpenShift specific setup
if [ "$PROVIDER" == "oc" ]; then
  # Run the security setup script before Helm install
  SECURITY_SCRIPT="${SCRIPT_DIR}/openshift_security_setup.sh"
  
  if [ -f "$SECURITY_SCRIPT" ]; then
    echo -e "\nSetting up OpenShift security configurations..."
    
    # Capture both stdout and the exit code
    SECURITY_OUTPUT=$("$SECURITY_SCRIPT" "$NAMESPACE" "$RELEASE" setup 2>&1)
    SECURITY_EXIT_CODE=$?
    
    # Check exit code
    if [ $SECURITY_EXIT_CODE -ne 0 ]; then
      echo "ERROR: OpenShift security setup failed with exit code: $SECURITY_EXIT_CODE"
      echo "$SECURITY_OUTPUT"
      exit 1
    fi
    
    # Parse the security override file from output
    SECURITY_OVERRIDE_FILE=$(echo "$SECURITY_OUTPUT" | grep "SECURITY_OVERRIDE_FILE=" | cut -d'=' -f2)
    
    # Add security override file to values if it was created
    if [ -f "$SECURITY_OVERRIDE_FILE" ]; then
      echo "Adding security override file: $SECURITY_OVERRIDE_FILE"
      MY_VALUES+=("$SECURITY_OVERRIDE_FILE")
    fi
    
    echo "OpenShift security setup completed successfully"
  else
    echo "WARNING: OpenShift security setup script not found at: $SECURITY_SCRIPT"
    echo "Fusion may not work properly without proper SCC configuration!"
  fi
fi

# Add Lucidworks Helm repo
echo -e "\nAdding Lucidworks Helm repository..."
helm repo add lucidworks https://charts.lucidworks.com 2>/dev/null || true
helm repo update

# Don't mess with upgrading the Prom / Grafana charts during upgrade
if [ "$UPGRADE" != "1" ] && [ "${PROMETHEUS}" != "none" ]; then
  if [ "${PROMETHEUS}" == "install" ]; then
    echo -e "\nInstalling Prometheus and Grafana for monitoring..."
    if [ "${is_helm_v3}" != "" ]; then
      # Check if prometheus repo is added
      helm repo list | grep prometheus-community > /dev/null 2>&1
      if [ $? -ne 0 ]; then
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        helm repo add stable https://charts.helm.sh/stable
        helm repo update
      fi
      
      # Install kube-prometheus-stack for Helm v3
      helm install "${RELEASE}-monitoring" prometheus-community/kube-prometheus-stack \
        --namespace "${NAMESPACE}" \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set grafana.adminPassword=admin123
    else
      # For Helm v2, use the older stable charts
      helm install stable/prometheus \
        --name "${RELEASE}-monitoring" \
        --namespace "${NAMESPACE}" \
        --set server.service.type=ClusterIP \
        --set alertmanager.enabled=false
    fi
  fi
fi

# Execute the upgrade script
if [ "$UPGRADE" == "1" ]; then
  if [ ! -f "${UPGRADE_SCRIPT}" ]; then
    echo -e "\nUpgrade script ${UPGRADE_SCRIPT} not found"
    echo "If this is a new cluster please run an install first"
    exit 1
  fi
  echo -e "\nUpgrading Fusion using: ${UPGRADE_SCRIPT}"
else
  echo -e "\nInstalling Fusion ${CHART_VERSION} into namespace ${NAMESPACE} with release tag: ${RELEASE}"
fi

# Let's exit immediately if the upgrade script command fails
set -e
if [ -f "${UPGRADE_SCRIPT}" ]; then
  chmod +x "${UPGRADE_SCRIPT}"
  bash "${UPGRADE_SCRIPT}" "${DRY_RUN}"
else
  echo "ERROR: Upgrade script ${UPGRADE_SCRIPT} not found"
  exit 1
fi
set +e

install_status=$?

# For OpenShift, run post-installation security setup IMMEDIATELY after Helm
# This is critical for hooks and jobs to work properly
if [ "$PROVIDER" == "oc" ] && [ "${DRY_RUN}" == "" ]; then
  SECURITY_SCRIPT="${SCRIPT_DIR}/openshift_security_setup.sh"
  
  if [ -f "$SECURITY_SCRIPT" ]; then
    echo -e "\nRunning post-installation security fixes for OpenShift (CRITICAL FOR JOBS)..."
    "$SECURITY_SCRIPT" "$NAMESPACE" "$RELEASE" post-install
    
    if [ $? -eq 0 ]; then
      echo "Post-installation security setup completed"
      
      # Give OpenShift time to propagate permissions
      echo "Waiting 10 seconds for permissions to propagate..."
      sleep 10
      
      # Trigger any failed jobs to retry
      echo "Triggering retry of failed jobs..."
      kubectl delete pods --field-selector=status.phase=Failed -n ${NAMESPACE} 2>/dev/null || true
      kubectl delete jobs --field-selector status.failed!=0 -n ${NAMESPACE} 2>/dev/null || true
    else
      echo "WARNING: Post-installation security setup had issues, but continuing..."
    fi
  fi
fi

if [ "$install_status" != "0" ]; then
  echo -e "\nInstallation failed with status: $install_status"
  
  # Provide troubleshooting tips
  echo -e "\nTroubleshooting tips:"
  echo "   1. Check if the Helm chart version exists: helm search repo lucidworks/fusion --versions"
  echo "   2. Check namespace events: kubectl get events -n ${NAMESPACE}"
  echo "   3. Check if there are resource constraints: kubectl describe nodes"
  
  if [ "$IS_CRC" == "1" ]; then
    echo "   4. For CRC, ensure you have enough resources allocated:"
    echo "      crc config get cpus"
    echo "      crc config get memory"
  fi
  
  exit $install_status
fi

if [ "${DRY_RUN}" == "" ]; then
  echo -e "\nFusion installation/upgrade completed successfully!"
  
  # Wait for pods to start
  echo -e "\nWaiting for Fusion pods to start..."
  echo "   This may take several minutes, especially on CRC..."
  
  # Wait a bit for resources to be created
  sleep 10
  
  # Show pod status
  echo -e "\nCurrent pod status:"
  kubectl get pods -n ${NAMESPACE}
  
  # Check if ingress is configured
  if [ "${INGRESS_HOSTNAME}" != "" ]; then
    ingress_setup
  else
    # Show how to access Fusion
    proxy_url
  fi
  
  # Show default credentials
  echo -e "\nDefault Fusion credentials:"
  echo "   Username: admin"
  echo "   Password: password123"
  echo ""
  echo "   WARNING: Remember to change the default password after first login!"
  
  if [ "$IS_CRC" == "1" ]; then
    echo -e "\nCRC-specific notes:"
    echo "   - CRC has limited resources, some services may take longer to start"
    echo "   - If pods are pending, check events: kubectl get events -n ${NAMESPACE}"
    echo "   - Monitor pod status: kubectl get pods -n ${NAMESPACE} -w"
    echo ""
    echo "   Quick access options for CRC:"
    echo "   1. Port forwarding (recommended):"
    echo "      kubectl port-forward -n ${NAMESPACE} svc/${RELEASE}-api-gateway 8764:8764"
    echo "      Access at: http://localhost:8764"
    echo ""
    echo "   2. OpenShift Route:"
    echo "      oc expose svc/${RELEASE}-api-gateway -n ${NAMESPACE}"
    echo "      oc get route -n ${NAMESPACE}"
  fi
  
  # Show monitoring info if Prometheus was installed
  if [ "$PROMETHEUS" == "install" ]; then
    echo -e "\nMonitoring with Prometheus and Grafana:"
    echo "   To access Grafana:"
    echo "   kubectl port-forward -n ${NAMESPACE} svc/${RELEASE}-monitoring-grafana 3000:80"
    echo "   Access at: http://localhost:3000"
    echo "   Username: admin"
    echo "   Password: admin123"
  fi
  
  echo -e "\nUseful commands:"
  echo "   - Check pod status: kubectl get pods -n ${NAMESPACE}"
  echo "   - Check logs: kubectl logs -n ${NAMESPACE} <pod-name>"
  echo "   - Get all resources: kubectl get all -n ${NAMESPACE}"
  echo "   - Describe a pod: kubectl describe pod -n ${NAMESPACE} <pod-name>"
  
  if [ -f "${UPGRADE_SCRIPT}" ]; then
    echo "   - Upgrade Fusion: ./${UPGRADE_SCRIPT}"
  fi
  
  echo -e "\nSetup complete! Fusion is being deployed to your cluster."
  echo "   It may take a few minutes for all services to be fully operational."
  
else
  echo -e "\nDry-run completed. No changes were made."
  echo "   Remove --dry-run flag to perform actual installation."
fi

# Final check for pod readiness (only if not dry-run and not upgrading)
if [ "${DRY_RUN}" == "" ] && [ "${UPGRADE}" != "1" ]; then
  echo -e "\nWaiting for Fusion API Gateway to be ready..."
  
  # Wait for the API gateway to be ready
  retries=60
  while (( retries > 0 )); do
    ready=$(kubectl get pod -n ${NAMESPACE} -l "app.kubernetes.io/component=api-gateway,app.kubernetes.io/instance=${RELEASE}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$ready" == "True" ]; then
      echo "   API Gateway is ready!"
      break
    fi
    retries=$(( retries - 1 ))
    echo -ne "."
    sleep 5
  done
  
  if [ $retries -eq 0 ]; then
    echo -e "\n   WARNING: API Gateway is taking longer than expected to start."
    echo "      Check pod status with: kubectl get pods -n ${NAMESPACE}"
    echo "      Check events with: kubectl get events -n ${NAMESPACE}"
  fi
fi