# RVV investigation: code presence versus execution

## Question

Does the running inference workload actually use useful RISC-V vector code, and
how much does it help? RVV can accelerate quantized dot products, conversion and
other elementwise operations. It cannot eliminate serial dependencies, memory
traffic or thread coordination.

The original executable-only search was:

```bash
objdump -d -C build/bin/llama-bench \
  | grep -E '\bvsetvli|\bvsetivli|\bvle[0-9]+\.v|\bvse[0-9]+\.v|\bvfm[a-z]*\.v|\bvmul\.v'
```

A missing match is interesting but **does not establish missing RVV support**.
Possible explanations include target flags without V, architecture detection,
unimplemented kernels for a particular tensor type, auto-vectorization limits,
incomplete mnemonic filters, old disassemblers or code in another library.

## Evidence recovered from the board

Source: llama.cpp `eec18f5d32099fb15d4ba15003a231bcc72757d5`, clean checkout
when inspected at `/home/caua/playground/llama.cpp`. GCC/G++ 14.2.0, Release.
Both builds use shared libraries, OpenMP and CPU repacking; BLAS is off.

| Existing artifact | Lines matching the original regex |
|---|---:|
| normal `build/bin/llama-bench` | 0 |
| normal `build/bin/libggml-cpu.so` | 15,352 |
| scalar `build-scalar/bin/llama-bench` | 0 |
| scalar `build-scalar/bin/libggml-cpu.so` | 0 |

These are static instruction-line counts, not benchmark results or execution
counts. `llama-bench` is a small launcher (~15 KiB). `ldd` shows it loads
`libllama-bench-impl.so`, llama/GGML libraries and `libggml-cpu.so.0`.
The first observed RVV sequence in the normal CPU library was in
`ggml_cpu_fp32_to_bf16`:

```text
0000000000016b78 <ggml_cpu_fp32_to_bf16>:
   16b82: 0d007357  vsetvli t1,zero,e32,m1,ta,ma
```

Recovered per-target compile flags for `arch/riscv/quants.c`:

```text
normal: -O3 -DNDEBUG -march=rv64gcv_zfh_zvfh_zicbop_zihintpause -mabi=lp64d -fopenmp
scalar: -O3 -DNDEBUG -march=rv64gc_zfh_zicbop_zihintpause -mabi=lp64d -fopenmp
```

`GGML_RVV` is ON/OFF respectively. The historical scalar build had **no explicit
no-vectorization flags** in `compile_commands.json`; its CPU target lacked V.
The source contains RISC-V kernels in `ggml/src/ggml-cpu/arch/riscv/` and CMake
options to enable RVV. Thus “llama.cpp has no RVV support” is contradicted by
these local artifacts. Whether the relevant Q4_0 hot paths execute these
instructions remains open.

## Reproduce the static check

From this lab (or pass the existing absolute build path):

```bash
./scripts/inspect-rvv.sh build/normal
./scripts/inspect-rvv.sh build/scalar
# Only use ldd on trusted locally built binaries.
ldd build/normal/bin/llama-bench
objdump -d -C build/normal/bin/libggml-cpu.so > /tmp/ggml-cpu.asm
grep -E '\bvsetvli|\bvsetivli|\bvle[0-9]+\.v|\bvse[0-9]+\.v|\bvfm[a-z]*\.v|\bvmul\.v' /tmp/ggml-cpu.asm
```

The script scans executables and shared libraries (including versioned filenames);
set `SCAN_OBJECTS=1` to also scan intermediate objects and archives (potentially
very slow on the board). It saves counts, symbol-labelled samples, tool version
and hashes, and reports decoding errors. Its broader regex is still a heuristic.
Duplicate instructions may occur in objects, archives and final libraries: do
not sum them as distinct code. It does not automatically scan system libraries
or prove absence. Follow resolved dependencies and inspect disassembly manually
when results are surprising.

## Controlled build comparison

The new recipes use explicit board-verified target flags, `GGML_NATIVE=OFF`
(avoid opaque native inference), Release/O3, OpenMP, CPU repacking, no BLAS and
shared libraries in both builds. They omit unreported `zicbop`. Normal uses V
and reported `zvfh`; scalar omits V and `zvfh`, sets `GGML_RVV=OFF`, and adds
GCC `-fno-tree-loop-vectorize -fno-tree-slp-vectorize` to C and C++.
Scalar is a **scalar-intended baseline**, not a claim about every dependency.
CMake adds target flags too: verify the effective command, not just the cache.

This is a comparison of kernel paths and compiler vectorization together, not a
pure auto-vectorization ablation. Historical timings must not be attributed to
these new recipes until reproduced. A third build with RVV kernels enabled but
auto-vectorization disabled could help separate these effects.

## Next investigation

1. Measure `vlenb` and execute a minimal vector correctness test. Kernel-reported
   ISA is evidence, not a measurement of vector performance.
2. Check `compile_commands.json`, preprocessor macros (`__riscv_vector`) and
   `ggml/src/ggml-cpu/CMakeLists.txt`; ensure no later target flag overrides V.
3. Trace Q4_0 tensor handling, repacking and actual dot-product dispatch in
   `arch/riscv/quants.c` and `repack.cpp`. Locate quantized hot symbols in assembly.
4. Reproduce identical pp/tg tests in both builds; verify model hash and source.
5. Use `perf record/report` if the board's PMU/permissions permit it. Correlate
   sampled symbols and instruction addresses with disassembly. If unavailable,
   record that limitation and use scoped instrumentation/counters.
6. Test kernel correctness against a reference before claiming optimization;
   report pp and tg separately, with raw repetitions and thermal/frequency state.

No proof of runtime RVV coverage or quantified RVV speedup has been completed.
