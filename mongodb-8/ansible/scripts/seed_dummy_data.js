const targetCount = parseInt(process.env.TARGET_COUNT || '500000', 10);
const batchSize = parseInt(process.env.BATCH_SIZE || '1000', 10);

const dbh = db.getSiblingDB('perf_test');
const coll = dbh.getCollection('events');

coll.createIndex({ tenant_id: 1, created_at: -1 });
coll.createIndex({ category: 1, score: -1 });
coll.createIndex({ user_id: 1 });

const existing = coll.countDocuments();
print('existing_docs=' + existing);

if (existing >= targetCount) {
  print('seed_skipped=true');
  print('total_docs=' + existing);
  quit(0);
}

let inserted = 0;
for (let i = existing; i < targetCount; i += batchSize) {
  const docs = [];
  const upper = Math.min(i + batchSize, targetCount);

  for (let j = i; j < upper; j++) {
    docs.push({
      doc_id: j,
      tenant_id: 'tenant_' + (j % 50),
      user_id: 'user_' + (j % 20000),
      category: ['alpha', 'beta', 'gamma', 'delta'][j % 4],
      score: (j * 17) % 1000,
      payload: {
        source: 'dummy-seed',
        flags: [j % 2 === 0, j % 3 === 0, j % 5 === 0],
        tags: ['tag_' + (j % 20), 'tag_' + (j % 37)],
        nested: { a: j % 97, b: j % 193, c: 'v' + (j % 1000) }
      },
      created_at: new Date(Date.now() - ((targetCount - j) * 1000)),
      updated_at: new Date()
    });
  }

  coll.insertMany(docs, { ordered: false });
  inserted += (upper - i);

  if (inserted % 50000 === 0) {
    print('inserted=' + inserted);
  }
}

print('inserted_total=' + inserted);
print('total_docs=' + coll.countDocuments());
