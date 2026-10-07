# Qwen3 0.6B / Q4_0 on Orange Pi RV2

A small decoder model makes a practical first workload for a 4 GB SBC: weights
leave room for runtime buffers and a modest KV cache, builds/tests can be repeated,
and kernel behavior can be investigated without starting with an oversized model.
Small does not imply high answer quality or that all context sizes fit.

## Local artifact

- Model: Qwen3 0.6B, reported by the owner; file `Qwen3-0.6B-Q4_0.gguf`.
- Format: GGUF, intended Q4_0 quantization. Confirm tensor types from loader
  metadata; not every tensor must be Q4_0.
- Recovered path: `/home/caua/models/Qwen3-0.6B-Q4_0.gguf` (outside this repo).
- Size: 428,970,080 bytes.
- SHA-256: `da2572f16c06133561ce56accaa822216f2391ef4d37fba427801cd6736417d4`.
- Initialization `llama-bench` identified `qwen3 0.6B Q4_0` and reported
  751,632,384 tensor parameters; the model label is not an exact parameter count.
- Download source, model revision and conversion command: UNKNOWN.
- Upstream model: <https://huggingface.co/Qwen/Qwen3-0.6B>; the local GGUF's
  distributor/revision is not established by this link.

No weights are redistributed. Obtain weights separately under their applicable
license; record source URL, revision, conversion/quantization tool revision and
hash. A different distributor's GGUF need not reproduce this artifact.

## Run and benchmark

From repository root after building:

```bash
MODEL="$HOME/models/Qwen3-0.6B-Q4_0.gguf"
./build/normal/bin/llama-cli -m "$MODEL" -ngl 0 -t 4 -c 2048 -n 128 \
  -p 'Explain the RISC-V vector extension in simple terms.'
./scripts/benchmark.sh "$MODEL" build/normal 1,2,4,8 3
./scripts/benchmark.sh "$MODEL" build/scalar 1,2,4,8 3
```

The prompt/context reproduces a command recovered from shell history. Chat
formatting and Qwen3 thinking behavior can affect interactive output; capture
CLI configuration/output when comparing latency or correctness. Benchmark tests
use synthetic tokens and their own context, not that CLI prompt.

## Historical observations (owner-reported, approximate)

| Build | Threads | Test | tokens/s |
|---|---:|---|---:|
| normal | 1 | pp128 | ~11.2 |
| scalar | 1 | pp128 | ~0.86 |
| scalar | 1 | tg128 | ~0.61 |
| scalar | 2 | pp128 | ~1.61 |

Exact original outputs, dates, repetition statistics and full runtime environment
were not recovered. These entries are **pending controlled reproduction** and
are not measured results of the new build scripts. Shell history confirms loops
for threads 1,2,4,8 with `-p 128 -n 128 -r 3`. No additional historical timings
are inferred. See [results](../../results/README.md) for evidence rules.

A new one-thread/one-repetition smoke test of the existing normal build measured
pp128 11.185344 and tg128 4.325013 tokens/s. Raw JSON and configuration are in
[initialization evidence](../../results/evidence/README.md); this run does not
complete the repeated thread sweep or scalar comparison.

## Open questions

- Which quantized dot-product/repacking paths actually run, and which use RVV?
- Do pp and tg scale similarly with threads? Where does memory traffic dominate?
- How much of the scalar/normal difference is explicit kernels versus compiler
  auto-vectorization? Are thermals/clocks or swapping confounding it?
- Is another quantization a better accuracy/speed/memory tradeoff?
- How does longer context affect KV memory and decode throughput?
