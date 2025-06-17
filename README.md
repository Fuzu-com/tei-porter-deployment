# TEI Porter Deployment

Deploy [Text Embeddings Inference (TEI)](https://github.com/huggingface/text-embeddings-inference) on [Porter](https://porter.run).

## Quick Start

1. **Copy the example configuration**:
   ```bash
   cp porter-example.yaml porter.yaml
   ```

2. **Configure porter.yaml**:
   - Replace `your-domain.example.com` with your actual domain
   - Optionally set `HF_TOKEN` if using private models

3. **Deploy**:
   ```bash
   porter apply
   ```

## Configuration

The deployment includes:
- **Model**: [janni-t/qwen3-embedding-0.6b-tei-onnx](https://huggingface.co/janni-t/qwen3-embedding-0.6b-tei-onnx) (public model)
- **Resources**: 3 CPU cores, 10GB RAM
- **Image**: AMD-optimized TEI CPU build
- **Backend**: ONNX runtime for fast CPU inference

## Environment Variables

### Option 1: Porter Dashboard (Recommended)
Set environment variables in Porter's Environment Groups for better security.

### Option 2: Command Line
```bash
porter apply --env HF_TOKEN=your_token_here
```

### Option 3: Direct Edit
Edit values directly in `porter.yaml` (not recommended for security).

## Performance Testing

The repository includes a performance testing script for embeddings:

```bash
./embed_test.sh          # Default: 100 requests, 3 concurrent
./embed_test.sh 200 10   # Custom: 200 requests, 10 concurrent
```

Tests various text lengths from single words to long documents, providing detailed performance metrics including response times and throughput.

## API Usage

Once deployed, the API is available at your configured domain:

```bash
curl -X POST https://your-domain.example.com/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "janni-t/qwen3-embedding-0.6b-tei-onnx",
    "input": "Your text here"
  }'
```

## Performance

With the ONNX-optimized Qwen3-0.6B model on AMD CPUs (t3a.2xlarge):
- Average response time: ~1.9s
- Throughput: ~38 tokens/second
- Supports up to 32,768 token sequences
- 1024-dimensional embeddings

## Model Information

The Qwen3-0.6B model:
- Publicly available (no authentication required)
- Multilingual support
- Optimized for CPU inference via ONNX
- Mean pooling built into the ONNX graph

## Porter Resources

- [Porter Documentation](https://docs.porter.run)
- [Porter CLI Reference](https://docs.porter.run/cli/overview)
- [Environment Variables](https://docs.porter.run/deploying-applications/environment-variables)

## License

MIT