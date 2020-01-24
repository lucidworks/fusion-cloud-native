#!/bin/bash
SOLR=http://localhost:8983
curl -XPOST "$SOLR/api/cluster/autoscaling" -H "Content-type:application/json" --data-binary @policy.json
curl "$SOLR/api/cluster/autoscaling"

exit 0

APP=

echo -e "\nCreating Analytics collection in the Analytics partition"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_signals&collection.configName=${APP}_signals&numShards=3&replicationFactor=2&policy=Analytics"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_query_rewrite_staging&collection.configName=${APP}_query_rewrite_staging&numShards=1&replicationFactor=2&policy=Analytics"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_job_reports&collection.configName=${APP}_job_reports&numShards=1&replicationFactor=2&policy=Analytics"

sleep 3

echo -e "\nCreating Search collections in the Search partition"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}&collection.configName=${APP}&numShards=1&replicationFactor=3&policy=search"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_signals_aggr&collection.configName=${APP}_signals_aggr&numShards=1&replicationFactor=3&policy=search"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_query_rewrite&collection.configName=${APP}_query_rewrite&numShards=1&replicationFactor=3&policy=search"
curl "$SOLR/solr/admin/collections?action=CREATE&name=${APP}_user_prefs&collection.configName=${APP}_user_prefs&numShards=1&replicationFactor=2&policy=search"

