#!/bin/bash

GCP_PROJECT=CHANGEME
CLUSTER=CHANGEME
REGION=us-west1
VERS="-"

gcloud config set compute/zone ${REGION}
gcloud config set project $GCP_PROJECT

gcloud beta container --project "${GCP_PROJECT}" clusters create "${CLUSTER}" \
  --region "${REGION}" \
  --no-enable-basic-auth \
  --cluster-version ${VERS} \
  --machine-type "n1-standard-4" --image-type "COS" \
  --disk-type "pd-standard" \
  --disk-size "50" \
  --node-labels fusion_node_type=system \
  --metadata disable-legacy-endpoints=true \
  --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
  --num-nodes "1" \
  --logging=NONE \
  --monitoring=NONE \
  --enable-ip-alias \
  --network "projects/${GCP_PROJECT}/global/networks/default" \
  --subnetwork "projects/${GCP_PROJECT}/regions/${REGION}/subnetworks/default" \
  --default-max-pods-per-node "30" \
  --enable-autoscaling \
  --min-nodes "1" \
  --max-nodes "4" \
  --no-enable-autoupgrade --enable-autorepair

gcloud config set container/cluster ${CLUSTER}

gcloud beta container --project "${GCP_PROJECT}" node-pools create "spark-std-8" \
  --node-version ${VERS} \
  --cluster "${CLUSTER}" \
  --region "${REGION}" \
  --machine-type "n1-standard-8" \
  --image-type "COS" \
  --disk-type "pd-standard" \
  --disk-size "100" \
  --node-labels fusion_node_type=spark_only \
  --metadata disable-legacy-endpoints=true \
  --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
  --preemptible \
  --num-nodes "1" \
  --enable-autoscaling \
  --min-nodes "0" \
  --max-nodes "2" \
  --no-enable-autoupgrade \
  --enable-autorepair

gcloud beta container --project "${GCP_PROJECT}" node-pools create "search-highmem-8" \
  --node-version ${VERS} \
  --cluster "${CLUSTER}" \
  --region "${REGION}" \
  --machine-type "n1-highmem-8" \
  --image-type "COS" \
  --disk-type "pd-standard" \
  --disk-size "100" \
  --node-labels fusion_node_type=search \
  --metadata disable-legacy-endpoints=true \
  --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
  --num-nodes "1" \
  --enable-autoscaling \
  --min-nodes "0" \
  --max-nodes "3" \
  --no-enable-autoupgrade \
  --enable-autorepair

gcloud beta container --project "${GCP_PROJECT}" node-pools create "analytics-std-4" \
  --node-version ${VERS} \
  --cluster "${CLUSTER}" \
  --region "${REGION}" \
  --machine-type "n1-standard-4" \
  --image-type "COS" \
  --disk-type "pd-standard" \
  --disk-size "100" \
  --node-labels fusion_node_type=analytics \
  --metadata disable-legacy-endpoints=true \
  --scopes "https://www.googleapis.com/auth/devstorage.full_control","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
  --num-nodes "0" \
  --enable-autoscaling \
  --min-nodes "0" \
  --max-nodes "4" \
  --no-enable-autoupgrade \
  --enable-autorepair
