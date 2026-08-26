# Testing Guide (Data + Read Load)

This document explains how to seed test data and run read-load tests using MongoDB connection strings.

## 1. Seed Dummy Data

Script:
- ansible/scripts/seed_dummy_data.js

Target collection:
- perf_test.events

Default seed size:
- 500,000 documents

Find current PRIMARY public IP (from your inventory):

```bash
for ip in PUBLIC_IP_1 PUBLIC_IP_2 PUBLIC_IP_3; do
  echo "=== $ip ==="
  ssh -o BatchMode=yes -o ConnectTimeout=10 root@$ip "mongosh --quiet --eval 'const h=db.hello(); printjson({isPrimary: !!h.isWritablePrimary, me: h.me});'"
done
```

Run from local machine (copy + execute on current PRIMARY):

```bash
cd ansible
PRIMARY_IP=PRIMARY_PUBLIC_IP
scp -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new scripts/seed_dummy_data.js root@${PRIMARY_IP}:/tmp/seed_dummy_data.js
ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new root@${PRIMARY_IP} 'mongosh --quiet /tmp/seed_dummy_data.js'
```

Expected output includes:
- existing_docs=...
- inserted_total=...
- total_docs=500000

## 2. 1K Read Smoke Test

Script:
- ansible/scripts/read_smoke_1k.sh

Example:

```bash
cd ansible
MONGO_HOST=PRIMARY_PUBLIC_IP TOTAL_READS=1000 CONCURRENCY=100 DOC_MAX=500000 ./scripts/read_smoke_1k.sh
```

This is useful for quick checks but is process-heavy because it spawns many mongosh clients.

## 3. 5K Read Test via Replica-Set URI

Preferred scripts:
- ansible/scripts/read_rs_5k.py
- ansible/scripts/run_read_rs_5k.sh

Why this path:
- Uses pooled Python MongoDB client
- More realistic than spawning thousands of shell processes

Example:

```bash
cd ansible
PRIMARY_IP=PRIMARY_PUBLIC_IP \
MONGO_URI='mongodb://PRIVATE_IP_1:27017,PRIVATE_IP_2:27017,PRIVATE_IP_3:27017/perf_test?replicaSet=rs0&readPreference=secondaryPreferred' \
TOTAL_READS=5000 \
WORKERS=120 \
DOC_MAX=500000 \
./scripts/run_read_rs_5k.sh
```

Output fields:
- reads_total
- reads_ok
- reads_fail
- elapsed_seconds
- throughput_rps
- server_connections_current
- server_connections_available

## 4. Verify Cluster-Wide Behavior

After test, check roles and query counters:

```bash
for ip in PUBLIC_IP_1 PUBLIC_IP_2 PUBLIC_IP_3; do
  echo "=== $ip ==="
  ssh -o BatchMode=yes -o ConnectTimeout=10 root@$ip \
    "mongosh --quiet --eval 'const h=db.hello(); const s=db.serverStatus(); printjson({me:h.me,isPrimary:!!h.isWritablePrimary,secondary:!!h.secondary,queries:s.opcounters.query});'"
done
```

## 5. Tuning Test Intensity

- Increase WORKERS gradually (120 -> 200 -> 300)
- Keep TOTAL_READS fixed (5000) for comparable runs
- Track failures, runtime, and per-node query growth

## 6. When to Use LKE

Use LKE when you need true high-concurrency client simulation (many client pods) rather than one-node load generation.

Recommended next step for production-like testing:
- Run multiple load-generator pods in LKE, each with moderate worker pools, all targeting the same replica-set URI.

## 7. Common Issues

### SSH timeout to cluster nodes
- Check current public IP and firewall allowlist.
- Update operator_allowed_cidrs in terraform.tfvars and re-apply firewall.

### One member not reachable
- Restart mongod on that host:

```bash
ssh root@NODE_IP 'systemctl restart mongod && systemctl is-active mongod'
```

### Python package install blocked (PEP 668)
- runner script already handles this by creating a virtualenv on remote host.
