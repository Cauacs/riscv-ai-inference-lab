# From a model to instructions

```text
Qwen model architecture + tokenizer
↓
learned weights (parameters)
↓
GGUF file with metadata, tokenizer data and tensor payloads (here Q4_0)
↓
llama.cpp: model loading, tokenization, inference and sampling
↓
GGML: tensor operations, computation graph and backend dispatch
↓
CPU kernels: matrix products, dot products, normalization, attention, etc.
↓
compiler + assembler + linker
↓
RISC-V machine instructions in executables/shared libraries
↓
CPU: scalar units, vector units, caches and memory
```

This is a useful tracing path, not a literal runtime pipeline through a compiler:
compilation happens at build time. GGUF conversion/quantization usually happen
offline; the board loads already-converted weights.

## Model, parameters and tokens

A model combines a network architecture with learned numerical **parameters**:
mostly weights in matrices, plus other tensors. Inference applies these weights
to input data; it does not train them. Qwen3 0.6B denotes a roughly 0.6-billion-
parameter model, not a 0.6 GB file. Model labels are approximate: our artifact's
`llama-bench` tensor census reports 751,632,384 parameters. Precision and metadata
affect file size.

A **token** is an ID from the model's vocabulary, representing a text fragment
(or a special control marker). Tokenization maps text into IDs; tokens are not
necessarily words. The model predicts scores for possible next tokens; sampling
selects one, which is appended to the sequence.

**Prompt processing** (prefill) processes the input tokens, often in batches.
Matrix–matrix work can reuse weights across tokens. It also populates the
attention key/value (KV) cache.

**Token generation** (decode) produces successive new tokens. Each depends on
previous tokens, so a single sequence usually advances one token at a time.
Weight access and matrix–vector work can dominate; attention reads the growing
KV cache. Whether this board is compute- or bandwidth-limited is a measurement
question, not established here.

## Quantization and storage

**Quantization** stores weights with fewer bits, approximately preserving their
values with scales and sometimes other block metadata. It reduces weight memory
and bandwidth requirements, but changes numerical accuracy and kernel work.
It does not mean every inference operation uses low-bit arithmetic.

GGML's **Q4_0** packs 32 weight values into 16 bytes of 4-bit values plus a
2-byte half-precision scale per block: 18 bytes/32 weights, or 4.5 bits/weight
for tensors using this layout. Values are decoded with a block scale and an
integer offset (nominal signed range -8 to 7). Other tensors may have other
precisions. Therefore “4-bit model” is shorthand, not an exact total file-size
formula. Quantized dot products can use integer arithmetic and scaling rather
than materializing every weight as a float first.

**GGUF** is a file/container format for model metadata and tensor data, not a
quantization algorithm. A GGUF can hold multiple tensor types, including float
and different quantized formats. **GGML** is the tensor/computation library used
by llama.cpp; it is not the same thing as GGUF.

**llama.cpp** supplies model implementations, inference orchestration and tools
such as `llama-cli` and `llama-bench`. GGML schedules operations onto backends.
Its CPU backend implements **kernels**: low-level routines that perform specific
operations on tensors, including architecture-specific quantized dot products.

## Compiler and vector units

Scalar instructions typically operate on individual values. **SIMD/vectorization**
performs similar work on multiple elements per instruction. The compiler can
sometimes auto-vectorize loops; kernels can also explicitly use vector intrinsics
or assembly. Disabling auto-vectorization alone does not disable those explicit
kernels.

**RVV**, the RISC-V Vector Extension, supplies vector registers, loads/stores,
arithmetic and vector-length control. RVV code can be written to adapt to the
hardware vector length. `vsetvli` configures element width, register grouping and
active length; it is not itself a multiply. Flags, intrinsic support, data layout,
backend dispatch and kernel coverage determine whether useful work is vectorized.

The compiler converts C/C++ and intrinsics into machine code. In our recovered
build, most CPU kernel code is in `libggml-cpu.so`, not in the `llama-bench`
launcher. Static disassembly establishes instruction presence, not runtime use.

## What the benchmark measures

**Tokens/second** is processed/generated tokens divided by measured elapsed time
for a test. `pp128` measures processing 128 synthetic prompt tokens; `tg128`
measures generating 128 tokens in a separate test. They are not equivalent
workloads. `-p 128 -n 128` selects both separate tests; it does not select a
combined 128-token prompt followed by a 128-token continuation (`-pg` does that).

Benchmark tokens are synthetic, not a language-quality test or necessarily a
user's chat prompt. Initialization/model loading and interactive end-to-end
latency are different metrics. Batch sizes, KV types, depth/context, repetitions,
warmup, thread count, temperature and competing workloads matter. Compare the
same model hash, source revision and settings. A speed difference between scalar
and RVV builds is not by itself proof of which individual kernel caused it.
