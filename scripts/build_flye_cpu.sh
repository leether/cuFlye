#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build_flye_cpu.sh [options]

Build the pinned CPU Flye reference checkout used by cuFlye M0.

Options:
  --flye-dir PATH        Flye checkout path. Default: ./upstream-flye
  --ref REF              Expected Flye tag/ref. Default: 2.9.6
  --expected-commit SHA  Expected commit prefix. Default: 886b8c1
  --jobs N              Build parallelism. Default: nproc/sysctl fallback
  --fetch-upstream       Clone the expected Flye ref if --flye-dir is missing
  --clean                Run make clean before building
  --skip-version-check   Do not enforce expected ref/commit
  --manifest PATH        Build manifest path. Default: ./out/m0/build_manifest.json
  -h, --help             Show this help

Environment:
  CUFLYE_FETCH_UPSTREAM=1  Same as --fetch-upstream
  FLYE_DIR=PATH            Same as --flye-dir
  FLYE_REF=REF             Same as --ref
  JOBS=N                   Same as --jobs
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

flye_dir="${FLYE_DIR:-${repo_root}/upstream-flye}"
expected_ref="${FLYE_REF:-2.9.6}"
expected_commit="886b8c1"
jobs="${JOBS:-}"
fetch_upstream="${CUFLYE_FETCH_UPSTREAM:-0}"
clean=0
skip_version_check=0
manifest="${repo_root}/out/m0/build_manifest.json"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --flye-dir)
      flye_dir="$2"
      shift 2
      ;;
    --ref)
      expected_ref="$2"
      shift 2
      ;;
    --expected-commit)
      expected_commit="$2"
      shift 2
      ;;
    --jobs)
      jobs="$2"
      shift 2
      ;;
    --fetch-upstream)
      fetch_upstream=1
      shift
      ;;
    --clean)
      clean=1
      shift
      ;;
    --skip-version-check)
      skip_version_check=1
      shift
      ;;
    --manifest)
      manifest="$2"
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

if [ -z "${jobs}" ]; then
  if command -v nproc >/dev/null 2>&1; then
    jobs="$(nproc)"
  elif command -v sysctl >/dev/null 2>&1; then
    jobs="$(sysctl -n hw.ncpu)"
  else
    jobs=4
  fi
fi

mkdir -p "$(dirname "${manifest}")"

if [ ! -d "${flye_dir}/.git" ]; then
  if [ "${fetch_upstream}" = "1" ]; then
    mkdir -p "$(dirname "${flye_dir}")"
    git clone --depth 1 --branch "${expected_ref}" \
      https://github.com/mikolmogorov/Flye.git "${flye_dir}"
  else
    cat >&2 <<EOF
Flye checkout not found: ${flye_dir}

Run one of:
  scripts/build_flye_cpu.sh --fetch-upstream
  git clone --depth 1 --branch ${expected_ref} https://github.com/mikolmogorov/Flye.git ${flye_dir}
EOF
    exit 1
  fi
fi

actual_commit="$(git -C "${flye_dir}" rev-parse --short=12 HEAD)"
actual_tags="$(git -C "${flye_dir}" tag --points-at HEAD | tr '\n' ' ')"
actual_branch="$(git -C "${flye_dir}" branch --show-current || true)"

if [ "${skip_version_check}" != "1" ]; then
  if ! printf '%s\n' "${actual_tags}" | grep -Eq "(^|[[:space:]])${expected_ref}([[:space:]]|$)" &&
     ! printf '%s\n' "${actual_commit}" | grep -q "^${expected_commit}"; then
    cat >&2 <<EOF
Unexpected Flye checkout:
  path: ${flye_dir}
  expected tag/ref: ${expected_ref}
  expected commit prefix: ${expected_commit}
  actual commit: ${actual_commit}
  actual tags: ${actual_tags}

Use --skip-version-check only for deliberate experiments.
EOF
    exit 1
  fi
fi

if [ "${clean}" = "1" ]; then
  make -C "${flye_dir}" clean
fi

make -C "${flye_dir}" -j "${jobs}"

required_bins=(
  "${flye_dir}/bin/flye"
  "${flye_dir}/bin/flye-modules"
  "${flye_dir}/bin/flye-minimap2"
  "${flye_dir}/bin/flye-samtools"
)

for bin_path in "${required_bins[@]}"; do
  if [ ! -x "${bin_path}" ]; then
    echo "Required executable missing after build: ${bin_path}" >&2
    exit 1
  fi
done

python3 - "$manifest" "$repo_root" "$flye_dir" "$expected_ref" "$expected_commit" \
  "$actual_commit" "$actual_tags" "$actual_branch" "$jobs" <<'PY'
import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone

manifest, repo_root, flye_dir, expected_ref, expected_commit, actual_commit, actual_tags, actual_branch, jobs = sys.argv[1:]

def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT).strip()
    except Exception as exc:
        return f"unavailable: {exc}"

payload = {
    "created_at_utc": datetime.now(timezone.utc).isoformat(),
    "repo_root": os.path.abspath(repo_root),
    "flye_dir": os.path.abspath(flye_dir),
    "expected_ref": expected_ref,
    "expected_commit_prefix": expected_commit,
    "actual_commit": actual_commit,
    "actual_tags": actual_tags.split(),
    "actual_branch": actual_branch or None,
    "jobs": int(jobs),
    "host": platform.node(),
    "platform": platform.platform(),
    "machine": platform.machine(),
    "python": sys.version.split()[0],
    "make": run(["make", "--version"]).splitlines()[0],
    "gcc": run(["gcc", "--version"]).splitlines()[0] if shutil.which("gcc") else None,
    "gxx": run(["g++", "--version"]).splitlines()[0] if shutil.which("g++") else None,
    "flye_version": run([os.path.join(flye_dir, "bin", "flye"), "--version"]),
}

os.makedirs(os.path.dirname(manifest), exist_ok=True)
with open(manifest, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

echo "Built Flye CPU reference at ${flye_dir}"
echo "Build manifest: ${manifest}"
