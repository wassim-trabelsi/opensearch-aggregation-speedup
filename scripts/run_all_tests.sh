#!/bin/bash

# Script to orchestrate the full test suite
# Usage: ./scripts/run_all_tests.sh

set -e

OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
INDEX_NAME="${INDEX_NAME:-test_index}"

echo "=========================================="
echo "OpenSearch Performance Bug Reproduction"
echo "=========================================="
echo ""

# Function to wait for OpenSearch to be ready
wait_for_opensearch() {
    echo "Waiting for OpenSearch to be ready..."
    MAX_ATTEMPTS=30
    ATTEMPT=0
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if curl -s "$OPENSEARCH_URL" > /dev/null 2>&1; then
            echo "OpenSearch is ready!"
            return 0
        fi
        ATTEMPT=$((ATTEMPT + 1))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS - waiting..."
        sleep 2
    done
    
    echo "ERROR: OpenSearch did not become ready in time"
    exit 1
}

# Function to check if index exists
index_exists() {
    curl -s -o /dev/null -w "%{http_code}" "$OPENSEARCH_URL/$INDEX_NAME" | grep -q "200"
}

# Function to check document count
get_doc_count() {
    curl -s "$OPENSEARCH_URL/$INDEX_NAME/_count" | jq -r '.count' 2>/dev/null || echo "0"
}

# Wait for OpenSearch
wait_for_opensearch

# Check if index exists and has data
if index_exists; then
    DOC_COUNT=$(get_doc_count)
    echo "Index '$INDEX_NAME' exists with $DOC_COUNT documents"
    
    if [ "$DOC_COUNT" -lt 1000 ]; then
        echo "Warning: Index has fewer than 1000 documents. Regenerating data..."
        ./scripts/generate_data.sh
    else
        echo "Using existing index data"
    fi
else
    echo "Index '$INDEX_NAME' does not exist. Creating..."
    ./scripts/create_index.sh
    echo ""
    echo "Generating test data..."
    ./scripts/generate_data.sh
fi

echo ""
echo "=========================================="
echo "Generating query vector..."
echo "=========================================="
QUERY_VECTOR=$(./scripts/generate_query_vector.sh)
QUERY_VECTOR_FILE="/tmp/query_vector.json"
echo "$QUERY_VECTOR" > "$QUERY_VECTOR_FILE"
echo "Query vector saved to $QUERY_VECTOR_FILE"
echo ""

echo "=========================================="
echo "Running Performance Tests"
echo "=========================================="
echo ""

# Run basic query test
echo "TEST 1: Basic Query (size: 100)"
echo "--------------------------------"
./scripts/run_basic_query.sh "$QUERY_VECTOR_FILE"
BASIC_MEAN=$(grep "Mean:" /tmp/basic_query_stats.txt | awk '{print $2}')

echo ""
echo ""

# Run aggregation query test
echo "TEST 2: Aggregation Query (size: 0 with aggs)"
echo "--------------------------------"
./scripts/run_agg_query.sh "$QUERY_VECTOR_FILE"
AGG_MEAN=$(grep "Mean:" /tmp/agg_query_stats.txt | awk '{print $2}')

echo ""
echo "=========================================="
echo "Performance Comparison"
echo "=========================================="
echo ""

# Calculate speed difference
SPEED_DIFF=$(echo "scale=2; $BASIC_MEAN / $AGG_MEAN" | bc)

echo "Basic Query (size: 100):"
cat /tmp/basic_query_stats.txt
echo ""

echo "Aggregation Query (size: 0 with aggs):"
cat /tmp/agg_query_stats.txt
echo ""

echo "Speed Difference: Aggregation query is ${SPEED_DIFF}x faster"
echo ""

# Clean up
rm -f "$QUERY_VECTOR_FILE"

echo "Test completed!"

