#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${1:-} == --help ]]; then
    echo 'Usage: inspect-rvv.sh [BUILD_DIR]; OBJDUMP selects the disassembler.'
    echo 'Set SCAN_OBJECTS=1 to include intermediate objects and archives (slow).'
    exit 0
fi
[[ $# -le 1 ]] || { echo 'Too many arguments' >&2; exit 2; }
build=$(realpath -e -- "${1:-$root/build/normal}")
objdump=${OBJDUMP:-objdump}
command -v "$objdump" >/dev/null
mkdir -p "$root/results/raw"
out=$(mktemp -d "$root/results/raw/$(date -u +%Y%m%dT%H%M%SZ)-rvv.XXXXXX")
"$objdump" --version > "$out/tool-version.txt"
# Broader than the original search: configuration, loads/stores, integer/FP,
# masks/reductions/conversions. Heuristic mnemonic filter, not an ISA decoder.
# Anchor to the mnemonic column, not demangled names (e.g. std::vector).
pattern='^[[:space:]]*[[:xdigit:]]+:[[:space:]]+v(setvli|setivli|setvl|l[a-z0-9]*|s[a-z0-9]*|f[a-z0-9]*|m[a-z0-9]*|w[a-z0-9]*|n[a-z0-9]*|a[a-z0-9]*|r[a-z0-9]*|c[a-z0-9]*|d[a-z0-9]*|x[a-z0-9]*|o[a-z0-9]*)[.[:space:]]'
printf 'RVV static scan: %s\n' "$build" | tee "$out/summary.txt"
failed=0; scanned=0; matched=0
find_args=(-type f '(' -name llama-bench -o -name llama-cli -o -name '*.so' -o -name '*.so.*')
if [[ ${SCAN_OBJECTS:-0} == 1 ]]; then find_args+=(-o -name '*.a' -o -name '*.o'); fi
find_args+=(')' -print0)
while IFS= read -r -d '' file; do
    scanned=$((scanned + 1))
    if ! "$objdump" -d -C --no-show-raw-insn "$file" > "$out/disassembly.tmp" 2> "$out/error.tmp"; then
        printf 'ERROR %s: ' "$file" | tee -a "$out/summary.txt"
        tr '\n' ' ' < "$out/error.tmp" | tee -a "$out/summary.txt"
        echo | tee -a "$out/summary.txt"; failed=1; continue
    fi
    count=$(grep -Ec "$pattern" "$out/disassembly.tmp" || true)
    printf '%s matching instruction lines | %s\n' "$count" "$file" | tee -a "$out/summary.txt"
    sha256sum "$file" >> "$out/sha256.txt"
    if [[ $count -gt 0 ]]; then
        matched=$((matched + 1))
        { echo "=== $file ==="; awk -v pat="$pattern" '
            /^[0-9a-f]+ <.*>:$/{symbol=$0}
            $0 ~ pat {if(n++<20){print symbol; print}}' "$out/disassembly.tmp"; } >> "$out/samples.txt"
    fi
done < <(find "$build" "${find_args[@]}")
rm -f -- "$out/disassembly.tmp" "$out/error.tmp"
{
    echo "Scanned=$scanned files; with matches=$matched; errors=$failed"
    echo 'Presence proves compiled code, NOT execution or performance benefit.'
    echo 'No match is inconclusive: filter/decoder/linked external libraries may miss code.'
    echo 'Use ldd on trusted local executables to locate libraries outside this build.'
    echo "Report: $out"
} | tee -a "$out/summary.txt"
[[ $scanned -gt 0 && $failed -eq 0 ]]
