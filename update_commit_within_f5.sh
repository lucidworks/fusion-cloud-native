#!/usr/bin/env bash

if [ -z $LW_K8S_GATEWAY ]; then
  if [ -z $LW_K8S_GATEWAY_IP ]; then
    echo -e "\nERROR: No LW_K8S_GATEWAY or LW_K8S_GATEWAY_IP defined!\n"
    exit 1
  fi

  LW_K8S_GATEWAY="http://${LW_K8S_GATEWAY_IP}:6764"
fi

if [ -z $LW_K8S_CREDS ]; then
  LW_K8S_CREDS="admin:password123"
fi

COLLECTION=$1
if [ -z "$COLLECTION" ]; then
  echo "ERROR: Pass the collection name!"
  exit 1
fi

COMMIT_WITHIN="$2"
if [ -z "$COMMIT_WITHIN" ]; then
  COMMIT_WITHIN="-1"
fi

find="\"commitWithin\" : [[:digit:]]+"
replace="\"commitWithin\" : $COMMIT_WITHIN"
json_file="${COLLECTION}.json"

curl -s -u $LW_K8S_CREDS "$LW_K8S_GATEWAY/api/collections/${COLLECTION}" > $json_file

echo -e "\nCurrent properties for $COLLECTION:"
cat $json_file

sed -E -i '' "s/${find}/${replace}/" $json_file

echo -e "\n\nUpdated to:"
curl -u $LW_K8S_CREDS -XPUT "$LW_K8S_GATEWAY/api/collections/${COLLECTION}" -H "Content-type:application/json" -d @$json_file

rm $json_file
