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
  --apply-patches        Apply cuFlye patches for the expected Flye ref
  --clean                Run make clean before building
  --skip-version-check   Do not enforce expected ref/commit
  --manifest PATH        Build manifest path. Default: ./out/m0/build_manifest.json
  -h, --help             Show this help

Environment:
  CUFLYE_FETCH_UPSTREAM=1  Same as --fetch-upstream
  CUFLYE_APPLY_PATCHES=1   Same as --apply-patches
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
apply_patches="${CUFLYE_APPLY_PATCHES:-0}"
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
    --apply-patches)
      apply_patches=1
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

make_args=("THREADS=${jobs}")
machine="$(uname -m)"
case "${machine}" in
  aarch64)
    # Upstream Flye's top-level Makefile only special-cases macOS arm64.
    # Linux/aarch64 DGX builds need these variables so vendored minimap2 uses
    # the NEON path instead of x86 SSE flags.
    make_args+=("aarch64=1" "arm_neon=1")
    ;;
esac

mkdir -p "$(dirname "${manifest}")"

clone_upstream() {
  local tmp_dir
  local attempt
  tmp_dir="${flye_dir}.tmp.$$"
  rm -rf "${tmp_dir}"
  for attempt in 1 2 3; do
    echo "Cloning Flye ${expected_ref} into ${flye_dir} (attempt ${attempt}/3)"
    if git clone --depth 1 --branch "${expected_ref}" \
      https://github.com/mikolmogorov/Flye.git "${tmp_dir}"; then
      rm -rf "${flye_dir}"
      mv "${tmp_dir}" "${flye_dir}"
      return 0
    fi
    rm -rf "${tmp_dir}"
    sleep "$((attempt * 5))"
  done
  echo "Failed to clone Flye after 3 attempts." >&2
  return 1
}

if [ -d "${flye_dir}" ] && [ ! -d "${flye_dir}/.git" ]; then
  if [ "${fetch_upstream}" = "1" ]; then
    rm -rf "${flye_dir}"
  else
    echo "Flye path exists but is not a git checkout: ${flye_dir}" >&2
    exit 1
  fi
fi

if [ -d "${flye_dir}/.git" ] && ! git -C "${flye_dir}" rev-parse --verify HEAD >/dev/null 2>&1; then
  if [ "${fetch_upstream}" = "1" ]; then
    rm -rf "${flye_dir}"
  else
    echo "Flye checkout exists but has no valid HEAD: ${flye_dir}" >&2
    exit 1
  fi
fi

if [ ! -d "${flye_dir}/.git" ]; then
  if [ "${fetch_upstream}" = "1" ]; then
    mkdir -p "$(dirname "${flye_dir}")"
    clone_upstream
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
applied_patch_names=()

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

apply_patch_set() {
  local patch_dir
  local patch_file
  patch_dir="${repo_root}/patches/flye/${expected_ref}"
  if [ ! -d "${patch_dir}" ]; then
    echo "No cuFlye patch directory for Flye ${expected_ref}: ${patch_dir}"
    return 0
  fi

  while IFS= read -r patch_file; do
    [ -n "${patch_file}" ] || continue
    if git -C "${flye_dir}" apply --check "${patch_file}"; then
      git -C "${flye_dir}" apply "${patch_file}"
      applied_patch_names+=("$(basename "${patch_file}")")
    elif git -C "${flye_dir}" apply --reverse --check "${patch_file}"; then
      echo "Patch already applied: $(basename "${patch_file}")"
      applied_patch_names+=("$(basename "${patch_file}")")
    else
      echo "Patch cannot be applied cleanly: ${patch_file}" >&2
      exit 1
    fi
  done < <(find "${patch_dir}" -maxdepth 1 -type f -name '*.patch' | sort)
}

if [ "${apply_patches}" = "1" ]; then
  apply_patch_set
fi

if [ "${clean}" = "1" ]; then
  make -C "${flye_dir}" clean "${make_args[@]}"
fi

# Keep top-level prerequisites sequential. Flye's samtools configure links
# against vendored minimap2, so running top-level minimap2 and samtools targets
# concurrently can race on clean checkouts. THREADS still controls sub-makes.
make -C "${flye_dir}" -j 1 "${make_args[@]}"

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
  "$actual_commit" "$actual_tags" "$actual_branch" "$jobs" "${make_args[*]}" \
  "$apply_patches" "${applied_patch_names[*]}" <<'PY'
import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone

manifest, repo_root, flye_dir, expected_ref, expected_commit, actual_commit, actual_tags, actual_branch, jobs, make_args, apply_patches, applied_patch_names = sys.argv[1:]

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
    "make_args": make_args.split(),
    "apply_patches": apply_patches == "1",
    "applied_patches": applied_patch_names.split(),
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
