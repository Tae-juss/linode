#!/usr/bin/env python3
import os
import random
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

from pymongo import MongoClient
from pymongo.read_preferences import SecondaryPreferred

MONGO_URI = os.getenv(
    "MONGO_URI",
    "mongodb://10.0.0.2:27017,10.0.0.3:27017,10.0.0.4:27017/perf_test?replicaSet=rs0",
)
DB_NAME = os.getenv("DB_NAME", "perf_test")
COLL_NAME = os.getenv("COLL_NAME", "events")
TOTAL_READS = int(os.getenv("TOTAL_READS", "5000"))
WORKERS = int(os.getenv("WORKERS", "200"))
DOC_MAX = int(os.getenv("DOC_MAX", "500000"))


def main() -> int:
    client = MongoClient(
        MONGO_URI,
        appname="mongo-read-rs-test",
        maxPoolSize=max(300, WORKERS + 20),
        minPoolSize=min(20, WORKERS),
        serverSelectionTimeoutMS=10000,
    )
    coll = client.get_database(DB_NAME, read_preference=SecondaryPreferred())[COLL_NAME]

    # Warm up connection and topology discovery.
    client.admin.command("ping")

    def one_read(_):
        doc_id = random.randrange(0, DOC_MAX)
        doc = coll.find_one({"doc_id": doc_id}, {"_id": 1, "doc_id": 1})
        return doc is not None

    start = time.time()
    ok = 0
    fail = 0

    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futures = [ex.submit(one_read, i) for i in range(TOTAL_READS)]
        for f in as_completed(futures):
            try:
                if f.result():
                    ok += 1
                else:
                    fail += 1
            except Exception:
                fail += 1

    elapsed = time.time() - start
    rps = TOTAL_READS / elapsed if elapsed > 0 else 0.0

    print(f"reads_total={TOTAL_READS}")
    print(f"reads_ok={ok}")
    print(f"reads_fail={fail}")
    print(f"elapsed_seconds={elapsed:.3f}")
    print(f"throughput_rps={rps:.2f}")

    # Sample server-side connection metrics from current primary.
    status = client.admin.command("serverStatus")
    conns = status.get("connections", {})
    print(f"server_connections_current={conns.get('current')}")
    print(f"server_connections_available={conns.get('available')}")

    client.close()
    return 0 if fail == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
