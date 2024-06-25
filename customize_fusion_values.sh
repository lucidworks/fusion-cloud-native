#!/bin/bash

NODE_POOL=""
SOLR_REPLICAS=3
KAFKA_REPLICAS=3
CLUSTER_NAME=
PROMETHEUS_ON=true
SOLR_DISK_GB=50
PROVIDER=gke
RESOURCES=false
AFFINITY=false
REPLICAS=false
CHART_VERSION="5.9.4"
NAMESPACE=default
OUTPUT_SCRIPT=""
ADDITIONAL_VALUES=()
SKIP_CRDS=""
KAFKA_URL=""

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to create a custom Fusion values yaml from a template"
  echo -e "\nUsage: $CMD <yaml-file-to-create> [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c                      Cluster name (required)\n"
  echo -e "  -n                      Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  -r                      Helm release name for installing Fusion 5; defaults to the namespace, see -n option\n"
  echo -e "  --version               Fusion Helm Chart version; defaults to the latest release from Lucidworks, such as ${CHART_VERSION}\n"
  echo -e "  --provider              Name of your K8s provider, e.g. eks, aks, gke, oc; defaults to 'gke'\n"
  echo -e "  --prometheus            Enable Prometheus? true or false, defaults to true\n"
  echo -e "  --skip-crds             Add skip CRDs option to the helm upgrade command\n"
  echo -e "  --num-solr              Number of Solr pods to deploy, defaults to 3\n"
  echo -e "  --num-kafka             Number of Kafka pods to deploy, defaults to 3\n"
  echo -e "  --solr-disk-gb          Size (in gigabytes) of the Solr persistent volume claim, defaults to 50\n"
  echo -e "  --node-pool             Node pool label to assign pods to specific nodes, this option is only useful for existing\n                          clusters where you defined a custom node pool; defaults to '${NODE_POOL}', wrap the arg in double-quotes\n"
  echo -e "  --with-resource-limits  Flag to enable resource limits yaml, defaults to off\n"
  echo -e "  --with-affinity-rules   Flag to enable pod affinity rules yaml, defaults to off\n"
  echo -e "  --with-replicas         Flag to enable replicas yaml, defaults to off\n"
  echo -e "  --additional-values     Additional values files to add to the upgrade script, may be specified multiple times\n"
  echo -e "  --output-script         The name of the generated upgrade script, defaults to <provider>_<cluster_name>_<release>_upgrade_fusion.sh \n"
  echo -e "\nIf you omit the <yaml-file-to-create> arg, then the script will create it using the naming convention:\n       <provider>_<cluster>_<release>_fusion_values.yaml\n"
}

SCRIPT_CMD="$0"
MY_VALUES="$1"

if [ "$MY_VALUES" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the name of the values yaml file to create as the first arg to this script!"
  exit 1
fi

# start parsing
if [[ $MY_VALUES == -* ]] ; then
  # they didn't pass us the file name, so we'll compute it ..
  MY_VALUES="" # clear and compute after processing args
else
  # assume $1 is the values file name they want ...
  shift 1
fi

if [ $# -gt 1 ]; then
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
        --version)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --version parameter!"
              exit 1
            fi
            CHART_VERSION="$2"
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
        --prometheus)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --prometheus parameter!"
              exit 1
            fi
            PROMETHEUS_ON="$2"
            shift 2
        ;;
        --with-resource-limits)
            RESOURCES="true"
            shift 1
        ;;
        --skip-crds)
            SKIP_CRDS="--skip-crds"
            shift 1
        ;;
        --with-affinity-rules)
            AFFINITY="true"
            shift 1
        ;;
        --with-replicas)
            REPLICAS="true"
            shift 1
        ;;
        --additional-values)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --additional-values parameter!"
              exit 1
            fi
            ADDITIONAL_VALUES+=("$2")
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
        --output-script)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --output-script parameter!"
              exit 1
            fi
            OUTPUT_SCRIPT="$2"
            shift 2
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

if [ "$CLUSTER_NAME" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the K8s cluster name using: -c <cluster>"
  exit 1
fi

if [ "$MY_VALUES" == "" ]; then
  MY_VALUES="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"
fi

if [ "${OUTPUT_SCRIPT}" == "" ]; then
  OUTPUT_SCRIPT="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_upgrade_fusion.sh"
fi

if [ "${NODE_POOL}" == "" ]; then
  if [ "${PROVIDER}" == "eks" ]; then
    NODE_POOL="alpha.eksctl.io/nodegroup-name: standard-workers"
  elif [ "${PROVIDER}" == "gke" ]; then
    NODE_POOL="cloud.google.com/gke-nodepool: default-pool"
  else
    NODE_POOL="{}"
  fi
fi

ZK_REPLICAS=3



if [[ "$KAFKA_REPLICAS" == 1 ]]; then
  KAFKA_URL="$RELEASE-kafka-headless:9092"
else
  KAFKA_URL="$RELEASE-kafka-0.$RELEASE-kafka-headless:9092,$RELEASE-kafka-1.$RELEASE-kafka-headless:9092,$RELEASE-kafka-2.$RELEASE-kafka-headless:9092"
fi

cp customize_fusion_values.yaml.example $MY_VALUES
if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys"  ]]; then
  sed -i -e "s|{NODE_POOL}|${NODE_POOL}|g" "$MY_VALUES"
  sed -i -e "s|{SOLR_REPLICAS}|${SOLR_REPLICAS}|g" "$MY_VALUES"
  sed -i -e "s|{KAFKA_REPLICAS}|${KAFKA_REPLICAS}|g" "$MY_VALUES"
  sed -i -e "s|{ZK_REPLICAS}|${ZK_REPLICAS}|g" "$MY_VALUES"
  sed -i -e "s|{RELEASE}|${RELEASE}|g" "$MY_VALUES"
  sed -i -e "s|{PROMETHEUS}|${PROMETHEUS_ON}|g" "$MY_VALUES"
  sed -i -e "s|{SOLR_DISK_GB}|${SOLR_DISK_GB}|g" "$MY_VALUES"
  sed -i -e "s|{KAFKA_URL}|${KAFKA_URL}|g" "$MY_VALUES"
else
  sed -i '' -e "s|{NODE_POOL}|${NODE_POOL}|g" "$MY_VALUES"
  sed -i '' -e "s|{SOLR_REPLICAS}|${SOLR_REPLICAS}|g" "$MY_VALUES"
  sed -i '' -e "s|{KAFKA_REPLICAS}|${KAFKA_REPLICAS}|g" "$MY_VALUES"
  sed -i '' -e "s|{ZK_REPLICAS}|${ZK_REPLICAS}|g" "$MY_VALUES"
  sed -i '' -e "s|{RELEASE}|${RELEASE}|g" "$MY_VALUES"
  sed -i '' -e "s|{PROMETHEUS}|${PROMETHEUS_ON}|g" "$MY_VALUES"
  sed -i '' -e "s|{SOLR_DISK_GB}|${SOLR_DISK_GB}|g" "$MY_VALUES"
  sed -i '' -e "s|{KAFKA_URL}|${KAFKA_URL}|g" "$MY_VALUES"
fi

echo -e "\nCreated Fusion custom values yaml: ${MY_VALUES}\n"
BASE_CUSTOM_VALUES_REPLACE="MY_VALUES=\"\$MY_VALUES --values ${MY_VALUES}\""


if [ "$PROMETHEUS_ON" == "true" ]; then
  MONITORING_VALUES="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_monitoring_values.yaml"
  if [ ! -f "${MONITORING_VALUES}" ]; then
    cp example-values/monitoring-values.yaml "${MONITORING_VALUES}"
    if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys"  ]]; then
      sed -i -e "s|{NODE_POOL}|${NODE_POOL}|g" "${MONITORING_VALUES}"
      sed -i -e "s|{NAMESPACE}|${NAMESPACE}|g" "${MONITORING_VALUES}"
    else
      sed -i '' -e "s|{NODE_POOL}|${NODE_POOL}|g" "${MONITORING_VALUES}"
      sed -i '' -e "s|{NAMESPACE}|${NAMESPACE}|g" "${MONITORING_VALUES}"
    fi
    echo -e "\nCreated Monitoring custom values yaml: ${MONITORING_VALUES}. Keep this file handy as you'll need it to customize your Monitoring installation.\n"
  fi
fi

cp upgrade_fusion.sh.example "${OUTPUT_SCRIPT}"
if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys"  ]]; then
  sed -i -e "s|<PROVIDER>|${PROVIDER}|g" "$OUTPUT_SCRIPT"
  sed -i -e "s|<CLUSTER>|${CLUSTER_NAME}|g" "$OUTPUT_SCRIPT"
  sed -i -e "s|<RELEASE>|${RELEASE}|g" "$OUTPUT_SCRIPT"
  sed -i -e "s|<NAMESPACE>|${NAMESPACE}|g" "$OUTPUT_SCRIPT"
  sed -i -e "s|<CHART_VERSION>|${CHART_VERSION}|g" "$OUTPUT_SCRIPT"
  sed -i -e "s|<BASE_CUSTOM_VALUES>|${BASE_CUSTOM_VALUES_REPLACE}|g" "${OUTPUT_SCRIPT}"
  sed -i -e "s|<SKIP_CRDS>|${SKIP_CRDS}|g" "$OUTPUT_SCRIPT"

else
  sed -i '' -e "s|<PROVIDER>|${PROVIDER}|g" "$OUTPUT_SCRIPT"
  sed -i '' -e "s|<CLUSTER>|${CLUSTER_NAME}|g" "$OUTPUT_SCRIPT"
  sed -i '' -e "s|<RELEASE>|${RELEASE}|g" "$OUTPUT_SCRIPT"
  sed -i '' -e "s|<NAMESPACE>|${NAMESPACE}|g" "$OUTPUT_SCRIPT"
  sed -i '' -e "s|<CHART_VERSION>|${CHART_VERSION}|g" "$OUTPUT_SCRIPT"
  sed -i '' -e "s|<BASE_CUSTOM_VALUES>|${BASE_CUSTOM_VALUES_REPLACE}|g" "${OUTPUT_SCRIPT}"
  sed -i '' -e "s|<SKIP_CRDS>|${SKIP_CRDS}|g" "$OUTPUT_SCRIPT"
fi



if [ "$RESOURCES" == "true" ]; then
  resyaml="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_fusion_resources.yaml"
  cp example-values/resources.yaml "${resyaml}"
  replace="MY_VALUES=\"\$MY_VALUES --values ${resyaml}\""

  if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys" ]]; then
    sed -i -e "s|<RESOURCES_YAML>|${replace}|g" "$OUTPUT_SCRIPT"
  else
    sed -i '' -e "s|<RESOURCES_YAML>|${replace}|g" "$OUTPUT_SCRIPT"
  fi
else
  if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys"  ]]; then
    sed -i -e "s|<RESOURCES_YAML>||g" "$OUTPUT_SCRIPT"
  else
    sed -i '' -e "s|<RESOURCES_YAML>||g" "$OUTPUT_SCRIPT"
  fi
fi

if [ "$AFFINITY" == "true" ]; then
  affyaml="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_fusion_affinity.yaml"
  cp example-values/affinity.yaml "${affyaml}"
  replace="MY_VALUES=\"\$MY_VALUES --values ${affyaml}\""

  if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys"  ]]; then
    sed -i -e "s|<AFFINITY_YAML>|${replace}|g" "$OUTPUT_SCRIPT"
  else
    sed -i '' -e "s|<AFFINITY_YAML>|${replace}|g" "$OUTPUT_SCRIPT"
  fi
else
  if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys"  ]]; then
    sed -i -e "s|<AFFINITY_YAML>||g" "$OUTPUT_SCRIPT"
  else
    sed -i '' -e "s|<AFFINITY_YAML>||g" "$OUTPUT_SCRIPT"
  fi
fi

if [ "$REPLICAS" == "true" ]; then
  repyaml="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_fusion_replicas.yaml"
  cp example-values/replicas.yaml "${repyaml}"
  replace="MY_VALUES=\"\$MY_VALUES --values ${repyaml}\""

  if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys"  ]]; then
    sed -i -e "s|<REPLICAS_YAML>|${replace}|g" "$OUTPUT_SCRIPT"
  else
    sed -i '' -e "s|<REPLICAS_YAML>|${replace}|g" "$OUTPUT_SCRIPT"
  fi
else
  if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys"  ]]; then
    sed -i -e "s|<REPLICAS_YAML>||g" "$OUTPUT_SCRIPT"
  else
    sed -i '' -e "s|<REPLICAS_YAML>||g" "$OUTPUT_SCRIPT"
  fi
fi

ADDITIONAL_VALUES_STRING=""
if [ ! -z "${ADDITIONAL_VALUES[*]}" ]; then
  for v in "${ADDITIONAL_VALUES[@]}"; do
    ADDITIONAL_VALUES_STRING="${ADDITIONAL_VALUES_STRING} --values ${v}"
  done
  ADDITIONAL_VALUES_STRING="MY_VALUES=\"\$MY_VALUES $ADDITIONAL_VALUES_STRING\""
fi
if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys"  ]]; then
  sed -i -e "s|<ADDITIONAL_VALUES>|${ADDITIONAL_VALUES_STRING}|g" "$OUTPUT_SCRIPT"
else
  sed -i '' -e "s|<ADDITIONAL_VALUES>|${ADDITIONAL_VALUES_STRING}|g" "$OUTPUT_SCRIPT"
fi


echo -e "\nCreate $OUTPUT_SCRIPT for upgrading you Fusion cluster. Please keep this script along with your custom values yaml file(s) in version control.\n"
