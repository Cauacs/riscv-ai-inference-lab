# Results and evidence policy

Historical approximate observations are in the
[Qwen experiment](../experiments/qwen3-0.6b/README.md). They are owner-reported,
not recovered benchmark logs. Exact values and error bars remain pending
reproduction. Static RVV evidence is in
[the investigation](../docs/rvv-investigation.md); instruction counts are not
inference throughput. A newly captured one-thread/one-repetition run of the
existing normal build and corrected static scans are preserved in
[initialization evidence](evidence/README.md). This is a tooling smoke test,
not completion of the repeated baseline.

`benchmark.sh` creates unique `results/raw/<UTC>-<build>.<suffix>/` directories:

- per-thread JSON stdout, separate stderr diagnostics and exit status;
- exact shell-escaped commands, benchmark help/version and source status;
- model, executable and shared-library SHA-256 hashes;
- CMake cache, full compiler commands and recipe metadata when available;
- OS/kernel, CPU/ISA, RAM/swap, governors, frequencies, load and thermal snapshots.

`inspect-rvv.sh` creates separate raw reports with hashes, counts and samples.
`results/raw/` is ignored: local logs remain available without publishing large
or sensitive artifacts. Promote only reviewed small evidence files into version
control (e.g. `results/evidence/`). Strip private paths if necessary, but retain
all settings required to reproduce the claim; never alter measured values.
Models, build products and full assembly dumps are not committed.

## Before publishing a result

1. Record board/cooling/power, OS, kernel, compiler, exact llama.cpp revision and
   dirty status. A clean pinned source is preferred.
2. Record effective flags from `compile_commands.json`; CMake options alone are
   not sufficient. Preserve resolved library identity.
3. Record model source/revision, hash, quantization and GGUF metadata. Use UNKNOWN
   where provenance is missing, not a guessed value.
4. Record prompt/generation lengths, batch/ubatch, KV precision, context/depth,
   threads, repetitions, warmup, affinity and the exact command. pp/tg are separate.
5. Quiesce unrelated work; watch frequencies, temperatures and swap. Keep settings
   unchanged between builds or explain deviations. Repeat in alternating order.
6. Preserve all raw repetitions. Report mean/dispersion supported by the raw
   output, not the best run. Verify test success and comparable settings.
7. Separate static-code evidence, runtime profiling, performance and correctness.
   Tokens/s alone is not model-quality evidence or an RVV attribution.

The full 1/2/4/8-thread scalar sweep can take a long time. A short smoke test
checks tooling, not completion of the baseline roadmap.
