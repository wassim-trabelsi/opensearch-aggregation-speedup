# Performance Issue: Basic Search Query Significantly Slower Than Aggregation-Based Query

## Summary

When executing a KNN vector search query, using `size: 100` to return top hits directly is **4.93x slower** than using `size: 0` with aggregations that return the same number of results. Both queries return identical result sets (100 items), but the basic query has significantly higher latency and variance.

## Expected Behavior

Both query approaches should have similar performance when returning the same number of results. The basic query (`size: 100`) should not be slower than an aggregation-based approach (`size: 0` with aggregations).

## Actual Behavior

The basic query (`query_basic`) is consistently slower:

- **Mean latency**: 29.98 ms
- **Median latency**: 28.49 ms
- **Min latency**: 27.81 ms
- **Max latency**: 59.72 ms
- **Standard deviation**: 4.47 ms

The aggregation-based query (`query_agg`) is significantly faster:

- **Mean latency**: 6.08 ms
- **Median latency**: 5.25 ms
- **Min latency**: 3.80 ms
- **Max latency**: 55.53 ms
- **Standard deviation**: 5.11 ms

**Speed difference**: query_agg is **4.93x faster** than query_basic.

## Reproduction Steps

### Prerequisites

- Docker and Docker Compose
- `curl`, `jq`, `bc`, `python3`, `awk` command-line tools

### Setup

```bash
# Start OpenSearch
docker-compose up -d

# Wait for OpenSearch to be ready (usually 30-60 seconds)
# Verify it's running:
curl http://localhost:9200

# Create index and generate test data
chmod +x scripts/*.sh
./scripts/create_index.sh
./scripts/generate_data.sh
```

### Query Definitions

Both queries use the same underlying `embedding_query` with KNN vector search:

```json
{
  "function_score": {
    "query": {
      "bool": {
        "must": [
          {
            "knn": {
              "sanitized_knowledge_record.embedding": {
                "vector": [/* 1536-dimensional vector */],
                "k": 1000,
                "boost": 0.97
              }
            }
          }
        ]
      }
    },
    "boost_mode": "sum"
  }
}
```

### Query 1: Basic Query (SLOW - 29.98 ms average)

```bash
# Generate a query vector first
QUERY_VECTOR=$(./scripts/generate_query_vector.sh)

# Run the basic query
curl -X POST "localhost:9200/test_index/_search" -H 'Content-Type: application/json' -d "{
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
  \"_source\": [\"raw_record.object\", \"price.float\"]
}"
```

### Query 2: Aggregation Query (FAST - 6.08 ms average)

```bash
# Use the same query vector
QUERY_VECTOR=$(./scripts/generate_query_vector.sh)

# Run the aggregation query
curl -X POST "localhost:9200/test_index/_search" -H 'Content-Type: application/json' -d "{
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
}"
```

### Automated Test Suite

For comprehensive testing with 100 iterations:

```bash
# Run full test suite (creates index, generates data, runs both queries 100 times)
./scripts/run_all_tests.sh

# Or run individual tests
./scripts/run_basic_query.sh
./scripts/run_agg_query.sh

# Verify both queries return the same results
./scripts/verify_same_results.sh
```

## Performance Test Results

Tested with 100 iterations on each query type:

### query_basic Results:

```
Mean: 29.98 ms
Median: 28.49 ms
Min: 27.81 ms
Max: 59.72 ms
Standard deviation: 4.47 ms
```

### query_agg Results:

```
Mean: 6.08 ms
Median: 5.25 ms
Min: 3.80 ms
Max: 55.53 ms
Standard deviation: 5.11 ms
```

### Performance Comparison

```
==========================================
Performance Comparison
==========================================

Basic Query (size: 100):
Mean: 29.98 ms
Median: 28.49 ms
Min: 27.81 ms
Max: 59.72 ms
Standard deviation: 4.47 ms

Aggregation Query (size: 0 with aggs):
Mean: 6.08 ms
Median: 5.25 ms
Min: 3.80 ms
Max: 55.53 ms
Standard deviation: 5.11 ms

Speed Difference: Aggregation query is 4.93x faster
```

## Cluster Configuration

- **OpenSearch Version**: 3.4.0
- **Cluster**: Single-node Docker container
- **Index**: `test_index` contains 9,000 documents with vector embeddings
- **KNN Field**: `sanitized_knowledge_record.embedding` (knn_vector type)
- **Vector Dimension**: 1536 (OpenAI text-embedding-ada-002 compatible)
- **KNN Algorithm**: HNSW with lucene engine
- **KNN k parameter**: 1000
- **Result size**: 100 items
- **Index Settings**:
  - Number of shards: 1
  - Number of replicas: 1
  - KNN enabled: true
  - ef_search: 100

## Additional Context

1. Both queries return the same number of results (100 items)
2. Both queries use identical underlying search logic (same `embedding_query`)
3. Both queries return identical product IDs (verified via `verify_same_results.sh`)
4. The aggregation query uses `size: 0` to avoid returning hits, then uses `top_hits` aggregation to get the same results
5. The performance difference is consistent across multiple iterations (100 iterations tested)
6. The basic query shows higher variance (stddev: 4.47 ms) compared to aggregation query (stddev: 5.11 ms), but the aggregation query has occasional outliers (max: 55.53 ms vs basic query max: 59.72 ms)

## Why Aggregations Are Not a Viable Workaround

While aggregations provide better performance, they cannot be used in all scenarios. Specifically, when using **search pipelines** for **hybrid search** (combining multiple query types), aggregations create a fundamental ordering problem:

1. **Search pipelines** must process query results in a specific order
2. **Aggregations** execute after the search pipeline processing
3. This means aggregations cannot be applied to pipeline-processed results

In hybrid search workflows, we need to:
- Apply search pipeline transformations to individual hits
- Combine results from multiple query sources (e.g., KNN + BM25)
- Process and re-rank the combined results
- Return the top N results

With aggregations, the pipeline processing happens first, but then aggregations group and filter results, which breaks the intended hybrid search flow. The `size` parameter is the correct approach for this use case, but it suffers from the performance issue documented here.

## Questions

1. Why is returning hits directly (`size: 100`) slower than using aggregations to achieve the same result?
2. Is there an optimization that can be applied to the basic query to match aggregation performance?
3. Can search pipelines and aggregations be made compatible, or should the basic query performance be improved?

## Impact

This performance difference creates a critical bottleneck for users implementing hybrid search with search pipelines:

- **Cannot use aggregations** due to pipeline processing order requirements
- **Must use `size` parameter** which is 4.93x slower
- **Forces suboptimal performance** in production hybrid search systems
- Makes queries more complex when aggregations are attempted as workarounds
- Requires understanding aggregation syntax even when it's not the right solution
- Creates inconsistent performance characteristics across different query patterns

## Plugins

Please list all plugins currently enabled.

**Default plugins enabled in OpenSearch 3.4.0:**
- opensearch-knn (for vector search)
- opensearch-security (disabled via DISABLE_SECURITY_PLUGIN=true)
- opensearch-performance-analyzer
- opensearch-alerting
- opensearch-anomaly-detection
- opensearch-asynchronous-search
- opensearch-cross-cluster-replication
- opensearch-custom-codecs
- opensearch-flow-framework
- opensearch-geospatial
- opensearch-index-management
- opensearch-job-scheduler
- opensearch-ltr
- opensearch-ml
- opensearch-neural-search
- opensearch-notifications
- opensearch-notifications-core
- opensearch-observability
- opensearch-reports-scheduler
- opensearch-search-relevance
- opensearch-security-analytics
- opensearch-skills
- opensearch-sql
- opensearch-system-templates
- opensearch-ubi
- query-insights


## Host/Environment (please complete the following information):

- **OS**: macOS (darwin 25.1.0)
- **OpenSearch Version**: 3.4.0

## Additional context

Add any other context about the problem here.

### Test Data

The test index contains 9,000 documents with:
- Random 1536-dimensional unit vectors (norm = 1) for KNN search
- Unique `product_info.reference` IDs (ref_0 through ref_8999)
- Sample product data in `raw_record.object`
- Random price values in `price.float`

### Scripts Provided

This repository includes automated scripts to reproduce the issue:

- `scripts/create_index.sh` - Creates the test index with proper KNN mapping
- `scripts/generate_data.sh` - Generates 9,000 test documents
- `scripts/generate_query_vector.sh` - Generates a random query vector
- `scripts/run_basic_query.sh` - Runs basic query performance test (100 iterations)
- `scripts/run_agg_query.sh` - Runs aggregation query performance test (100 iterations)
- `scripts/verify_same_results.sh` - Verifies both queries return identical results
- `scripts/run_all_tests.sh` - Orchestrates the full test suite

### Environment Variables

You can customize the setup:

- `OPENSEARCH_URL`: OpenSearch endpoint (default: `http://localhost:9200`)
- `INDEX_NAME`: Index name (default: `test_index`)
- `DOC_COUNT`: Number of documents to generate (default: `9000`)
- `ITERATIONS`: Number of test iterations (default: `100`)


# This code is mainly generated by AI but grounded with a lot of manual tests and experiments by hand.