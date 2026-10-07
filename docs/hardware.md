# Test platform

Collected directly from `orangepirv2` during repository initialization. The board's
UTC clock reported 2026-10-07; this is a machine timestamp, not independent clock
verification. Hardware identity agrees with `/etc/armbian-release` and `lscpu`.

| Item | Observed value |
|---|---|
| Board | Orange Pi RV2 |
| CPU / microarchitecture | SpacemiT X60 / `spacemit,x60` |
| Architecture | little-endian `riscv64` |
| Online CPUs | 8, CPUs 0–7 |
| RAM | nominal 4 GB; `free -h`: 3.7 GiB usable |
| Swap | 1.9 GiB configured; snapshot had 13 MiB used |
| OS | Armbian community 26.8.0-trunk.170, Debian 13 (trixie), 13.5 |
| Kernel | `6.18.35-current-spacemit` |
| Reported frequency range | 614.4–1600 MHz (`lscpu`), not measured sustained frequency |
| L1d / L1i | 256 KiB aggregate each, 8 instances each |
| L2 | 1 MiB aggregate, 2 instances |
| GCC / G++ | Debian 14.2.0-19, version 14.2.0 |
| Clang | Debian 19.1.7 (available, not the recovered build compiler) |
| CMake | 3.31.6 |
| Binutils / objdump | 2.44 |

`/proc/cpuinfo` reports:

```text
rv64imafdcv_zicbom_zicboz_zicntr_zicond_zicsr_zifencei_zihintpause_zihpm_zaamo_zalrsc_zfh_zfhmin_zca_zcd_zba_zbb_zbc_zbs_zkt_zve32f_zve32x_zve64d_zve64f_zve64x_zvfh_zvfhmin_zvkt_sscofpmf_sstc_svinval_svnapot_svpbmt
```

The base ISA includes `v`; `zfh` and `zvfh` are also reported. This supports
building RVV and half-precision paths. Runtime execution of a minimal RVV test
and an explicit `vlenb` measurement remain TODO. Do not assume vector length,
vector throughput, vendor matrix extensions, or all ISA extensions from the
marketing name. `zicbop` is **not** in this kernel-reported list; the new build
recipe disables it even though the old builds enabled it.

GCC's default target is `rv64imafdc_zicsr_zifencei`, ABI `lp64d`: the default
alone does not enable V. A compile probe accepted `-march=rv64gcv_zfh_zvfh
-mabi=lp64d`. The build scripts probe their complete selected flags using both
C and C++ compilers before CMake configuration.

## Collect configuration for each run

```bash
uname -a
lscpu
free -b
grep . /etc/os-release
grep . /etc/armbian-release
grep -E '^(isa|hart isa|uarch|model name)' /proc/cpuinfo
gcc --version
g++ --version
gcc -Q --help=target
cmake --version
```

`benchmark.sh` also captures governors, current/min/max frequencies, thermal
readings, load and memory before and after a run. These snapshots do not replace
continuous monitoring. Cooling, power supply, storage medium, ambient temperature
and historical governor settings are UNKNOWN. Record them before comparing runs.
Avoid competing workloads and swapping; note any affinity/governor changes rather
than silently changing system-wide settings. Eight threads need not be fastest.
