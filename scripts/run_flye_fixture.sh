#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run_flye_fixture.sh [options]

Run a fixed CPU Flye fixture and capture metadata for M0 oracle comparisons.

Options:
  --fixture NAME       Fixture name: toy-hifi, toy-raw, or custom. Default: toy-hifi
  --flye-dir PATH      Flye checkout path. Default: ./upstream-flye
  --out-dir PATH       Output directory. Default: ./out/m0/runs/<fixture>-<timestamp>
  --threads N          Flye thread count. Default: 8
  --min-overlap N      Flye -m value. Default: 1000 for toy fixtures
  --genome-size SIZE   Flye -g value. Default: 500k for toy fixtures
  --reads PATH         Reads path. Required for --fixture custom
  --read-type TYPE     Flye read type for custom: pacbio-raw, pacbio-corr,
                       pacbio-hifi, nano-raw, nano-hq, nano-corr, subassemblies
  --extra-arg ARG      Extra Flye argument. May be repeated.
  --force              Remove existing output directory before running
  -h, --help           Show this help

Examples:
  scripts/run_flye_fixture.sh --out-dir out/m0/runs/toy-a
  scripts/run_flye_fixture.sh --fixture custom --reads reads.fq.gz \
    --read-type pacbio-raw --genome-size 40m --out-dir out/m0/runs/sample
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

fixture="toy-hifi"
flye_dir="${FLYE_DIR:-${repo_root}/upstream-flye}"
out_dir=""
threads="${THREADS:-8}"
min_overlap="1000"
genome_size="500k"
reads=""
read_type=""
force=0
extra_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fixture)
      fixture="$2"
      shift 2
      ;;
    --flye-dir)
      flye_dir="$2"
      shift 2
      ;;
    --out-dir)
      out_dir="$2"
      shift 2
      ;;
    --threads)
      threads="$2"
      shift 2
      ;;
    --min-overlap)
      min_overlap="$2"
      shift 2
      ;;
    --genome-size)
      genome_size="$2"
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
    --extra-arg)
      extra_args+=("$2")
      shift 2
      ;;
    --force)
      force=1
      shift
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

case "${fixture}" in
  toy-hifi)
    reads="${reads:-${flye_dir}/flye/tests/data/ecoli_500kb_reads_hifi.fastq.gz}"
    read_type="${read_type:-pacbio-corr}"
    genome_size="${genome_size:-500k}"
    min_overlap="${min_overlap:-1000}"
    ;;
  toy-raw)
    reads="${reads:-${flye_dir}/flye/tests/data/ecoli_500kb_reads.fastq.gz}"
    read_type="${read_type:-pacbio-raw}"
    genome_size="${genome_size:-500k}"
    min_overlap="${min_overlap:-1000}"
    ;;
  custom)
    if [ -z "${reads}" ] || [ -z "${read_type}" ]; then
      echo "--fixture custom requires --reads and --read-type" >&2
      exit 2
    fi
    ;;
  *)
    echo "Unknown fixture: ${fixture}" >&2
    exit 2
    ;;
esac

if [ -z "${out_dir}" ]; then
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  out_dir="${repo_root}/out/m0/runs/${fixture}-${timestamp}"
fi

flye_bin="${flye_dir}/bin/flye"
if [ ! -x "${flye_bin}" ]; then
  echo "Flye binary not found or not executable: ${flye_bin}" >&2
  echo "Run scripts/build_flye_cpu.sh first." >&2
  exit 1
fi

if [ ! -r "${reads}" ]; then
  echo "Reads file not found: ${reads}" >&2
  exit 1
fi

if [ -e "${out_dir}" ]; then
  if [ "${force}" = "1" ]; then
    rm -rf "${out_dir}"
  else
    echo "Output directory already exists: ${out_dir}" >&2
    echo "Use --force to replace it." >&2
    exit 1
  fi
fi

mkdir -p "${out_dir}"

read_flag=""
case "${read_type}" in
  pacbio-raw) read_flag="--pacbio-raw" ;;
  pacbio-corr) read_flag="--pacbio-corr" ;;
  pacbio-hifi) read_flag="--pacbio-hifi" ;;
  nano-raw) read_flag="--nano-raw" ;;
  nano-hq) read_flag="--nano-hq" ;;
  nano-corr) read_flag="--nano-corr" ;;
  subassemblies) read_flag="--subassemblies" ;;
  *)
    echo "Unsupported read type: ${read_type}" >&2
    exit 2
    ;;
esac

cmd=(
  "${flye_bin}"
  "${read_flag}" "${reads}"
  "-g" "${genome_size}"
  "-o" "${out_dir}"
  "-t" "${threads}"
  "-m" "${min_overlap}"
  "--debug"
)

if [ "${#extra_args[@]}" -gt 0 ]; then
  cmd+=("${extra_args[@]}")
fi

printf '%q ' "${cmd[@]}" > "${out_dir}/command.sh"
printf '\n' >> "${out_dir}/command.sh"

metadata_tmp="${out_dir}/run_metadata.pre.json"
python3 - "$metadata_tmp" "$repo_root" "$flye_dir" "$fixture" "$reads" "$read_type" "$genome_size" "$min_overlap" "$threads" "${cmd[@]}" <<'PY'
import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone

metadata_path, repo_root, flye_dir, fixture, reads, read_type, genome_size, min_overlap, threads, *cmd = sys.argv[1:]

def run(cmdline):
    try:
        return subprocess.check_output(cmdline, text=True, stderr=subprocess.STDOUT).strip()
    except Exception as exc:
        return f"unavailable: {exc}"

payload = {
    "started_at_utc": datetime.now(timezone.utc).isoformat(),
    "repo_root": os.path.abspath(repo_root),
    "repo_commit": run(["git", "-C", repo_root, "rev-parse", "HEAD"]),
    "flye_dir": os.path.abspath(flye_dir),
    "flye_commit": run(["git", "-C", flye_dir, "rev-parse", "HEAD"]),
    "flye_tags": run(["git", "-C", flye_dir, "tag", "--points-at", "HEAD"]).split(),
    "fixture": fixture,
    "reads": os.path.abspath(reads),
    "read_type": read_type,
    "genome_size": genome_size,
    "min_overlap": min_overlap,
    "threads": int(threads),
    "command": cmd,
    "host": platform.node(),
    "platform": platform.platform(),
    "machine": platform.machine(),
    "python": sys.version.split()[0],
    "nvidia_smi": run(["nvidia-smi", "-L"]) if shutil.which("nvidia-smi") else None,
}

with open(metadata_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

start_epoch="$(date +%s)"
time_log="${out_dir}/time.log"

if /usr/bin/time -v true >/dev/null 2>&1; then
  /usr/bin/time -v "${cmd[@]}" > "${out_dir}/stdout.log" 2> >(tee "${out_dir}/stderr.log" > "${time_log}")
elif /usr/bin/time -l true >/dev/null 2>&1; then
  /usr/bin/time -l "${cmd[@]}" > "${out_dir}/stdout.log" 2> >(tee "${out_dir}/stderr.log" > "${time_log}")
else
  "${cmd[@]}" > "${out_dir}/stdout.log" 2> "${out_dir}/stderr.log"
fi

end_epoch="$(date +%s)"
elapsed_seconds="$((end_epoch - start_epoch))"

python3 - "$metadata_tmp" "${out_dir}/run_metadata.json" "$elapsed_seconds" <<'PY'
import json
import sys
from datetime import datetime, timezone

src, dst, elapsed = sys.argv[1:]
with open(src, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
payload["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
payload["elapsed_seconds"] = int(elapsed)
payload["exit_status"] = 0
with open(dst, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
rm -f "${metadata_tmp}"

"${repo_root}/tools/canonicalize_flye_artifacts.py" --manifest "${out_dir}" \
  > "${out_dir}/artifact_hashes.json"

echo "Flye fixture run complete: ${out_dir}"
echo "Metadata: ${out_dir}/run_metadata.json"
echo "Artifact hashes: ${out_dir}/artifact_hashes.json"
