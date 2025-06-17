#!/bin/bash

# Simple Infinity Reranker Performance Test
# Tests the reranker endpoint with various query-document combinations

set -e

# Configuration
ENDPOINT="https://rerank.fuzu.com/rerank"
MODEL="BAAI/bge-reranker-base"
REQUESTS=${1:-50}  # Default 50 requests
CONCURRENT=${2:-10}  # Default 10 concurrent

# Note: If you're getting 403 errors, the domain might be behind Cloudflare protection.
# You may need to use the Porter internal URL or configure Cloudflare to allow API access.

echo "🚀 Simple Reranker Performance Test"
echo "===================================="
echo "Endpoint: $ENDPOINT"
echo "Requests: $REQUESTS"
echo "Concurrent: $CONCURRENT"
echo ""

# Test queries of varying complexity
declare -a TEST_QUERIES=(
    "machine learning"
    "how to implement vector search"
    "What are the best practices for building a recommendation system?"
    "I need to understand how neural networks process natural language and generate embeddings for semantic search applications"
    "In modern information retrieval systems, the combination of dense vector embeddings and sparse keyword matching has proven to be highly effective. When implementing such hybrid search systems, it's crucial to understand how to properly weight the contributions from each approach and how reranking models can significantly improve the final result quality by considering the full context of both the query and candidate documents"
)

# Documents to rerank (varying lengths and relevance)
declare -a TEST_DOCUMENTS=(
    "Machine learning is a subset of artificial intelligence"
    "Deep learning uses neural networks with multiple layers"
    "Vector databases store high-dimensional embeddings for similarity search"
    "Recommendation systems analyze user behavior to suggest relevant items"
    "Natural language processing enables computers to understand human language"
    "Embeddings are dense vector representations of text in high-dimensional space"
    "Semantic search goes beyond keyword matching to understand meaning and context"
    "Hybrid search combines traditional keyword search with vector similarity"
    "Reranking models improve search results by considering query-document interactions"
    "Information retrieval has evolved from simple text matching to sophisticated AI systems"
)

# Query and document type labels
declare -a QUERY_LABELS=(
    "Short query (2 words)"
    "Medium query (5 words)"
    "Question (10 words)"
    "Long query (15 words)"
    "Complex query (75 words)"
)

# Create temp directory for results
TEMP_DIR=$(mktemp -d)
echo "Temp results: $TEMP_DIR"
echo ""
echo "Query complexity being tested:"
for i in "${!TEST_QUERIES[@]}"; do
    word_count=$(echo "${TEST_QUERIES[$i]}" | wc -w)
    echo "  ${QUERY_LABELS[$i]}: ${word_count} words"
done
echo ""
echo "Document pool: ${#TEST_DOCUMENTS[@]} documents"
echo ""

# Function to make a single rerank request
make_rerank_request() {
    local id=$1
    local query="$2"
    local query_type="$3"
    local start_time=$(date +%s.%N)
    
    # Create JSON array of documents
    local docs_json=$(printf '%s\n' "${TEST_DOCUMENTS[@]}" | jq -R . | jq -s .)
    
    # Create the full request payload
    local payload=$(jq -n \
        --arg model "$MODEL" \
        --arg query "$query" \
        --argjson documents "$docs_json" \
        '{model: $model, query: $query, documents: $documents}')
    
    local response=$(curl -s -w "%{http_code}" \
        -X POST "$ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -o "$TEMP_DIR/response_${id}.json")
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Extract HTTP status (last 3 characters)
    local http_code=${response: -3}
    
    # Count tokens in query
    local query_tokens=$(echo "$query" | wc -w)
    # Count total tokens (query + all documents)
    local doc_tokens=$(printf '%s\n' "${TEST_DOCUMENTS[@]}" | wc -w)
    local total_tokens=$((query_tokens + doc_tokens))
    
    # Log result: id,http_code,duration,query_type,query_tokens,total_tokens
    echo "$id,$http_code,$duration,$query_type,$query_tokens,$total_tokens" >> "$TEMP_DIR/results.txt"
    
    if [ "$http_code" = "200" ]; then
        printf "✓"
        # Extract top result score if available
        if [ -f "$TEMP_DIR/response_${id}.json" ]; then
            local top_score=$(jq -r '.[0].score // "N/A"' "$TEMP_DIR/response_${id}.json" 2>/dev/null || echo "N/A")
            echo "$id,$top_score" >> "$TEMP_DIR/scores.txt"
        fi
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
    
    # Rotate through test queries
    query_index=$(((i - 1) % ${#TEST_QUERIES[@]}))
    query="${TEST_QUERIES[$query_index]}"
    query_label="${QUERY_LABELS[$query_index]}"
    
    make_rerank_request $i "$query" "$query_label" &
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
    
    # Performance breakdown by query complexity
    echo "Performance by Query Complexity:"
    echo "================================"
    for label in "${QUERY_LABELS[@]}"; do
        # Get stats for this query type
        type_data=$(awk -F',' -v label="$label" '$2 == 200 && $4 == label {print $3}' "$TEMP_DIR/results.txt")
        if [ -n "$type_data" ]; then
            type_count=$(echo "$type_data" | wc -l)
            type_avg=$(echo "$type_data" | awk '{sum+=$1} END {print sum/NR}')
            type_min=$(echo "$type_data" | sort -n | head -n1)
            type_max=$(echo "$type_data" | sort -n | tail -n1)
            
            # Get token counts for this type
            type_query_tokens=$(awk -F',' -v label="$label" '$2 == 200 && $4 == label {print $5; exit}' "$TEMP_DIR/results.txt")
            type_total_tokens=$(awk -F',' -v label="$label" '$2 == 200 && $4 == label {print $6; exit}' "$TEMP_DIR/results.txt")
            
            printf "  %s:\n" "$label"
            printf "    Query tokens: %s, Total tokens: %s\n" "$type_query_tokens" "$type_total_tokens"
            printf "    Count: %d, Avg: %.3fs, Min: %.3fs, Max: %.3fs\n" $type_count $type_avg $type_min $type_max
        fi
    done
    echo ""
    
    # Score distribution analysis
    if [ -f "$TEMP_DIR/scores.txt" ] && [ -s "$TEMP_DIR/scores.txt" ]; then
        echo "Reranking Score Statistics:"
        echo "=========================="
        # Filter out N/A values and calculate stats
        grep -v "N/A" "$TEMP_DIR/scores.txt" | cut -d',' -f2 | sort -n > "$TEMP_DIR/valid_scores.txt" || true
        if [ -s "$TEMP_DIR/valid_scores.txt" ]; then
            score_count=$(wc -l < "$TEMP_DIR/valid_scores.txt")
            avg_score=$(awk '{sum+=$1} END {if(NR>0) print sum/NR; else print 0}' "$TEMP_DIR/valid_scores.txt")
            min_score=$(head -n1 "$TEMP_DIR/valid_scores.txt" 2>/dev/null || echo "0")
            max_score=$(tail -n1 "$TEMP_DIR/valid_scores.txt" 2>/dev/null || echo "0")
            
            printf "  Valid scores: %d\n" $score_count
            printf "  Average top score: %.4f\n" $avg_score
            printf "  Min top score: %.4f\n" $min_score
            printf "  Max top score: %.4f\n" $max_score
            echo ""
        fi
    fi
fi

printf "Total Test Duration: %.2f seconds\n" $total_time
printf "Requests per Second: %.2f\n" $(echo "scale=2; $success_count / $total_time" | bc -l)

# Calculate token throughput
if [ $success_count -gt 0 ]; then
    total_tokens_processed=$(awk -F',' '$2 == 200 {sum+=$6} END {print sum}' "$TEMP_DIR/results.txt")
    printf "Total Tokens Processed: %d\n" $total_tokens_processed
    printf "Tokens per Second: %.2f\n" $(echo "scale=2; $total_tokens_processed / $total_time" | bc -l)
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
    echo "This script tests reranking with:"
    echo "  • 5 query complexity levels (2-75 words)"
    echo "  • 10 diverse documents per request"
    echo "  • Performance metrics by query type"
    echo "  • Reranking score analysis"
fi