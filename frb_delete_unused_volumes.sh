#!/bin/bash

for volume in `aws ec2 describe-volumes --filter "Name=status,Values=available" --output text --query "Volumes[*].{ID:VolumeId}"`
do
    echo "Executing aws ec2 delete-volume --volume-id $volume"
    aws ec2 delete-volume --volume-id $volume
done