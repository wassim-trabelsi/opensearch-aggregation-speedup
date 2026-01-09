#!/bin/bash

# Script to execute the aggregation query (size: 0 with aggs) performance test
# Usage: ./scripts/run_agg_query.sh [query_vector_file]
# If query_vector_file is not provided, generates a new one

set -e

OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
INDEX_NAME="${INDEX_NAME:-test_index}"
ITERATIONS="${ITERATIONS:-100}"

# Get query vector
if [ -n "$1" ] && [ -f "$1" ]; then
    QUERY_VECTOR=$(cat "$1")
    if [ -z "$QUERY_VECTOR" ]; then
        echo "Error: Query vector file is empty. Generating new vector..."
        QUERY_VECTOR=$(./scripts/generate_query_vector.sh)
    fi
else
    echo "Generating query vector..."
    QUERY_VECTOR=$(./scripts/generate_query_vector.sh)
fi

echo "Running aggregation query test (size: 0 with aggs) - $ITERATIONS iterations"
echo "=========================================="

TIMINGS=()

for i in $(seq 1 $ITERATIONS); do
    RESPONSE=$(curl -s -X POST "$OPENSEARCH_URL/$INDEX_NAME/_search" \
      -H 'Content-Type: application/json' \
      -w "\n%{time_total}" \
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
                  \"_source\": [\"raw_record.object\", \"price.float\"]
                }
              }
            }
          }
        }
      }")
    
    # Extract timing from curl output (last line)
    CURL_TIME=$(echo "$RESPONSE" | tail -n 1)
    ELAPSED_MS=$(echo "$CURL_TIME * 1000" | bc)
    
    # Extract result count from aggregations (remove timing line first)
    RESULT_COUNT=$(echo "$RESPONSE" | sed '$d' | jq -r '.aggregations.by_group_id.buckets | length // 0')
    
    TIMINGS+=($ELAPSED_MS)
    
    printf "Iteration %2d: %8.2f ms | Results: %d\n" $i $ELAPSED_MS $RESULT_COUNT
done

echo ""
echo "Statistics:"
echo "-----------"

# Calculate statistics using awk and sort
STATS=$(printf '%s\n' "${TIMINGS[@]}" | sort -n | awk '
{
    sum += $1
    sumsq += $1 * $1
    if (NR == 1 || $1 < min) min = $1
    if (NR == 1 || $1 > max) max = $1
    arr[NR] = $1
}
END {
    mean = sum / NR
    variance = (sumsq / NR) - (mean * mean)
    stddev = sqrt(variance)
    
    # Calculate median (input is already sorted)
    n = NR
    if (n % 2 == 1) {
        median = arr[(n + 1) / 2]
    } else {
        median = (arr[n / 2] + arr[n / 2 + 1]) / 2
    }
    
    printf "Mean: %.2f ms\n", mean
    printf "Median: %.2f ms\n", median
    printf "Min: %.2f ms\n", min
    printf "Max: %.2f ms\n", max
    printf "Standard deviation: %.2f ms\n", stddev
}')

echo "$STATS"

# Store results for comparison
printf '%s\n' "${TIMINGS[@]}" > /tmp/agg_query_timings.txt
echo "$STATS" > /tmp/agg_query_stats.txt

