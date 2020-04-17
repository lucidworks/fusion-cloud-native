#!/usr/bin/env bash

PROXY_IP=`kubectl get service proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`

if [ "${PROXY_IP}" != "" ]; then
  echo -e "Found Fusion proxy service at: $PROXY_IP"
else
  echo -e "Fusion proxy service IP not found! Are you pointing to the correct namespace?"
  exit 1
fi

FUSION_API="http://${PROXY_IP}:6764/api"

FUSION_PASS="$1"
if [ "${FUSION_PASS}" == "" ]; then
  echo -e "\nPlease enter the INITIAL password for admin: "; read -s FUSION_PASS
  echo ""
fi

echo -e "Setting initial admin password for Fusion running at: $FUSION_API"
curl -XPOST -H 'Content-type: application/json' -d "{\"password\":\"${FUSION_PASS}\"}" "$FUSION_API"
echo ""
