#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bench/profile_flye_cpu.sh [options]

Run a CPU Flye profiling baseline through scripts/run_flye_fixture.sh.

Options:
  --profile-dir PATH    Profile output directory. Default: ./out/m0/profiles/<fixture>-<timestamp>
  --fixture NAME        Fixture name. Default: toy-hifi
  --flye-dir PATH       Flye checkout path. Default: ./upstream-flye
  --threads N           Flye thread count. Default: 8
  --reads PATH          Custom reads path, forwarded to run_flye_fixture.sh
  --read-type TYPE      Custom read type, forwarded to run_flye_fixture.sh
  --genome-size SIZE    Genome size, forwarded to run_flye_fixture.sh
  --min-overlap N       Minimum overlap, forwarded to run_flye_fixture.sh
  --extra-arg ARG       Extra Flye argument. May be repeated.
  -h, --help            Show this help
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

fixture="toy-hifi"
profile_dir=""
flye_dir="${FLYE_DIR:-${repo_root}/upstream-flye}"
threads="${THREADS:-8}"
reads=""
read_type=""
genome_size=""
min_overlap=""
extra_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile-dir)
      profile_dir="$2"
      shift 2
      ;;
    --fixture)
      fixture="$2"
      shift 2
      ;;
    --flye-dir)
      flye_dir="$2"
      shift 2
      ;;
    --threads)
      threads="$2"
      shift 2
      ;;
    --reads)
      reads="$2"
      shift 2
      ;;
    --read-type)
      read_type="$2"
      shift 2
      ;;
    --genome-size)
      genome_size="$2"
      shift 2
      ;;
    --min-overlap)
      min_overlap="$2"
      shift 2
      ;;
    --extra-arg)
      extra_args+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "${profile_dir}" ]; then
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  profile_dir="${repo_root}/out/m0/profiles/${fixture}-${timestamp}"
fi

run_dir="${profile_dir}/run"
mkdir -p "${profile_dir}"

args=(
  --fixture "${fixture}"
  --flye-dir "${flye_dir}"
  --out-dir "${run_dir}"
  --threads "${threads}"
  --force
)

if [ -n "${reads}" ]; then args+=(--reads "${reads}"); fi
if [ -n "${read_type}" ]; then args+=(--read-type "${read_type}"); fi
if [ -n "${genome_size}" ]; then args+=(--genome-size "${genome_size}"); fi
if [ -n "${min_overlap}" ]; then args+=(--min-overlap "${min_overlap}"); fi

for extra in "${extra_args[@]}"; do
  args+=(--extra-arg "${extra}")
done

"${repo_root}/scripts/run_flye_fixture.sh" "${args[@]}"

python3 - "$profile_dir" "$run_dir" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

profile_dir = Path(sys.argv[1])
run_dir = Path(sys.argv[2])

metadata = {}
metadata_path = run_dir / "run_metadata.json"
if metadata_path.exists():
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))

time_log = (run_dir / "time.log").read_text(encoding="utf-8", errors="replace") if (run_dir / "time.log").exists() else ""

peak_rss_kb = None
match = re.search(r"Maximum resident set size .*?:\s*(\d+)", time_log)
if match:
    peak_rss_kb = int(match.group(1))
else:
    match = re.search(r"(\d+)\s+maximum resident set size", time_log)
    if match:
        peak_rss_kb = int(match.group(1)) // 1024

summary = {
    "profile_dir": str(profile_dir.resolve()),
    "run_dir": str(run_dir.resolve()),
    "elapsed_seconds": metadata.get("elapsed_seconds"),
    "peak_rss_kb": peak_rss_kb,
    "fixture": metadata.get("fixture"),
    "threads": metadata.get("threads"),
    "machine": metadata.get("machine"),
    "host": metadata.get("host"),
    "nvidia_smi": metadata.get("nvidia_smi"),
}

(profile_dir / "profile_summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "CPU profile complete: ${profile_dir}"
echo "Profile summary: ${profile_dir}/profile_summary.json"
