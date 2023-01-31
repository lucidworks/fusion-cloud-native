#!/bin/bash
# Scale down EKS cluster to lower EC2 cost
eksctl scale nodegroup --cluster=fusion-5 --nodes=0 --name=standard-workers