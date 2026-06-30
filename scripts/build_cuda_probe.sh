#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build_cuda_probe.sh [options]

Build the standalone cuFlye CUDA runtime probe.

Options:
  --cuda-home PATH  CUDA toolkit root. Default: CUDA_HOME, CUDA_PATH, or /usr/local/cuda
  --cxx PATH        C++ compiler. Default: CXX or g++
  --out PATH        Output binary. Default: ./out/m1e/bin/cuflye-cuda-probe
  --manifest PATH   Build manifest path. Default: ./out/m1e/cuda_probe_build_manifest.json
  -h, --help        Show this help
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cuda_home="${CUDA_HOME:-${CUDA_PATH:-/usr/local/cuda}}"
cxx="${CXX:-g++}"
out_bin="${repo_root}/out/m1e/bin/cuflye-cuda-probe"
manifest="${repo_root}/out/m1e/cuda_probe_build_manifest.json"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --cuda-home)
      cuda_home="$2"
      shift 2
      ;;
    --cxx)
      cxx="$2"
      shift 2
      ;;
    --out)
      out_bin="$2"
      shift 2
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

include_dir="${cuda_home}/include"
if [ ! -r "${include_dir}/cuda_runtime_api.h" ]; then
  echo "CUDA runtime header not found: ${include_dir}/cuda_runtime_api.h" >&2
  exit 1
fi

machine="$(uname -m)"
lib_candidates=(
  "${cuda_home}/lib64"
  "${cuda_home}/lib"
)
case "${machine}" in
  aarch64|arm64)
    lib_candidates+=(
      "${cuda_home}/targets/sbsa-linux/lib"
      "${cuda_home}/targets/aarch64-linux/lib"
      "${cuda_home}/targets/aarch64-linux-gnu/lib"
    )
    ;;
  x86_64)
    lib_candidates+=("${cuda_home}/targets/x86_64-linux/lib")
    ;;
esac

lib_dir=""
for candidate in "${lib_candidates[@]}"; do
  if [ -r "${candidate}/libcudart.so" ] || [ -r "${candidate}/libcudart.dylib" ]; then
    lib_dir="${candidate}"
    break
  fi
done

if [ -z "${lib_dir}" ]; then
  echo "CUDA runtime library not found under ${cuda_home}" >&2
  exit 1
fi

mkdir -p "$(dirname "${out_bin}")" "$(dirname "${manifest}")"

"${cxx}" -std=c++11 -O2 -Wall -Wextra \
  -I"${include_dir}" "${repo_root}/cuda/cuflye_cuda_probe.cpp" \
  -L"${lib_dir}" -Wl,-rpath,"${lib_dir}" -lcudart \
  -o "${out_bin}"

python3 - "$manifest" "$repo_root" "$out_bin" "$cuda_home" "$include_dir" "$lib_dir" "$cxx" <<'PY'
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone

manifest, repo_root, out_bin, cuda_home, include_dir, lib_dir, cxx = sys.argv[1:]

def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT).strip()
    except Exception as exc:
        return f"unavailable: {exc}"

payload = {
    "created_at_utc": datetime.now(timezone.utc).isoformat(),
    "repo_root": os.path.abspath(repo_root),
    "repo_commit": run(["git", "-C", repo_root, "rev-parse", "HEAD"]),
    "output_binary": os.path.abspath(out_bin),
    "cuda_home": os.path.abspath(cuda_home),
    "include_dir": os.path.abspath(include_dir),
    "lib_dir": os.path.abspath(lib_dir),
    "compiler": cxx,
    "compiler_version": run([cxx, "--version"]),
    "host": platform.node(),
    "platform": platform.platform(),
    "machine": platform.machine(),
    "python": sys.version.split()[0],
}

with open(manifest, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

echo "Built cuFlye CUDA runtime probe: ${out_bin}"
echo "Build manifest: ${manifest}"
