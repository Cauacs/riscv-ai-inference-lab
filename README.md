# riscv-ai-inference-lab

Experimental lab for understanding and optimizing local LLM inference on RISC-V
hardware. The current test platform is an Orange Pi RV2, with experiments covering
llama.cpp, Qwen, GGML kernels, compiler output, benchmarking, and RISC-V Vector
Extension (RVV) usage.

**Question:** How much LLM inference performance can we extract from a small
RISC-V board, and where are the actual bottlenecks?

This repository follows the path from model weights and GGUF quantization through
llama.cpp, GGML kernels, compiler output and RISC-V machine code to measured
performance. The aim is to explain changes with evidence, not just compare a
single tokens/s number.

## Platform and current stack

- Orange Pi RV2: SpacemiT X60, 8 RISC-V 64-bit cores, nominal 4 GB RAM.
- Armbian community / Debian 13; kernel `6.18.35-current-spacemit`.
- CPU ISA reported by Linux includes V, Zfh and Zvfh; vector length measurement
  remains TODO. See [hardware evidence](docs/hardware.md).
- GCC/G++ 14.2.0, CMake 3.31.6, binutils 2.44.
- llama.cpp pinned to `eec18f5d32099fb15d4ba15003a231bcc72757d5`
  in [`llama.cpp.commit`](llama.cpp.commit); GGML CPU backend, OpenMP, no BLAS.
- Qwen3 0.6B, GGUF / Q4_0; local file is 428,970,080 bytes.
  [Model provenance and hash](experiments/qwen3-0.6b/README.md).

## Work already done

Native llama.cpp builds, Qwen inference with `llama-cli`, `llama-bench` thread
sweeps, a scalar-intended comparison build and executable disassembly were
previously performed. The existing checkout, build caches, compiler commands,
model file and relevant shell commands were recovered on the board without
modifying them. Original benchmark output files were not recovered.

### Initial observations

| Historical build | Threads | Test | Approximate tokens/s |
|---|---:|---|---:|
| normal | 1 | pp128 | ~11.2 |
| scalar | 1 | pp128 | ~0.86 |
| scalar | 1 | tg128 | ~0.61 |
| scalar | 2 | pp128 | ~1.61 |

These are owner-reported observations, **pending controlled reproduction**;
exact original values, uncertainty and complete run conditions are unavailable.
Do not treat them as results from the new scripts. pp128 is prompt processing;
tg128 is token generation. They measure different workloads.

An initialization smoke test on the **existing** normal build measured pp128
11.185344 and tg128 4.325013 tokens/s at one thread, one repetition. This is not
the repeated baseline: [raw JSON, configuration and validation scope](results/evidence/README.md)
are preserved as small evidence files. Both new recipes passed compiler probes
and CMake configuration; their full compilation and benchmark sweep remain pending.

### Scalar versus normal

Recovered CPU-target flags enable V in the normal build and omit it in the
historical scalar build (`GGML_RVV=ON/OFF`). Both retain Release/O3 and OpenMP.
The new scripts make that contrast explicit and additionally disable GCC loop
and SLP auto-vectorization in the scalar build. Both use the same source, CPU
backend and repacking settings, with no BLAS. They deliberately omit old
`zicbop` flags because the kernel does not report that extension.

This is a kernel-path **and** compiler-vectorization comparison, not an isolated
measurement of automatic vectorization. A “scalar” label is an intended baseline,
not proof about every linked dependency. New builds need new measurements.

### RVV investigation

The executable-only search found no obvious RVV instructions. Inspection during
initialization found **15,352 instruction lines matching the original regex in
the normal `libggml-cpu.so`**, versus zero in the scalar library. The small
`llama-bench` launchers both had zero. The relevant code was in a shared library.

This establishes compiled RVV code, **not** runtime coverage of Q4_0 hot kernels
or its speedup. The investigation is open: locate dispatched kernels, profile
execution and correlate changes with reproducible benchmarks.
[Commands, evidence and next steps](docs/rvv-investigation.md).

## Layout

```text
README.md, LICENSE, .gitignore, llama.cpp.commit
docs/
  hardware.md             # measured configuration and limitations
  inference-stack.md      # model → quantization → kernels → instructions
  rvv-investigation.md    # static evidence and runtime questions
scripts/
  build-llama.sh          # explicit native RVV-enabled build
  build-llama-scalar.sh   # scalar-intended comparison
  build-common.sh         # shared capability checks / build recipe
  benchmark.sh            # pp128/tg128 + provenance collection
  inspect-rvv.sh          # executable, library and object scan
experiments/qwen3-0.6b/README.md
results/README.md         # evidence and comparison discipline
results/evidence/         # small reviewed smoke-test / static-scan artifacts
```

Generated `vendor/`, `build/` and `results/raw/` are ignored, not empty project
scaffolding. Weights are kept outside the repository.

## Reproduce on the board

Requirements: native riscv64 Linux, GCC/G++, CMake, Git, binutils, Python 3 (for
optional JSON analysis), standard GNU shell tools and OpenMP support. Debian
packages: `build-essential cmake git binutils`; Ninja is optional. These scripts
do not install packages, change CPU governors or modify an existing checkout.

From repository root, fetch the pinned upstream source into an ignored directory:

```bash
mkdir -p vendor
git clone https://github.com/ggml-org/llama.cpp.git vendor/llama.cpp
git -C vendor/llama.cpp checkout --detach "$(<llama.cpp.commit)"
./scripts/build-llama.sh
./scripts/build-llama-scalar.sh
```

Alternatively, reuse the recovered source read-only for out-of-tree builds:

```bash
./scripts/build-llama.sh "$HOME/playground/llama.cpp"
./scripts/build-llama-scalar.sh "$HOME/playground/llama.cpp"
```

Verify its revision against `llama.cpp.commit`. Builds land in this lab's
`build/normal` and `build/scalar`; existing `build`/`build-scalar` directories in
that source checkout are untouched. Default parallelism is 2 to limit memory
pressure on 4 GB RAM (`JOBS=4` to override). `--configure-only` after the source
argument checks configuration without compiling. Inspect `build.log`,
`lab-build.txt`, `CMakeCache.txt` and `compile_commands.json`; the scripts probe
flags but do not claim an optimal configuration. Scalar currently requires GCC.

With separately obtained, licensed weights:

```bash
MODEL="$HOME/models/Qwen3-0.6B-Q4_0.gguf"
./build/normal/bin/llama-cli -m "$MODEL" -ngl 0 -t 4 -c 2048 -n 128 \
  -p 'Explain the RISC-V vector extension in simple terms.'
./scripts/benchmark.sh "$MODEL" build/normal 1,2,4,8 3
./scripts/benchmark.sh "$MODEL" build/scalar 1,2,4,8 3
./scripts/inspect-rvv.sh build/normal
./scripts/inspect-rvv.sh build/scalar
```

The benchmark fixes pp/tg at 128 each, batch 2048, ubatch 512, f16 KV types and
zero GPU layers, with default warmup. These are **separate synthetic tests**;
CLI context 2048 is not the benchmark's context setting. Exact commands, model
and library hashes, source/compiler metadata and system snapshots are saved in
unique `results/raw/` directories. Existing builds can also be passed explicitly.
The scalar sweep may be slow. Consult [benchmark discipline](results/README.md)
before interpreting timings and [inference concepts](docs/inference-stack.md)
for a practical explanation of the stack.

## Roadmap (not completed)

### Phase 1 — Baseline

- Reproduce Qwen3 0.6B inference with saved output and model provenance.
- Record system/cooling configuration and establish a raw llama.cpp baseline.
- Compare 1/2/4/8 threads and normal versus scalar at the same revision.

### Phase 2 — Understand vectorization

- Verify runtime RVV capabilities and vector length.
- Inspect compiler target configuration and effective kernel flags.
- Locate vectorized GGML paths and inspect generated assembly.
- Determine which RVV kernels the workload actually executes.

### Phase 3 — Optimize

- Profile hot kernels and inspect their GGML implementations.
- Experiment with compiler flags and isolated changes; benchmark each.
- Potentially implement/modify an RVV kernel with correctness tests.

### Phase 4 — Expand

- Test additional quantizations and larger models that fit available RAM.
- Compare runtimes only where useful to answer a specific question.
- Investigate memory bandwidth/profiling and performance-per-memory tradeoffs.

## Related project and license

[RCT / RISC-V Compute Toolkit](https://github.com/Cauacs/riscv-compute-toolkit)
focuses on general reproducible RISC-V benchmarking. This lab is specifically
about AI inference, model formats and kernel optimization; it does not duplicate
RCT's general benchmarking framework.

Lab scripts and documentation: [MIT](LICENSE). llama.cpp and model weights retain
their own licenses; neither upstream source nor weights are vendored in Git.
