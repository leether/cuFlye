#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build_cuda_read_window_smoke.sh [options]

Build the standalone cuFlye CUDA read-window smoke prototype.

Options:
  --cuda-home PATH  CUDA toolkit root. Default: CUDA_HOME, CUDA_PATH, or /usr/local/cuda
  --nvcc PATH       nvcc compiler. Default: NVCC, nvcc in PATH, or CUDA_HOME/bin/nvcc
  --arch ARCH       CUDA architecture. Default: CUFLYE_CUDA_ARCH or nvidia-smi compute_cap
  --out PATH        Output binary. Default: ./out/m1i/bin/cuflye-cuda-read-window-smoke
  --manifest PATH   Build manifest path. Default: ./out/m1i/cuda_read_window_smoke_build_manifest.json
  -h, --help        Show this help
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cuda_home="${CUDA_HOME:-${CUDA_PATH:-/usr/local/cuda}}"
nvcc="${NVCC:-}"
arch="${CUFLYE_CUDA_ARCH:-}"
out_bin="${repo_root}/out/m1i/bin/cuflye-cuda-read-window-smoke"
manifest="${repo_root}/out/m1i/cuda_read_window_smoke_build_manifest.json"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --cuda-home)
      cuda_home="$2"
      shift 2
      ;;
    --nvcc)
      nvcc="$2"
      shift 2
      ;;
    --arch)
      arch="$2"
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

if [ -z "${nvcc}" ]; then
  if command -v nvcc >/dev/null 2>&1; then
    nvcc="$(command -v nvcc)"
  elif [ -x "${cuda_home}/bin/nvcc" ]; then
    nvcc="${cuda_home}/bin/nvcc"
  else
    echo "nvcc not found. Set NVCC or pass --nvcc." >&2
    exit 1
  fi
fi

if [ -z "${arch}" ]; then
  if command -v nvidia-smi >/dev/null 2>&1; then
    compute_cap="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '[:space:].' || true)"
    if [ -n "${compute_cap}" ]; then
      arch="sm_${compute_cap}"
    fi
  fi
fi
arch="${arch:-sm_121}"

mkdir -p "$(dirname "${out_bin}")" "$(dirname "${manifest}")"

"${nvcc}" -std=c++14 -O2 -arch="${arch}" \
  "${repo_root}/cuda/cuflye_cuda_read_window_smoke.cu" \
  -o "${out_bin}"

python3 - "$manifest" "$repo_root" "$out_bin" "$cuda_home" "$nvcc" "$arch" <<'PY'
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone

manifest, repo_root, out_bin, cuda_home, nvcc, arch = sys.argv[1:]


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
    "nvcc": nvcc,
    "nvcc_version": run([nvcc, "--version"]),
    "cuda_arch": arch,
    "host": platform.node(),
    "platform": platform.platform(),
    "machine": platform.machine(),
    "python": sys.version.split()[0],
}

with open(manifest, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

echo "Built cuFlye CUDA read-window smoke prototype: ${out_bin}"
echo "Build manifest: ${manifest}"
