#!/bin/bash

APP=""
SOLR="http://localhost:8983"

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to delete and re-create Solr collections for a Fusion app to adjust shards, replicas, and auto-scaling policy"
  echo -e "\nWARNING: This script deletes Solr collections so any data in the collections will be lost! Be careful as this operation cannot be undone."
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  --app    App ID; required, no default\n"
  echo -e "  --solr   Base Solr URL, defaults to ${SOLR}"
  echo -e "             Use kubectl port-forward to open an SSH connection to Solr in your k8s cluster.\n"
}

SCRIPT_CMD="$0"

if [ $# -gt 1 ]; then
  while true; do
    case "$1" in
        --app)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --app parameter!"
              exit 1
            fi
            APP="$2"
            shift 2
        ;;
        --solr)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --solr parameter!"
              exit 1
            fi
            SOLR="$2"
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

if [ "$APP" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Fusion app ID using: --app <ID>"
  exit 1
fi

echo -e "\nDeleting existing collections in Solr (${SOLR}) to re-create them with proper auto-scaling policy, shards, and replicas\n"

curl "$SOLR/solr/admin/collections?action=DELETE&name=${APP}"
curl "$SOLR/solr/admin/collections?action=DELETE&name=${APP}_signals"
curl "$SOLR/solr/admin/collections?action=DELETE&name=${APP}_signals_aggr"
curl "$SOLR/solr/admin/collections?action=DELETE&name=${APP}_query_rewrite_staging"
curl "$SOLR/solr/admin/collections?action=DELETE&name=${APP}_query_rewrite"
curl "$SOLR/solr/admin/collections?action=DELETE&name=${APP}_job_reports"
curl "$SOLR/solr/admin/collections?action=DELETE&name=${APP}_user_prefs"

sleep 5

# analytics oriented collections
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_signals&collection.configName=${APP}_signals&numShards=3&replicationFactor=2&policy=analytics&maxShardsPerNode=2"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_query_rewrite_staging&collection.configName=${APP}_query_rewrite_staging&numShards=1&replicationFactor=2&policy=analytics"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_job_reports&collection.configName=${APP}_job_reports&numShards=1&replicationFactor=2&policy=analytics"

sleep 2

# search oriented collections
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}&collection.configName=${APP}&numShards=1&replicationFactor=3&policy=search"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_signals_aggr&collection.configName=${APP}_signals_aggr&numShards=1&replicationFactor=3&policy=search"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_query_rewrite&collection.configName=${APP}_query_rewrite&numShards=1&replicationFactor=3&policy=search"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_user_prefs&collection.configName=${APP}_user_prefs&numShards=1&replicationFactor=2&policy=search"
