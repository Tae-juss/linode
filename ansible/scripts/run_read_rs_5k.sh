#!/usr/bin/env bash
set -euo pipefail

PRIMARY_IP="${PRIMARY_IP:-}"
MONGO_URI="${MONGO_URI:-}"
TOTAL_READS="${TOTAL_READS:-5000}"
WORKERS="${WORKERS:-200}"
DOC_MAX="${DOC_MAX:-500000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${PRIMARY_IP}" ]]; then
  echo "PRIMARY_IP is required"
  echo "Example: PRIMARY_IP=203.0.113.10"
  exit 1
fi

if [[ -z "${MONGO_URI}" ]]; then
  echo "MONGO_URI is required"
  echo "Example: mongodb://10.0.0.2:27017,10.0.0.3:27017,10.0.0.4:27017/perf_test?replicaSet=rs0&readPreference=secondaryPreferred"
  exit 1
fi

scp -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new \
  "${SCRIPT_DIR}/read_rs_5k.py" root@"${PRIMARY_IP}":/tmp/read_rs_5k.py

ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new root@"${PRIMARY_IP}" \
  "apt-get update -y >/dev/null && apt-get install -y python3-venv >/dev/null && python3 -m venv /opt/mongo-loadtest-venv && /opt/mongo-loadtest-venv/bin/pip -q install --upgrade pip >/dev/null && /opt/mongo-loadtest-venv/bin/pip -q install pymongo >/dev/null && MONGO_URI='${MONGO_URI}' TOTAL_READS='${TOTAL_READS}' WORKERS='${WORKERS}' DOC_MAX='${DOC_MAX}' /opt/mongo-loadtest-venv/bin/python /tmp/read_rs_5k.py"
