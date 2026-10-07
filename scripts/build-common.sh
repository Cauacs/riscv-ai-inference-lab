#!/usr/bin/env bash
# Shared implementation; invoke build-llama.sh or build-llama-scalar.sh.
set -euo pipefail
mode=${1:?normal or scalar}; shift
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${1:-} == --help ]]; then
    echo "Usage: build-llama[-scalar].sh [llama.cpp-source] [--configure-only]"
    echo "Environment: CC, CXX, JOBS (default 2). Outputs stay in this lab's build/."
    exit 0
fi
src=${1:-$root/vendor/llama.cpp}
[[ $# -eq 0 ]] || shift
configure_only=false
if [[ ${1:-} == --configure-only ]]; then configure_only=true; shift; fi
[[ $# -eq 0 ]] || { echo 'Unexpected argument' >&2; exit 2; }
src=$(realpath -e -- "$src")
[[ -f $src/ggml/CMakeLists.txt ]] || { echo 'Not a llama.cpp checkout' >&2; exit 2; }
[[ $(uname -m) == riscv64 ]] || { echo 'This build recipe requires native riscv64 Linux' >&2; exit 2; }
cc=${CC:-gcc}; cxx=${CXX:-g++}
# Avoid inherited flags silently changing the experiment.
[[ -z ${CFLAGS:-}${CXXFLAGS:-}${CPPFLAGS:-}${LDFLAGS:-} ]] || {
    echo 'Unset CFLAGS/CXXFLAGS/CPPFLAGS/LDFLAGS; recipe records explicit flags only.' >&2; exit 2;
}
build=$root/build/$mode
mkdir -p "$build"
exec > >(tee "$build/build.log") 2>&1
"$cc" --version; "$cxx" --version
"$cc" -Q --help=target || true
isa=$(awk -F ': *' '/^isa[[:space:]]*:/{print $2; exit}' /proc/cpuinfo)
[[ $isa == rv64* ]] || { echo 'Cannot verify CPU ISA in /proc/cpuinfo'; exit 2; }
base=${isa%%_*}
rvv=OFF; zfh=OFF; zvfh=OFF; pause=OFF
march=rv64gc
if [[ $mode == normal ]]; then
    [[ $base == *v* ]] || { echo 'CPU ISA does not report V'; exit 2; }
    rvv=ON; march=rv64gcv
fi
if [[ _$isa\_ == *_zfh_* ]]; then zfh=ON; march+=_zfh; fi
if [[ $rvv == ON && _$isa\_ == *_zvfh_* ]]; then zvfh=ON; march+=_zvfh; fi
if [[ _$isa\_ == *_zihintpause_* ]]; then pause=ON; march+=_zihintpause; fi
flags="-march=$march -mabi=lp64d"
if [[ $mode == scalar ]]; then
    # GCC flags: disable loop and basic-block (SLP) auto-vectorization.
    "$cc" --version | grep -qiE 'gcc|Free Software Foundation' || {
        echo 'Scalar recipe currently supports GCC only'; exit 2;
    }
    flags+=' -fno-tree-loop-vectorize -fno-tree-slp-vectorize'
fi
# Probe both compilers. CMake also sets per-target -march; inspect compile_commands.json.
printf 'int main(void){return 0;}\n' | "$cc" $flags -x c -c -o /dev/null -
printf 'int main(){return 0;}\n' | "$cxx" $flags -x c++ -c -o /dev/null -
for option in GGML_RVV GGML_RV_ZFH GGML_RV_ZVFH GGML_RV_ZICBOP GGML_RV_ZIHINTPAUSE; do
    grep -q "option($option " "$src/ggml/CMakeLists.txt" || {
        echo "Missing upstream option $option; review this recipe for this revision"; exit 2;
    }
done
args=(-S "$src" -B "$build" -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx"
    -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags"
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DBUILD_SHARED_LIBS=ON
    -DGGML_NATIVE=OFF -DGGML_CPU_ALL_VARIANTS=OFF -DGGML_CPU=ON
    -DGGML_RVV="$rvv" -DGGML_RV_ZFH="$zfh" -DGGML_RV_ZVFH="$zvfh"
    -DGGML_RV_ZICBOP=OFF -DGGML_RV_ZIHINTPAUSE="$pause"
    -DGGML_RV_ZVFBFWMA=OFF -DGGML_XTHEADVECTOR=OFF
    -DGGML_BLAS=OFF -DGGML_OPENMP=ON -DGGML_CPU_REPACK=ON
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_MTMD=OFF)
{
    date -u +%FT%TZ
    echo "mode=$mode cpu_isa=$isa"
    echo "llama_commit=$(git -C "$src" rev-parse HEAD)"
    git -C "$src" status --short
    printf 'cmake '; printf '%q ' "${args[@]}"; printf '\n'
} > "$build/lab-build.txt"
cmake "${args[@]}"
if ! "$configure_only"; then
    cmake --build "$build" --target llama-cli llama-bench -j "${JOBS:-2}"
fi
echo "Artifacts: $build; metadata: lab-build.txt, CMakeCache.txt, compile_commands.json"
