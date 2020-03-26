#!/bin/bash
SOLR=http://localhost:8983
curl -XPOST "$SOLR/api/cluster/autoscaling" -H "Content-type:application/json" --data-binary @policy.json
curl "$SOLR/api/cluster/autoscaling"
