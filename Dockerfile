FROM opensearchproject/opensearch:3.4.0

# Configure OpenSearch for single-node development
ENV discovery.type=single-node
ENV bootstrap.memory_lock=true

# Expose OpenSearch port
EXPOSE 9200

# Security plugin will be disabled via DISABLE_SECURITY_PLUGIN in docker-compose

