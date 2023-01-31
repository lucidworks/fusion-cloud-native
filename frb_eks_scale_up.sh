#!/bin/bash
# Scale up EKS clusters
eksctl scale nodegroup --cluster=fusion-5 --nodes=3 --name=standard-workers
sleep 60;
# Add code to wait till the abobe EC2 instances are running
fusion_ec2_pending_instances=($(aws ec2 describe-instances --filters 'Name=tag:alpha.eksctl.io/cluster-name,Values=fusion-5*' 'Name=instance-state-name,Values=pending' --output text --query 'Reservations[*].Instances[*].InstanceId'))
for pending_instance_id in "${fusion_ec2_pending_instances[@]}"
do
 echo "Pending EC2 Instance ID is : $pending_instance_id"
done

load_balancer_name=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[*].[LoadBalancerName]' --output text)
echo "Load balancer name: ${load_balancer_name}"
# Get all ec2 instance ids where tag key=alpha.eksctl.io/cluster-name and value=Fusion-5.
# fusion_ec2_running_instances=($(aws ec2 describe-instances --filters 'Name=tag:alpha.eksctl.io/cluster-name,Values=fusion-5*' # 'Name=instance-state-name,Values=running' --output text --query 'Reservations[*].Instances[*].InstanceId'))
#fusion_ec2_running_instances="$(aws ec2 describe-instances --filters 'Name=tag:alpha.eksctl.io/cluster-name,Values=fusion-5*' 'Name=instance-state-name,Values=running' --output text --query 'Reservations[*].Instances[*].InstanceId')"
fusion_ec2_running_instances=$(aws ec2 describe-instances --filters 'Name=tag:alpha.eksctl.io/cluster-name,Values=fusion-5*' 'Name=instance-state-name,Values=running' --output json --query 'Reservations[*].Instances[*].InstanceId' | grep -i 'i-*' | sed 's/,//g'| sed 's/\"//g' | tr -d '[:space:]' | sed 's/i-/ i-/g')
echo "fusion_ec2_running_instances: $fusion_ec2_running_instances"
echo "Executing aws elb register-instances-with-load-balancer --load-balancer-name $load_balancer_name --instances $fusion_ec2_running_instances"
aws elb register-instances-with-load-balancer --load-balancer-name $load_balancer_name --instances $fusion_ec2_running_instances
# ec2_instance_ids_string=""
# for running_instance_id in "${fusion_ec2_running_instances[@]}"
# do
# echo "Running EC2 Instance ID is : $running_instance_id"
 # ec2_instance_ids_string+="${instance_id} "
# echo "Executing aws elb register-instances-with-load-balancer --load-balancer-name $load_balancer_name --instances $running_instance_id"
# aws elb register-instances-with-load-balancer --load-balancer-name $load_balancer_name --instances $running_instance_id
# done