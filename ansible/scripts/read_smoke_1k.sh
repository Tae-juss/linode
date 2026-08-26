#!/usr/bin/env bash
set -euo pipefail

MONGO_HOST="${MONGO_HOST:-127.0.0.1}"
MONGO_PORT="${MONGO_PORT:-27017}"
TOTAL_READS="${TOTAL_READS:-1000}"
CONCURRENCY="${CONCURRENCY:-100}"
DB_NAME="${DB_NAME:-perf_test}"
COLL_NAME="${COLL_NAME:-events}"
DOC_MAX="${DOC_MAX:-500000}"

# This is a quick smoke test for random single-document reads.
# It is not a full benchmark because workers spawn separate mongosh processes.

echo "Starting read smoke test: reads=${TOTAL_READS} concurrency=${CONCURRENCY} host=${MONGO_HOST}:${MONGO_PORT}"
start_ts=$(date +%s)

seq 1 "${TOTAL_READS}" | xargs -P "${CONCURRENCY}" -I{} sh -c '
  id=$(awk -v max='"${DOC_MAX}"' "BEGIN{srand(); print int(rand()*max)}")
  mongosh --quiet --host '"${MONGO_HOST}"' --port '"${MONGO_PORT}"' --eval "db.getSiblingDB(\"'"${DB_NAME}"'\").getCollection(\"'"${COLL_NAME}"'\").findOne({doc_id: ${id}})" >/dev/null
'

end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))
echo "read_smoke_completed reads=${TOTAL_READS} seconds=${elapsed}"
