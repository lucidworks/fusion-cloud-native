#!/bin/bash -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"

GCLOUD_PROJECT=
GCLOUD_ZONE=
CLUSTER_NAME=
NAMESPACE=default
BACKUP_VALUES="${SCRIPT_DIR}/backup_values.yaml"
SOLR_BACKUP_NFS_GB=1024
RELEASE=

function print_usage() {
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG\n"
  fi

  echo -e "  -c                     Name of the GKE cluster (required)\n"
  echo -e "  -p                     GCP Project ID (required)\n"
  echo -e "  -r                     Helm release name for installing Fusion 5; defaults to the namespace, see -n option\n"
  echo -e "  -n                     Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  --zone                  GCP Zone to create filestore in \n"
  echo -e "  --backup-values-file   The name of the values file to write backup values to"
  echo -e "  --solr-backup-fs-gb    Size (in gigabytes) of the GCP Fileshare for solr backups, defaults to ${SOLR_BACKUP_NFS_GB}\n"

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
        --zone)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --zone!"
              exit 1
            fi
            GCLOUD_ZONE=$2
            shift 2
        ;;
        --solr-backup-fs-gb)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --solr-backup-fs-gb parameter!"
              exit 1
            fi
            SOLR_BACKUP_NFS_GB=$2
            shift 2
        ;;
        --backup-values-file)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --backup-values-file parameter!"
              exit 1
            fi
            BACKUP_VALUES=$2
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


if [ -z "${GCLOUD_ZONE}" ]; then
  print_usage "$SCRIPT_CMD" "--zone parameter must be specified"
  exit 1
fi

if [ -z "${NAMESPACE}" ]; then
  print_usage "$SCRIPT_CMD" "-n parameter must be specified"
  exit 1
fi

if [ -z "${RELEASE}" ]; then
  RELEASE="${NAMESPACE}"
fi

if [ -z "${CLUSTER_NAME}" ]; then
  print_usage "$SCRIPT_CMD" "-c parameter must be specified"
  exit 1
fi

if [ -z "${GCLOUD_PROJECT}" ]; then
  print_usage "$SCRIPT_CMD" "-p parameter must be specified"
  exit 1
fi


NFS_NAME="${CLUSTER_NAME}-${NAMESPACE}-${RELEASE}"
NFS_NAME="${NFS_NAME//_/-}"

if [ -z "${GCLOUD_ZONE}" ]; then
  echo "--zone parameter must be specified"
  exit 1
fi

if ! gcloud --project "${GCLOUD_PROJECT}" filestore instances list --filter="${NFS_NAME}" | grep "${NFS_NAME}" > /dev/null 2>&1; then 
  echo -e "\n Creating GCP filestore instance with name: '${NFS_NAME}' in zone: '${GCLOUD_ZONE}'"
  gcloud --project "${GCLOUD_PROJECT}" filestore instances create "${NFS_NAME}" \
    --tier=STANDARD \
    --file-share=name="solrbackups,capacity=${SOLR_BACKUP_NFS_GB}GB" \
    --zone="${GCLOUD_ZONE}" \
    --network=name="default"
fi 

NFS_IP="$(gcloud filestore instances describe "${NFS_NAME}" \
  --project="${GCLOUD_PROJECT}" \
  --zone="${GCLOUD_ZONE}" \
  --format="value(networks.ipAddresses[0])")"

# need to create the namespace if it doesn't exist yet
if ! kubectl get namespace "${NAMESPACE}" > /dev/null 2>&1; then
  if [ "${UPGRADE}" != "1" ]; then
    kubectl create namespace "${NAMESPACE}"
    kubectl label namespace "${NAMESPACE}" "owner=${OWNER_LABEL}"
    echo -e "\nCreated namespace ${NAMESPACE} with owner label ${OWNER_LABEL}\n"
  fi
fi
cat <<EOF | kubectl -n "${NAMESPACE}" apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${NAMESPACE}-solr-backups
  annotations:
    pv.beta.kubernetes.io/gid: "8983"
spec:
  capacity:
    storage: ${SOLR_BACKUP_NFS_GB}G
  accessModes:
    - ReadWriteMany
  nfs:
    path: /solrbackups
    server: ${NFS_IP}
EOF


cat <<EOF | kubectl -n "${NAMESPACE}" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: "fusion-solr-backup-claim"
spec:
  volumeName: ${NAMESPACE}-solr-backups
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: ${SOLR_BACKUP_NFS_GB}G
EOF

tee "${BACKUP_VALUES}" << END
solr-backup-runner:
  enabled: true
  sharedPersistentVolumeName: "fusion-solr-backup-claim"

solr:
  additionalInitContainers:
    - name: chown-backup-directory
      securityContext:
        runAsUser: 0
      image: busybox:latest
      command: ['/bin/sh', '-c', "owner=\$(stat -c '%u' /mnt/solr-backups);  if [ ! \"\${owner}\" = \"8983\" ]; then chown -R 8983:8983 /mnt/solr-backups; fi "]
      volumeMounts:
        - mountPath: /mnt/solr-backups
          name: solr-backups
  additionalVolumes:
    - name: solr-backups
      persistentVolumeClaim:
        claimName: fusion-solr-backup-claim
  additionalVolumeMounts:
    - name: solr-backups
      mountPath: "/mnt/solr-backups"
END
