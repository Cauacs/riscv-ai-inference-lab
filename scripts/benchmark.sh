#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# -lt 1 || ${1:-} == --help ]]; then
    echo 'Usage: benchmark.sh MODEL [BUILD_DIR] [THREADS_CSV] [REPETITIONS]'
    echo 'Defaults: build/normal, 1,2,4,8, 3. Set LLAMA_SRC for source provenance.'
    [[ ${1:-} == --help ]] && exit 0 || exit 2
fi
[[ $# -le 4 ]] || { echo 'Too many arguments' >&2; exit 2; }
model=$(realpath -e -- "$1")
build=$(realpath -e -- "${2:-$root/build/normal}")
threads=${3:-1,2,4,8}; repetitions=${4:-3}
[[ $threads =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ && $repetitions =~ ^[1-9][0-9]*$ ]] || {
    echo 'Threads and repetitions must be positive integers' >&2; exit 2;
}
bench=$build/bin/llama-bench
[[ -f $model && -x $bench ]] || { echo 'Missing model or llama-bench' >&2; exit 2; }
mkdir -p "$root/results/raw"
out=$(mktemp -d "$root/results/raw/$(date -u +%Y%m%dT%H%M%SZ)-$(basename "$build").XXXXXX")
# Capture metadata before/after; do not claim this fixes clocks or thermal state.
snapshot() {
    date -u +%FT%TZ; uname -a
    grep . /etc/os-release
    [[ ! -r /etc/armbian-release ]] || grep . /etc/armbian-release
    lscpu; free -b; uptime
    grep -E '^(isa|hart isa|uarch|model name)' /proc/cpuinfo | sort -u
    for f in /sys/devices/system/cpu/cpufreq/policy*/{scaling_governor,scaling_cur_freq,scaling_min_freq,scaling_max_freq} /sys/class/thermal/thermal_zone*/{type,temp}; do
        [[ ! -r $f ]] || printf '%s: %s\n' "$f" "$(< "$f")"
    done
}
snapshot > "$out/system-before.txt" 2>&1
"$bench" --help > "$out/bench-help.txt" 2>&1
"$bench" --version > "$out/bench-version.txt" 2>&1
sha256sum "$model" "$bench" > "$out/sha256.txt"
# Hash actual build libraries, not just the small launcher.
find "$build" -type f -name '*.so*' -exec sha256sum {} + >> "$out/sha256.txt"
for f in CMakeCache.txt compile_commands.json lab-build.txt; do
    if [[ -f $build/$f ]]; then cp -- "$build/$f" "$out/$f"; else echo "$f=UNKNOWN" >> "$out/provenance.txt"; fi
done
src=${LLAMA_SRC:-}
if [[ -z $src && -f $build/CMakeCache.txt ]]; then
    src=$(awk -F= '/^CMAKE_HOME_DIRECTORY:INTERNAL=/{print substr($0,index($0,"=")+1)}' "$build/CMakeCache.txt")
fi
{
    echo 'board=Orange Pi RV2 (verify system snapshot if run elsewhere)'
    echo 'model_identity=verify GGUF metadata; filename alone is not proof'
    echo 'quantization=verify tensor types in GGUF; historical model is Q4_0'
    echo 'prompt=128 generation=128 batch=2048 ubatch=512 gpu_layers=0'
    echo 'KV_types=f16,f16 warmup=enabled; pp and tg are separate synthetic tests'
    echo 'context=llama-bench-managed; see raw output and pinned source (not CLI -c 2048)'
    echo "threads=$threads repetitions=$repetitions"
    if [[ -n $src ]] && git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
        printf 'llama_commit='; git -C "$src" rev-parse HEAD
        echo 'source_status:'; git -C "$src" status --short
    else echo 'llama_commit=UNKNOWN'; fi
    for lang in C CXX; do
        compiler=$(awk -F= -v key="CMAKE_${lang}_COMPILER:FILEPATH" '$1==key{print $2}' "$build/CMakeCache.txt" 2>/dev/null || true)
        if [[ -n $compiler && -x $compiler ]]; then "$compiler" --version; else echo "${lang}_compiler=UNKNOWN"; fi
    done
    env | grep -E '^(OMP_|OPENBLAS_|LD_LIBRARY_PATH=)' || true
} >> "$out/provenance.txt"
IFS=, read -r -a counts <<< "$threads"
for t in "${counts[@]}"; do
    cmd=("$bench" -m "$model" -t "$t" -p 128 -n 128 -r "$repetitions"
        -b 2048 -ub 512 -ngl 0 -ctk f16 -ctv f16 -o json)
    printf '%q ' "${cmd[@]}" >> "$out/commands.sh"; printf '\n' >> "$out/commands.sh"
    echo "Benchmark: threads=$t; output=$out/t$t.json"
    # stdout is machine-readable; diagnostics remain separate. Failures are not results.
    if "${cmd[@]}" > "$out/t$t.json" 2> "$out/t$t.stderr.log"; then
        echo "threads=$t exit=0" >> "$out/status.txt"
    else
        status=$?; echo "threads=$t exit=$status" >> "$out/status.txt"
        snapshot > "$out/system-after.txt" 2>&1
        echo "Benchmark failed; inspect $out" >&2; exit "$status"
    fi
done
snapshot > "$out/system-after.txt" 2>&1
echo "Saved raw results and provenance: $out"
