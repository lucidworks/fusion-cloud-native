#!/bin/bash
pod_type="connectors-backend"
pod_name="$(kubectl get pods --template '{{range.items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep ${pod_type})"
echo "Pod name is: ${pod_name}"

d=`date +%m-%d-%Y`
run=1
notes_dir="../profile/notes/"
log_filename="${notes_dir}post-install-output-${d}_${pod_type}_${pod_name}_${run}.txt"

echo "kubectl logs ${pod_name} -c ${pod_type} 2>&1 | tee -a ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${pod_name} -c ${pod_type} 2>&1 | tee -a  ${log_filename}

echo "kubectl logs ${pod_name} -c check-zk 2>&1 | tee -a  ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${pod_name} -c check-zk 2>&1 | tee -a  ${log_filename}

echo "kubectl logs ${pod_name} -c check-kafka 2>&1 | tee -a  ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${pod_name} -c check-kafka 2>&1 | tee -a  ${log_filename}

echo "kubectl logs ${pod_name} -c check-admin 2>&1 | tee -a  ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${pod_name} -c check-admin 2>&1 | tee -a  ${log_filename}

echo "kubectl logs ${pod_name} -c check-indexing 2>&1 | tee -a  ${log_filename}" | tee -a  ${log_filename}
kubectl logs ${pod_name} -c check-indexing 2>&1 | tee -a  ${log_filename}