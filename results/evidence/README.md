# Initialization evidence

The board clock reported 2026-10-07 (UTC). No independent clock verification.
These artifacts were captured from the **existing** llama.cpp builds, not the new
lab recipes. Source checkout was clean at capture:
`eec18f5d32099fb15d4ba15003a231bcc72757d5`.

## Throughput smoke test, not a completed baseline

Command (paths on the board):

```bash
/home/caua/playground/llama.cpp/build/bin/llama-bench \
  -m /home/caua/models/Qwen3-0.6B-Q4_0.gguf -t 1 -p 128 -n 128 -r 1 \
  -b 2048 -ub 512 -ngl 0 -ctk f16 -ctv f16 -o json
```

| Test | Measured tokens/s | Repetitions |
|---|---:|---:|
| pp128 | 11.185344 | 1 |
| tg128 | 4.325013 | 1 |

Full JSON is `normal-existing-t1-r1.json`. One repetition has no useful estimate
of run-to-run variability; the reported zero standard deviation is not evidence
of stability. Warmup was enabled. Benchmark context is tool-managed; these are
separate pp/tg tests, not a CLI prompt or combined pp+tg test. Model loading is
outside the reported token throughput. The 1/2/4/8-thread, repeated normal/scalar
baseline remains pending.

The tool identifies `qwen3 0.6B Q4_0` and reports 751,632,384 tensor parameters;
model naming is not an exact parameter census. It reports tensor payload size
423,018,496 bytes, versus 428,970,080 bytes for the complete GGUF file.
Model distributor/revision/conversion provenance remains UNKNOWN.

## Static scan

The corrected inspection script anchors matches to the instruction mnemonic
column, avoiding false positives in demangled names such as `std::vector`.
The broader filter counted 34,244 lines in the normal `libggml-cpu.so.0.25.3`,
zero in the scalar library. Normal: 16 files scanned, one with matches; scalar:
16 files, none with matches. These counts differ from the original narrow regex
(15,352 normal CPU-library matches) because the filters differ.

See `*-rvv-summary.txt`, `*-rvv-sha256.txt` and `normal-rvv-samples.txt` for
counts, artifact identity and representative symbols. Presence is not execution.
System snapshots are `system-before.txt` and `system-after.txt`.

## Captured hashes

```text
da2572f16c06133561ce56accaa822216f2391ef4d37fba427801cd6736417d4  /home/caua/models/Qwen3-0.6B-Q4_0.gguf
e7dce723f0ad209d2d0a96e2649dcefc621eedbfc231a21cae7815f09d95bb49  /home/caua/playground/llama.cpp/build/bin/llama-bench
4edd1110865a44505134d64dc8b091b77e302077b21cb4927f5956bd78ea9f51  /home/caua/playground/llama.cpp/build/bin/libllama-perplexity-impl.so
49e431f1945b46055a9e58bdf4e4bbe9c376873fe672e73b23d518df51c95f37  /home/caua/playground/llama.cpp/build/bin/libllama-fit-params-impl.so
3c2273da645c0674bd1e32eea675a04fa3b56af293e0ecdd73fb7c68ddff2b53  /home/caua/playground/llama.cpp/build/bin/libggml.so.0.25.3
1e11be67ae9756ac2788cfacdcb674a368d18d63c3f7404f6165b8cc188fc429  /home/caua/playground/llama.cpp/build/bin/libmtmd.so.0.5.0
11acaf96962ebad527c0414746b55f10544b2b8ab303a65b9c0a75c0918953e6  /home/caua/playground/llama.cpp/build/bin/libggml-base.so.0.25.3
1fbe0b0c170f609db8f1fd9aa8d7995f0782d9a1dc38c57ccfe304cce349721b  /home/caua/playground/llama.cpp/build/bin/libllama-quantize-impl.so
c5777b71b3f9357dd12d5e0215da07dd2c49bd1bd478a838c30d57819bd39263  /home/caua/playground/llama.cpp/build/bin/libllama-server-impl.so
560ea83b082c6f889859cbd041cd15fdc2680f7585ee06757e5ce08187c658b0  /home/caua/playground/llama.cpp/build/bin/libllama-cli-impl.so
cd5ed484f9a4012af4f44f288c435efea6dbd79ad62fa12e8aa5da3b593d91ed  /home/caua/playground/llama.cpp/build/bin/libllama.so.0.5.0
9f046863ecdbd72c531421c311ab2c1ef582df908eb6adcabac92172e7a277d6  /home/caua/playground/llama.cpp/build/bin/libggml-cpu.so.0.25.3
f18574dd0f6c22ba0b1973b0e48a53101f4c0037fbbf1d2e9d6599dce7e9b987  /home/caua/playground/llama.cpp/build/bin/libllama-common.so.0.5.0
fd9cd7f4f619a63e9a7462ab223648d1485e8be6e9a96e2115f8d59571877e52  /home/caua/playground/llama.cpp/build/bin/libllama-completion-impl.so
3d36e7d617a549ce037a475cebc380a11a750d20e18d0b92fdd78ee3f6c9cc49  /home/caua/playground/llama.cpp/build/bin/libllama-bench-impl.so
95acdd882c5a7b92ad3b80a8a394e06071da14c3ebc0cba5e757ab3f6f236508  /home/caua/playground/llama.cpp/build/bin/libllama-batched-bench-impl.so
```

## Effective recovered CPU-kernel commands

```text
normal: /usr/bin/cc -DGGML_BACKEND_BUILD -DGGML_BACKEND_SHARED -DGGML_SCHED_MAX_COPIES=4 -DGGML_SHARED -DGGML_USE_CPU_REPACK -DGGML_USE_LLAMAFILE -DGGML_USE_OPENMP -D_GNU_SOURCE -D_XOPEN_SOURCE=600 -Dggml_cpu_EXPORTS -I/home/caua/playground/llama.cpp/ggml/src/.. -I/home/caua/playground/llama.cpp/ggml/src/. -I/home/caua/playground/llama.cpp/ggml/src/ggml-cpu -I/home/caua/playground/llama.cpp/ggml/src/../include -O3 -DNDEBUG -std=gnu11 -fPIC -Wshadow -Wstrict-prototypes -Wpointer-arith -Wmissing-prototypes -Werror=implicit-int -Werror=implicit-function-declaration -Wall -Wextra -Wpedantic -Wcast-qual -Wno-unused-function -Wdouble-promotion -march=rv64gcv_zfh_zvfh_zicbop_zihintpause -mabi=lp64d -fopenmp -o ggml/src/CMakeFiles/ggml-cpu.dir/ggml-cpu/arch/riscv/quants.c.o -c /home/caua/playground/llama.cpp/ggml/src/ggml-cpu/arch/riscv/quants.c
scalar: /usr/bin/cc -DGGML_BACKEND_BUILD -DGGML_BACKEND_SHARED -DGGML_SCHED_MAX_COPIES=4 -DGGML_SHARED -DGGML_USE_CPU_REPACK -DGGML_USE_LLAMAFILE -DGGML_USE_OPENMP -D_GNU_SOURCE -D_XOPEN_SOURCE=600 -Dggml_cpu_EXPORTS -I/home/caua/playground/llama.cpp/ggml/src/.. -I/home/caua/playground/llama.cpp/ggml/src/. -I/home/caua/playground/llama.cpp/ggml/src/ggml-cpu -I/home/caua/playground/llama.cpp/ggml/src/../include -O3 -DNDEBUG -std=gnu11 -fPIC -Wshadow -Wstrict-prototypes -Wpointer-arith -Wmissing-prototypes -Werror=implicit-int -Werror=implicit-function-declaration -Wall -Wextra -Wpedantic -Wcast-qual -Wno-unused-function -Wdouble-promotion -march=rv64gc_zfh_zicbop_zihintpause -mabi=lp64d -fopenmp -o ggml/src/CMakeFiles/ggml-cpu.dir/ggml-cpu/arch/riscv/quants.c.o -c /home/caua/playground/llama.cpp/ggml/src/ggml-cpu/arch/riscv/quants.c
```

## Validation scope

- All lab shell files passed `bash -n`; shellcheck was unavailable.
- C/C++ flag probes and CMake configuration passed on the board for both new
  recipes. Effective `quants.c` commands use V/Zvfh for normal, omit both and
  include no-auto-vectorization flags for scalar.
- `benchmark.sh` successfully captured the existing normal build's one-thread,
  one-repetition pp/tg run and parseable JSON.
- `inspect-rvv.sh` completed for both existing build directories without decode
  errors; scalar had no mnemonic matches.
- Full compilation of the new recipes and their runtime benchmark sweep are
  **not yet performed**. No optimization claim is made.
- Existing source and model files were not modified.

Published system snapshots normalize trailing whitespace only; raw copies remain unchanged.
