#!/bin/bash

# Script to create the test index with proper KNN field mapping
# Usage: ./scripts/create_index.sh

set -e

OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
INDEX_NAME="${INDEX_NAME:-test_index}"

echo "Creating index: $INDEX_NAME"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$OPENSEARCH_URL/$INDEX_NAME" \
  -H 'Content-Type: application/json' \
  -d '{
  "settings": {
    "index": {
      "knn": true,
      "knn.algo_param.ef_search": 1000
    }
  },
  "mappings": {
    "properties": {
      "sanitized_knowledge_record": {
        "properties": {
          "embedding": {
            "type": "knn_vector",
            "dimension": 1536,
            "method": {
              "name": "hnsw",
              "space_type": "cosinesimil",
              "engine": "faiss",
              "parameters": {
                "ef_construction": 128,
                "m": 24
              }
            }
          }
        }
      },
      "product_info": {
        "properties": {
          "reference": {
            "type": "keyword"
          }
        }
      },
      "raw_record": {
        "properties": {
          "object": {
            "type": "object",
            "enabled": true
          }
        }
      },
      "price": {
        "properties": {
          "float": {
            "type": "float"
          }
        }
      }
    }
  }
}')

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
    echo ""
    echo "Index created successfully!"
    echo "Waiting for index to be ready..."
    sleep 2
    curl -X GET "$OPENSEARCH_URL/$INDEX_NAME/_settings" | jq '.' || echo "Index settings retrieved"
else
    echo ""
    echo "ERROR: Failed to create index (HTTP $HTTP_CODE)"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    exit 1
fi
