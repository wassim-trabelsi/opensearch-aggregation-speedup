#!/bin/bash

# Script to generate and insert 9,000 test documents with random unit vectors
# Usage: ./scripts/generate_data.sh

set -e

OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
INDEX_NAME="${INDEX_NAME:-test_index}"
DOC_COUNT="${DOC_COUNT:-9000}"

echo "Generating $DOC_COUNT documents with random embeddings (norm = 1)..."

# Generate documents using Python for efficient vector generation
python3 << EOF
import json
import random
import math
import sys

DOC_COUNT = $DOC_COUNT
INDEX_NAME = "$INDEX_NAME"

def generate_unit_vector(dimension):
    """Generate a random unit vector (norm = 1)"""
    vector = [random.gauss(0, 1) for _ in range(dimension)]
    norm = math.sqrt(sum(x * x for x in vector))
    return [x / norm for x in vector]

def generate_document(doc_id):
    """Generate a single test document"""
    embedding = generate_unit_vector(1536)
    
    # Create unique reference ID for each document
    reference_id = f"ref_{doc_id}"
    
    return {
        "sanitized_knowledge_record": {
            "embedding": embedding
        },
        "product_info": {
            "reference": reference_id
        },
        "raw_record": {
            "object": {
                "id": doc_id,
                "name": f"Product {doc_id}",
                "description": f"Description for product {doc_id}"
            }
        },
        "price": {
            "float": round(random.uniform(10.0, 1000.0), 2)
        }
    }

# Generate bulk insert payload
bulk_actions = []
for i in range(DOC_COUNT):
    bulk_actions.append(json.dumps({"index": {"_index": INDEX_NAME}}))
    bulk_actions.append(json.dumps(generate_document(i)))

bulk_payload = "\n".join(bulk_actions) + "\n"

# Write to temporary file
with open("/tmp/opensearch_bulk.json", "w") as f:
    f.write(bulk_payload)

print(f"Generated {DOC_COUNT} documents")
print("Bulk file written to /tmp/opensearch_bulk.json")
EOF

echo "Inserting documents into OpenSearch in batches..."

# Split into batches of 500 documents (1000 lines each: index + doc)
BATCH_SIZE=1000  # lines (500 docs * 2 lines each)
TOTAL_LINES=$(wc -l < /tmp/opensearch_bulk.json)
BATCH_NUM=1

for ((START=1; START<=TOTAL_LINES; START+=BATCH_SIZE)); do
    END=$((START + BATCH_SIZE - 1))
    
    # Extract batch
    sed -n "${START},${END}p" /tmp/opensearch_bulk.json > /tmp/opensearch_bulk_batch.json
    
    # Insert batch
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$OPENSEARCH_URL/$INDEX_NAME/_bulk" \
      -H 'Content-Type: application/x-ndjson' \
      --data-binary @/tmp/opensearch_bulk_batch.json)
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Batch $BATCH_NUM inserted successfully"
    else
        echo "ERROR: Batch $BATCH_NUM failed with HTTP code: $HTTP_CODE"
        exit 1
    fi
    
    BATCH_NUM=$((BATCH_NUM + 1))
done

rm -f /tmp/opensearch_bulk_batch.json
echo "All batches inserted successfully"

echo "Refreshing index to make documents searchable..."
curl -X POST "$OPENSEARCH_URL/$INDEX_NAME/_refresh" --silent > /dev/null

echo "Waiting for index to be ready..."
sleep 3

# Verify document count
DOC_COUNT_ACTUAL=$(curl -s "$OPENSEARCH_URL/$INDEX_NAME/_count" | jq -r '.count // 0')
echo "Index now contains $DOC_COUNT_ACTUAL documents"

if [ "$DOC_COUNT_ACTUAL" = "0" ] && [ "$ITEMS_COUNT" != "0" ]; then
    echo ""
    echo "WARNING: Documents were sent but index is empty. Check the bulk response for errors."
    exit 1
fi

# Clean up
rm -f /tmp/opensearch_bulk.json

