#!/bin/bash -e

REGION="us-west-2"
CONFIG_FILE="eksctl_config.yaml"
REGION_ZONES=(a b c)


function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to setup a multi nodePool EKS cluster\n"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c          Name of the EKS cluster (required)\n"
  echo -e "  -p          AWS_ACCOUNT - profile (required)\n"
  echo -e "  -r          REGION - region to create cluster in, defaults to: ${REGION}\n"
  echo -e "  --config-file   Output file for generate eksctl config file, defaults to: ${CONFIG_FILE} \n"
}

if [ $# -gt 0 ]; then
  while true; do
    case "$1" in
        -c)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -c parameter!"
              exit 1
            fi
            CLUSTER="$2"
            shift 2
        ;;
        -p)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -p parameter!"
              exit 1
            fi
            PROFILE="$2"
            shift 2
        ;;
        -r)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -r parameter!"
              exit 1
            fi
            REGION="$2"
            shift 2
        ;;
        --config-file)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --config-file parameter!"
              exit 1
            fi
            CONFIG_FILE="$2"
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

if [ "${PROFILE}" == "" ]; then
  print_usage "${SCRIPT_CMD}" "Please provide the AWS project name using: -p <project>"
  exit 1
fi

if [ "${CLUSTER}" == "" ]; then
  print_usage "${SCRIPT_CMD}" "Please provide the EKS cluster name using: -c <cluster_name>"
  exit 1
fi

cat > "${CONFIG_FILE}" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: "${CLUSTER}"
  region: "${REGION}"
availabilityZones:
EOF
for zone in ${REGION_ZONES[@]}; do
cat >> "${CONFIG_FILE}" << EOF
 - "${REGION}${zone}"
EOF

done
cat >> "${CONFIG_FILE}" << EOF
nodeGroups:
EOF

for zone in ${REGION_ZONES[@]}; do
cat >> "${CONFIG_FILE}" <<EOF
  - name: "default-${REGION}${zone}"
    instanceType: m5.xlarge
    desiredCapacity: 1
    privateNetworking: true
    availabilityZones:
      - "${REGION}${zone}"
    maxSize: 2
    minSize: 1
    securityGroups:
      withShared: true
      withLocal: true
    labels:
      fusion_node_type: system
    iam:
      withAddonPolicies:
        autoScaler: true
        certManager: true
  - name: "spark-${REGION}${zone}"
    instanceType: m5.2xlarge
    desiredCapacity: 1
    privateNetworking: true
    availabilityZones:
      - "${REGION}${zone}"
    maxSize: 2
    minSize: 0
    securityGroups:
      withShared: true
      withLocal: true
    labels:
      fusion_node_type: spark_only
    iam:
      withAddonPolicies:
        autoScaler: true
        certManager: true
  - name: "highcpu-${REGION}${zone}"
    instanceType: c5.2xlarge
    desiredCapacity: 1
    privateNetworking: true
    availabilityZones:
      - "${REGION}${zone}"
    maxSize: 1
    minSize: 1
    securityGroups:
      withShared: true
      withLocal: true
    labels:
      fusion_node_type: gateway
    iam:
      withAddonPolicies:
        autoScaler: true
        certManager: true
  - name: "query-${REGION}${zone}"
    instanceType: m5.2xlarge
    desiredCapacity: 1
    privateNetworking: true
    availabilityZones:
      - "${REGION}${zone}"
    maxSize: 2
    minSize: 1
    securityGroups:
      withShared: true
      withLocal: true
    labels:
      fusion_node_type: query
    iam:
      withAddonPolicies:
        autoScaler: true
        certManager: true
  - name: "search-${REGION}${zone}"
    instanceType: m5.2xlarge
    desiredCapacity: 3
    privateNetworking: true
    availabilityZones:
      - "${REGION}${zone}"
    maxSize: 4
    minSize: 3
    securityGroups:
      withShared: true
      withLocal: true
    labels:
      fusion_node_type: search
    iam:
      withAddonPolicies:
        autoScaler: true
        certManager: true
  - name: "analytics-${REGION}${zone}"
    instanceType: m5.xlarge
    desiredCapacity: 1
    privateNetworking: true
    availabilityZones:
      - "${REGION}${zone}"
    maxSize: 2
    minSize: 1
    securityGroups:
      withShared: true
      withLocal: true
    labels:
      fusion_node_type: analytics
    iam:
      withAddonPolicies:
        autoScaler: true
        certManager: true
EOF
done

eksctl --profile "${PROFILE}" create cluster --config-file "${CONFIG_FILE}"

eksctl --profile "${PROFILE}" utils write-kubeconfig --cluster "${CLUSTER}"

helm install cluster-autoscaler stable/cluster-autoscaler \
 --set "autoDiscovery.clusterName=${CLUSTER}" \
 --set cloud-provider=aws \
 --set rbac.create=true \
 --set "awsRegion=${REGION}"
