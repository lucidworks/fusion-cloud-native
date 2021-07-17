#!/bin/bash

OUTPUT_FILE="${1}"
DOCKER_REPOSITORY="${2}"
IMAGE_PULL_SECRET="${3}"

function usage(){
  echo "generate_values_file.sh <output_file> <docker_repository> <image_pull_secret>"
}
if [[ -z "${OUTPUT_FILE}" ]]; then 
  echo "<output_file> missing"
  usage
  exit 1
fi
if [[ -z "${DOCKER_REPOSITORY}" ]]; then 
  echo "<docker_repository> missing"
  usage
  exit 1
fi
if [[ -z "${IMAGE_PULL_SECRET}" ]]; then 
  echo "<image_pull_secret> missing"
  usage
  exit 1
fi

cat > "${OUTPUT_FILE}" << EOF
---
admin-ui:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
api-gateway:
  keytoolUtils:
    image:
      repository: "${DOCKER_REPOSITORY}"
      imagePullSecrets:
        - name: "${IMAGE_PULL_SECRET}"
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
argo:
  images:
    namespace: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
argo-common-workflows:
  image:
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
auth-ui:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
classic-rest-service:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
classification:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"

connectors:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
connectors-backend:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
    repository: ${DOCKER_REPOSITORY}
connector-plugin:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
devops-ui:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
fusion-admin:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
fusion-data-augmentation:
  image:
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
fusion-indexing:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
fusion-log-forwarder:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
fusion-resources:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
insights:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
job-launcher:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
job-rest-server:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
ml-model-service:
  preinstall:
    image:
      repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  keytoolUtils:
    image:
      repository: "${DOCKER_REPOSITORY}"
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
  milvus:
    initContainerImage: "${DOCKER_REPOSITORY}/alpine:3.8"
    image:
      repository: "${DOCKER_REPOSITORY}/milvus"
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
    mysql:
      image: "${DOCKER_REPOSITORY}/mysql"
      busybox:
        image: "${DOCKER_REPOSITORY}/busybox"
      imagePullSecrets:
        - name: "${IMAGE_PULL_SECRET}"
  ambassador:
    image:
      repository: "${DOCKER_REPOSITORY}/ambassador"
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
pm-ui:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
pulsar:
  initContainer:
    image:
      repository: "${DOCKER_REPOSITORY}"
  images:
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
    zookeeper:
      repository: "${DOCKER_REPOSITORY}/pulsar-all"
    bookie:
      repository: "${DOCKER_REPOSITORY}/pulsar-all"
    autorecovery:
      repository: "${DOCKER_REPOSITORY}/pulsar-all"
    broker:
      repository: "${DOCKER_REPOSITORY}/pulsar-all"
    functions:
      repository: "${DOCKER_REPOSITORY}/pulsar-all"
    pulsar_manager:
      repository: "${DOCKER_REPOSITORY}/pulsar-manager"
  pulsar_metadata:
    image:
      repository: "${DOCKER_REPOSITORY}/pulsar-all"
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
query-pipeline:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
question-answering:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
recommender:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
rules-ui:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
seldon-core-operator:
  image:
    registry: ${DOCKER_REPOSITORY}
    repository: seldon-core-operator
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
solr:
  initContainer:
    image:
      repository: ${DOCKER_REPOSITORY}
      solrzoneImageName: "${DOCKER_REPOSITORY}/kubectl:1.15-debian-9"
  image:
    repository: ${DOCKER_REPOSITORY}/solr
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
sql-service:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
templating:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
tikaserver:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
webapps:
  image:
    repository: ${DOCKER_REPOSITORY}
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
zookeeper:
  image:
    repository: ${DOCKER_REPOSITORY}/zookeeper
    imagePullSecrets:
      - name: "${IMAGE_PULL_SECRET}"
EOF
