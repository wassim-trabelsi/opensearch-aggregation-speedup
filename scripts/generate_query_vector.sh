#!/bin/bash

# Script to generate a random 1536-dimensional unit vector (norm = 1)
# Usage: ./scripts/generate_query_vector.sh
# Output: JSON array of 1536 floats

set -e

DIMENSION=1536

# Generate random vector and normalize to unit length
python3 << EOF
import json
import random
import math

# Generate random vector
vector = [random.gauss(0, 1) for _ in range($DIMENSION)]

# Calculate norm
norm = math.sqrt(sum(x * x for x in vector))

# Normalize to unit length
unit_vector = [x / norm for x in vector]

# Verify norm is approximately 1
actual_norm = math.sqrt(sum(x * x for x in unit_vector))
assert abs(actual_norm - 1.0) < 1e-10, f"Norm should be 1.0, got {actual_norm}"

# Output as JSON array
print(json.dumps(unit_vector))
EOF

