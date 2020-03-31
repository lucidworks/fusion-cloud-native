#!/usr/bin/env bash

COMMIT_WITHIN="-1"
LW_K8S_GATEWAY="http://localhost:6764"

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to update the commit_within setting for a Fusion collection"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  --collection     Collection name (required)\n"
  echo -e "  --gateway        Fusion API Gateway URL, defaults to http://localhost:6764\n"
  echo -e "  --commit_within  Commit within ms; defaults to -1 (disabled)\n"
}

SCRIPT_CMD="$0"

if [ $# -gt 1 ]; then
  while true; do
    case "$1" in
        --collection)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --collection parameter!"
              exit 1
            fi
            COLLECTION="$2"
            shift 2
        ;;
        --gateway)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --gateway parameter!"
              exit 1
            fi
            LW_K8S_GATEWAY="$2"
            shift 2
        ;;
        --commit_within)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --commit_within parameter!"
              exit 1
            fi
            COMMIT_WITHIN="$2"
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

if [ -z $LW_K8S_GATEWAY ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Gateway URL name using: --gateway <URL>"
  exit 1
fi

if [ -z "$COLLECTION" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Collection name using: --collection <ID>"
  exit 1
fi

if [ -z "$COMMIT_WITHIN" ]; then
  COMMIT_WITHIN="-1"
fi

echo -e "admin password: "; read -s admin_passwd
LW_K8S_CREDS="admin:${admin_passwd}"
echo ""

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
