#!/bin/bash

# Script to verify that both query types return the same product IDs
# Usage: ./scripts/verify_same_results.sh [query_vector_file]

set -e

OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
INDEX_NAME="${INDEX_NAME:-test_index}"

# Get query vector
if [ -n "$1" ] && [ -f "$1" ]; then
    QUERY_VECTOR=$(cat "$1")
else
    echo "Generating query vector..."
    QUERY_VECTOR=$(./scripts/generate_query_vector.sh)
fi

echo "=========================================="
echo "Verifying Both Queries Return Same Results"
echo "=========================================="
echo ""

# Run basic query and extract product IDs
echo "Running basic query (size: 100)..."
BASIC_RESPONSE=$(curl -s -X POST "$OPENSEARCH_URL/$INDEX_NAME/_search" \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": {
      \"function_score\": {
        \"query\": {
          \"bool\": {
            \"must\": [
              {
                \"knn\": {
                  \"sanitized_knowledge_record.embedding\": {
                    \"vector\": $QUERY_VECTOR,
                    \"k\": 1000,
                    \"boost\": 0.97
                  }
                }
              }
            ]
          }
        },
        \"boost_mode\": \"sum\"
      }
    },
    \"size\": 100,
    \"_source\": [\"product_info.reference\", \"raw_record.object.id\"]
  }")

BASIC_IDS=$(echo "$BASIC_RESPONSE" | jq -r '.hits.hits[] | ._source.product_info.reference' | sort)
BASIC_COUNT=$(echo "$BASIC_IDS" | wc -l | tr -d ' ')

echo "Basic query returned $BASIC_COUNT results"
echo ""

# Run aggregation query and extract product IDs
echo "Running aggregation query (size: 0 with aggs)..."
AGG_RESPONSE=$(curl -s -X POST "$OPENSEARCH_URL/$INDEX_NAME/_search" \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": {
      \"function_score\": {
        \"query\": {
          \"bool\": {
            \"must\": [
              {
                \"knn\": {
                  \"sanitized_knowledge_record.embedding\": {
                    \"vector\": $QUERY_VECTOR,
                    \"k\": 1000,
                    \"boost\": 0.97
                  }
                }
              }
            ]
          }
        },
        \"boost_mode\": \"sum\"
      }
    },
    \"size\": 0,
    \"aggs\": {
      \"by_group_id\": {
        \"terms\": {
          \"field\": \"product_info.reference\",
          \"order\": {\"best_score\": \"desc\"},
          \"size\": 100
        },
        \"aggs\": {
          \"best_score\": {
            \"max\": {\"script\": \"_score\"}
          },
          \"best_hit\": {
            \"top_hits\": {
              \"size\": 1,
              \"_source\": [\"product_info.reference\", \"raw_record.object.id\"]
            }
          }
        }
      }
    }
  }")

AGG_IDS=$(echo "$AGG_RESPONSE" | jq -r '.aggregations.by_group_id.buckets[].best_hit.hits.hits[0]._source.product_info.reference' | sort)
AGG_COUNT=$(echo "$AGG_IDS" | wc -l | tr -d ' ')

echo "Aggregation query returned $AGG_COUNT results"
echo ""

# Compare results
echo "=========================================="
echo "Comparison Results"
echo "=========================================="

if [ "$BASIC_COUNT" -eq "$AGG_COUNT" ]; then
    echo "✓ Both queries returned the same number of results: $BASIC_COUNT"
else
    echo "✗ Result count mismatch:"
    echo "  Basic query: $BASIC_COUNT results"
    echo "  Aggregation query: $AGG_COUNT results"
fi

# Check if IDs match
DIFF=$(diff <(echo "$BASIC_IDS") <(echo "$AGG_IDS") || true)

if [ -z "$DIFF" ]; then
    echo "✓ Both queries returned the same product IDs"
    echo ""
    echo "Sample IDs (first 10):"
    echo "$BASIC_IDS" | head -10
else
    echo "✗ Product IDs differ!"
    echo ""
    echo "Differences:"
    echo "$DIFF" | head -20
    echo ""
    echo "Basic query IDs (first 10):"
    echo "$BASIC_IDS" | head -10
    echo ""
    echo "Aggregation query IDs (first 10):"
    echo "$AGG_IDS" | head -10
fi

echo ""
echo "=========================================="

