#!/usr/bin/env bash
set -euo pipefail

# Run 5K read operations using a MongoDB replica set connection string.
# Defaults assume this script is executed from one of the MongoDB nodes.

MONGO_URI="${MONGO_URI:-mongodb://10.0.0.2:27017,10.0.0.3:27017,10.0.0.4:27017/perf_test?replicaSet=rs0&readPreference=secondaryPreferred}"
TOTAL_READS="${TOTAL_READS:-5000}"
CONCURRENCY="${CONCURRENCY:-200}"
DOC_MAX="${DOC_MAX:-500000}"

echo "Starting replica-set read test"
echo "uri=${MONGO_URI}"
echo "reads=${TOTAL_READS} concurrency=${CONCURRENCY}"

start_ts=$(date +%s)

seq 1 "${TOTAL_READS}" | xargs -P "${CONCURRENCY}" -I{} sh -c '
  id=$(awk -v max='"${DOC_MAX}"' "BEGIN{srand(); print int(rand()*max)}")
  mongosh --quiet "'"${MONGO_URI}"'" --eval "db.events.findOne({doc_id: ${id}})" >/dev/null
'

end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))
echo "read_test_completed reads=${TOTAL_READS} seconds=${elapsed}"
