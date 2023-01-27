#!/bin/bash

connectors_backend_pod="$(kubectl get pods --template '{{range.items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep connectors-backend)"
d=`date +%m-%d-%Y`
run=1
notes_dir="../profile/notes/"
log_filename="${notes-dir}post-install-output-${d}_${run}.txt"

echo "kubectl logs ${connectors_backend_pod} -c connectors-backend 2>&1 | tee -a ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${connectors_backend_pod} -c connectors-backend 2>&1 | tee -a  ${log_filename}

echo "kubectl logs ${connectors_backend_pod} -c check-zk 2>&1 | tee -a  ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${connectors_backend_pod} -c check-zk 2>&1 | tee -a  ${log_filename}

echo "kubectl logs ${connectors_backend_pod} -c check-kafka 2>&1 | tee -a  ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${connectors_backend_pod} -c check-kafka 2>&1 | tee -a  ${log_filename}

echo "kubectl logs ${connectors_backend_pod} -c check-admin 2>&1 | tee -a  ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${connectors_backend_pod} -c check-admin 2>&1 | tee -a  ${log_filename}

echo "kubectl logs ${connectors_backend_pod} -c check-indexing 2>&1 | tee -a  ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${connectors_backend_pod} -c check-indexing 2>&1 | tee -a  ${log_filename}