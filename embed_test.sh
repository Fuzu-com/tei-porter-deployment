#!/bin/bash

# Simple Infinity Embedding Performance Test
# Optimized for macOS compatibility

set -e

# Configuration
ENDPOINT="https://embed.fuzu.com/embeddings"
MODEL="janni-t/qwen3-embedding-0.6b-tei-onnx"
REQUESTS=${1:-100}  # Default 50 requests
CONCURRENT=${2:-6}  # Default 10 concurrent

echo "🚀 Simple Embedding Performance Test"
echo "===================================="
echo "Endpoint: $ENDPOINT"
echo "Requests: $REQUESTS"
echo "Concurrent: $CONCURRENT"
echo ""

# Test sentences of varying lengths (realistic use cases)
declare -a TEST_SENTENCES=(
    "Query"
    "Machine learning embeddings"
    "How do I implement text search using vector embeddings in my application?"
    "I need to build a recommendation system that can understand user preferences based on their browsing history and product descriptions. The system should be able to match users with relevant products by analyzing textual content like product titles, descriptions, and user reviews."
    "In the context of modern artificial intelligence and natural language processing applications, vector embeddings have become a fundamental component for representing textual data in high-dimensional spaces. These dense vector representations capture semantic relationships between words, phrases, and documents, enabling sophisticated search, recommendation, and classification systems. When implementing such systems in production environments, it's crucial to consider factors like embedding dimensionality, model selection, computational efficiency, and scalability to handle real-world data volumes and user loads."
)

# Sentence type labels for analysis
declare -a SENTENCE_LABELS=(
    "Short (1 word)"
    "Medium (3 words)" 
    "Question (13 words)"
    "Paragraph (47 words)"
    "Long text (95 words)"
)

# Create temp directory for results
TEMP_DIR=$(mktemp -d)
echo "Temp results: $TEMP_DIR"
echo ""
echo "Text lengths being tested:"
for i in "${!TEST_SENTENCES[@]}"; do
    word_count=$(echo "${TEST_SENTENCES[$i]}" | wc -w)
    echo "  ${SENTENCE_LABELS[$i]}: ${word_count} words"
done

# Function to make a single request
make_request() {
    local id=$1
    local sentence="$2"
    local sentence_type="$3"
    local start_time=$(date +%s.%N)
    
    local response=$(curl -s -w "%{http_code}" \
        -X POST "$ENDPOINT" \
        -H "Content-Type: application/json" \
        -H "User-Agent: SimpleTest/1.0" \
        -d "{\"model\": \"$MODEL\", \"input\": \"$sentence\"}")
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Extract HTTP status (last 3 characters)
    local http_code=${response: -3}
    
    # Count approximate tokens (words + punctuation)
    local token_count=$(echo "$sentence" | wc -w)
    
    # Log result: id,http_code,duration,sentence_type,token_count
    echo "$id,$http_code,$duration,$sentence_type,$token_count" >> "$TEMP_DIR/results.txt"
    
    if [ "$http_code" = "200" ]; then
        printf "✓"
    else
        printf "✗"
    fi
}

echo "Starting test..."
echo -n "Progress: "

# Record start time
start_test=$(date +%s.%N)

# Run requests with limited concurrency
for ((i=1; i<=REQUESTS; i++)); do
    # Limit concurrent jobs
    while [ $(jobs -r | wc -l) -ge $CONCURRENT ]; do
        sleep 0.1
    done
    
    # Rotate through test sentences
    sentence_index=$(((i - 1) % ${#TEST_SENTENCES[@]}))
    sentence="${TEST_SENTENCES[$sentence_index]}"
    sentence_label="${SENTENCE_LABELS[$sentence_index]}"
    
    make_request $i "$sentence" "$sentence_label" &
done

# Wait for all jobs to complete
wait

end_test=$(date +%s.%N)
total_time=$(echo "$end_test - $start_test" | bc -l)

echo ""
echo ""
echo "📊 Results:"
echo "==========="

# Count successes and failures
success_count=$(awk -F',' '$2 == 200' "$TEMP_DIR/results.txt" | wc -l)
total_count=$(wc -l < "$TEMP_DIR/results.txt")
failure_count=$((total_count - success_count))

echo "Total Requests: $total_count"
echo "Successful: $success_count"
echo "Failed: $failure_count"
echo "Success Rate: $(echo "scale=1; $success_count * 100 / $total_count" | bc -l)%"
echo ""

# Calculate timing statistics for successful requests
if [ $success_count -gt 0 ]; then
    echo "Overall Performance (successful requests):"
    awk -F',' '$2 == 200 {print $3}' "$TEMP_DIR/results.txt" | sort -n > "$TEMP_DIR/times.txt"
    
    # Calculate statistics
    avg_time=$(awk '{sum+=$1} END {print sum/NR}' "$TEMP_DIR/times.txt")
    min_time=$(head -n1 "$TEMP_DIR/times.txt")
    max_time=$(tail -n1 "$TEMP_DIR/times.txt")
    
    # Calculate median
    line_count=$(wc -l < "$TEMP_DIR/times.txt")
    if [ $((line_count % 2)) -eq 1 ]; then
        median_line=$(((line_count + 1) / 2))
        median_time=$(sed -n "${median_line}p" "$TEMP_DIR/times.txt")
    else
        median_line1=$((line_count / 2))
        median_line2=$((line_count / 2 + 1))
        median1=$(sed -n "${median_line1}p" "$TEMP_DIR/times.txt")
        median2=$(sed -n "${median_line2}p" "$TEMP_DIR/times.txt")
        median_time=$(echo "scale=3; ($median1 + $median2) / 2" | bc -l)
    fi
    
    printf "  Average Response Time: %.3f seconds\n" $avg_time
    printf "  Median Response Time:  %.3f seconds\n" $median_time
    printf "  Min Response Time:     %.3f seconds\n" $min_time
    printf "  Max Response Time:     %.3f seconds\n" $max_time
    echo ""
    
    # Performance breakdown by text length
    echo "Performance by Text Length:"
    echo "=========================="
    for label in "${SENTENCE_LABELS[@]}"; do
        # Get stats for this sentence type
        type_data=$(awk -F',' -v label="$label" '$2 == 200 && $4 == label {print $3}' "$TEMP_DIR/results.txt")
        if [ -n "$type_data" ]; then
            type_count=$(echo "$type_data" | wc -l)
            type_avg=$(echo "$type_data" | awk '{sum+=$1} END {print sum/NR}')
            type_min=$(echo "$type_data" | sort -n | head -n1)
            type_max=$(echo "$type_data" | sort -n | tail -n1)
            
            # Get token count for this type
            type_tokens=$(awk -F',' -v label="$label" '$2 == 200 && $4 == label {print $5; exit}' "$TEMP_DIR/results.txt")
            
            printf "  %s (%s tokens):\n" "$label" "$type_tokens"
            printf "    Count: %d, Avg: %.3fs, Min: %.3fs, Max: %.3fs\n" $type_count $type_avg $type_min $type_max
        fi
    done
    echo ""
fi

printf "Total Test Duration: %.2f seconds\n" $total_time
printf "Requests per Second: %.2f\n" $(echo "scale=2; $success_count / $total_time" | bc -l)

# Calculate token throughput
if [ $success_count -gt 0 ]; then
    total_tokens=$(awk -F',' '$2 == 200 {sum+=$5} END {print sum}' "$TEMP_DIR/results.txt")
    printf "Total Tokens Processed: %d\n" $total_tokens
    printf "Tokens per Second: %.2f\n" $(echo "scale=2; $total_tokens / $total_time" | bc -l)
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "🎉 Test completed!"

# Usage info
if [ $# -eq 0 ]; then
    echo ""
    echo "Usage: $0 [REQUESTS] [CONCURRENT]"
    echo "Example: $0 100 20    # 100 requests, 20 concurrent"
    echo ""
    echo "This script tests 5 different text lengths:"
    echo "  • Single word queries"  
    echo "  • Short phrases"
    echo "  • Questions" 
    echo "  • Paragraphs"
    echo "  • Long documents"
fi
