#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run_m6o_session_scale_proof.sh [options]

Run the M6o file-backed full-query-hit worker session scale proof.

Options:
  --proof-root PATH       Proof output root. Default: /tmp/cuflye-m6o-proof-<utc>
  --worker-bin PATH       CUDA full-query-hit worker binary. Required.
  --requests N            Compatible positive requests. Default: 4, minimum: 4
  --fixture NAME          Flye fixture name. Default: toy-hifi
  --query-ids IDS         Source-pack query ids. Default: 5,6,7,8,9,10,11,12
  --threads N             Flye threads. Default: 1
  --device ID             CUDA device id. Default: 0
  --session-poll-ms N     Worker session poll interval. Default: 2
  --session-timeout-ms N  Worker session timeout. Default: 600000
  --negative-memory-budget-bytes N
                          Negative proof memory budget. Default: 1
  -h, --help              Show this help.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

proof_root=""
worker_bin=""
request_count=4
fixture="toy-hifi"
query_ids="5,6,7,8,9,10,11,12"
threads=1
device=0
session_poll_ms=2
session_timeout_ms=600000
negative_memory_budget_bytes=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --proof-root)
      proof_root="$2"
      shift 2
      ;;
    --worker-bin)
      worker_bin="$2"
      shift 2
      ;;
    --requests)
      request_count="$2"
      shift 2
      ;;
    --fixture)
      fixture="$2"
      shift 2
      ;;
    --query-ids)
      query_ids="$2"
      shift 2
      ;;
    --threads)
      threads="$2"
      shift 2
      ;;
    --device)
      device="$2"
      shift 2
      ;;
    --session-poll-ms)
      session_poll_ms="$2"
      shift 2
      ;;
    --session-timeout-ms)
      session_timeout_ms="$2"
      shift 2
      ;;
    --negative-memory-budget-bytes)
      negative_memory_budget_bytes="$2"
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

if [ -z "${worker_bin}" ]; then
  echo "--worker-bin is required" >&2
  exit 2
fi
if [ ! -x "${worker_bin}" ]; then
  echo "worker binary is not executable: ${worker_bin}" >&2
  exit 1
fi
case "${request_count}" in
  ''|*[!0-9]*)
    echo "--requests must be a positive integer" >&2
    exit 2
    ;;
esac
if [ "${request_count}" -lt 4 ]; then
  echo "--requests must be at least 4 for M6o" >&2
  exit 2
fi

if [ -z "${proof_root}" ]; then
  proof_root="/tmp/cuflye-m6o-proof-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "${proof_root}/logs"

positive_pid=""
negative_pid=""
cleanup() {
  for pid in "${positive_pid:-}" "${negative_pid:-}"; do
    if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

wait_for_session_ready() {
  local session_dir="$1"
  local pid="$2"
  local label="$3"
  local attempts=$((session_timeout_ms / session_poll_ms))
  if [ "${attempts}" -lt 1 ]; then
    attempts=1
  fi
  for _ in $(seq 1 "${attempts}"); do
    if [ -f "${session_dir}/session-ready.json" ]; then
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      wait "${pid}" || true
      echo "${label} worker exited before session-ready.json" >&2
      return 1
    fi
    sleep "$(python3 - "${session_poll_ms}" <<'PY'
import sys
print(int(sys.argv[1]) / 1000.0)
PY
)"
  done
  echo "${label} worker did not become ready" >&2
  return 1
}

echo "proof_root=${proof_root}"

"${repo_root}/scripts/run_flye_fixture.sh" \
  --fixture "${fixture}" \
  --out-dir "${proof_root}/baseline/flye" \
  --threads "${threads}" \
  --force \
  > "${proof_root}/logs/baseline.stdout.log" \
  2> "${proof_root}/logs/baseline.stderr.log"
echo "baseline_done"

positive_session="${proof_root}/session"
mkdir -p "${positive_session}"
"${worker_bin}" \
  --worker-session-dir "${positive_session}" \
  --worker-session-max-requests "${request_count}" \
  --worker-session-poll-ms "${session_poll_ms}" \
  --worker-session-timeout-ms "${session_timeout_ms}" \
  --device "${device}" \
  > "${proof_root}/logs/session-worker.stdout.log" \
  2> "${proof_root}/logs/session-worker.stderr.log" &
positive_pid=$!
printf '%s\n' "${positive_pid}" > "${proof_root}/session-worker.pid"
wait_for_session_ready "${positive_session}" "${positive_pid}" "positive"
echo "positive_session_ready"

source_pack_dir="${proof_root}/positive/source-pack"
for request_index in $(seq 1 "${request_count}"); do
  request_name="$(printf 'request-%02d' "${request_index}")"
  "${repo_root}/scripts/run_flye_fixture.sh" \
    --fixture "${fixture}" \
    --out-dir "${proof_root}/positive/${request_name}/flye" \
    --threads "${threads}" \
    --read-to-graph-source-pack-dir "${source_pack_dir}" \
    --read-to-graph-source-pack-query-ids "${query_ids}" \
    --read-to-graph-full-query-hit-worker-mode full-query-hit-dry-run-v0 \
    --read-to-graph-full-query-hit-worker-lifecycle-mode session-file-v0 \
    --read-to-graph-full-query-hit-worker-session-dir "${positive_session}" \
    --read-to-graph-full-query-hit-worker-output-dir "${proof_root}/positive/${request_name}/worker" \
    --read-to-graph-full-query-hit-worker-device "${device}" \
    --expect-failure \
    --force \
    > "${proof_root}/logs/${request_name}.stdout.log" \
    2> "${proof_root}/logs/${request_name}.stderr.log"
  echo "positive_${request_name}_done"
done

wait "${positive_pid}"
positive_pid=""
echo "positive_session_worker_done"

oracle_tsv="${proof_root}/positive/oracle.raw-overlaps.tsv"
first_oracle=1
rm -f "${oracle_tsv}"
while IFS= read -r raw_overlap_tsv; do
  if [ "${first_oracle}" = 1 ]; then
    cat "${raw_overlap_tsv}" > "${oracle_tsv}"
    first_oracle=0
  else
    tail -n +3 "${raw_overlap_tsv}" >> "${oracle_tsv}"
  fi
done < <(find "${source_pack_dir}" -path '*/raw-overlaps.tsv' | sort -V)

for request_index in $(seq 1 "${request_count}"); do
  request_name="$(printf 'request-%02d' "${request_index}")"
  python3 "${repo_root}/tools/diff_read_to_graph_raw_overlap_row_keys.py" \
    "${oracle_tsv}" \
    "${proof_root}/positive/${request_name}/worker/full-query-hit-worker.raw-overlaps.tsv" \
    --json \
    --json-output "${proof_root}/positive/${request_name}/oracle-vs-worker-row-key-diff.json" \
    > "${proof_root}/logs/${request_name}-row-key-diff.stdout.log"
done
echo "positive_row_key_diffs_done"

negative_session="${proof_root}/negative-session"
mkdir -p "${negative_session}"
"${worker_bin}" \
  --worker-session-dir "${negative_session}" \
  --worker-session-max-requests 1 \
  --worker-session-poll-ms "${session_poll_ms}" \
  --worker-session-timeout-ms "${session_timeout_ms}" \
  --device "${device}" \
  > "${proof_root}/logs/negative-session-worker.stdout.log" \
  2> "${proof_root}/logs/negative-session-worker.stderr.log" &
negative_pid=$!
printf '%s\n' "${negative_pid}" > "${proof_root}/negative-session-worker.pid"
wait_for_session_ready "${negative_session}" "${negative_pid}" "negative"
echo "negative_session_ready"

"${repo_root}/scripts/run_flye_fixture.sh" \
  --fixture "${fixture}" \
  --out-dir "${proof_root}/negative/flye" \
  --threads "${threads}" \
  --read-to-graph-source-pack-dir "${proof_root}/negative/source-pack" \
  --read-to-graph-source-pack-query-ids "${query_ids}" \
  --read-to-graph-full-query-hit-worker-mode full-query-hit-dry-run-v0 \
  --read-to-graph-full-query-hit-worker-lifecycle-mode session-file-v0 \
  --read-to-graph-full-query-hit-worker-session-dir "${negative_session}" \
  --read-to-graph-full-query-hit-worker-output-dir "${proof_root}/negative/worker" \
  --read-to-graph-full-query-hit-worker-device "${device}" \
  --read-to-graph-full-query-hit-worker-memory-budget-bytes "${negative_memory_budget_bytes}" \
  --expect-failure \
  --force \
  > "${proof_root}/logs/negative.stdout.log" \
  2> "${proof_root}/logs/negative.stderr.log"
echo "negative_flye_done"

if wait "${negative_pid}"; then
  negative_pid=""
  echo "negative worker unexpectedly exited zero" >&2
  exit 1
else
  negative_pid=""
  echo "negative_session_worker_failed_closed"
fi

python3 - "${repo_root}" "${proof_root}" "${request_count}" "${fixture}" "${query_ids}" <<'PY'
import json
import pathlib
import statistics
import sys

repo_root = pathlib.Path(sys.argv[1])
proof_root = pathlib.Path(sys.argv[2])
request_count = int(sys.argv[3])
fixture = sys.argv[4]
query_ids = [int(value) for value in sys.argv[5].split(",") if value]


def load(path):
    return json.loads(path.read_text())


requests = []
for index in range(1, request_count + 1):
    request_name = f"request-{index:02d}"
    base = proof_root / "positive" / request_name
    audit = load(base / "worker/full-query-hit-worker-dry-run.json")
    response = load(base / "worker/full-query-hit-worker-response.json")
    diff = load(base / "oracle-vs-worker-row-key-diff.json")
    requests.append({
        "index": index,
        "name": request_name,
        "audit": {
            "status": audit.get("status"),
            "decision": audit.get("decision"),
            "worker_session_submit_ms": audit.get("worker_session_submit_ms"),
            "worker_wall_ms": audit.get("worker_wall_ms"),
            "actual_worker_cuda_context_warm": audit.get(
                "actual_worker_cuda_context_warm"),
            "actual_request_timing_ms": audit.get("actual_request_timing_ms"),
            "row_key_diff": audit.get("row_key_diff"),
            "graph_mutation_consumed_worker_output": audit.get(
                "graph_mutation_consumed_worker_output"),
        },
        "response": response,
        "external_row_key_diff": diff,
    })

session_complete = load(proof_root / "session/session-complete.json")
negative_audit = load(proof_root / "negative/worker/full-query-hit-worker-dry-run.json")
negative_response = load(proof_root / "negative/worker/full-query-hit-worker-response.json")
negative_session_error = load(proof_root / "negative-session/session-error.json")

current_hashes = load(proof_root / "baseline/flye/artifact_hashes.json")["artifacts"]
golden_hashes = load(repo_root / "tests/golden/toy-hifi-dgx-aarch64.json")["artifact_hashes"]
current = {item["path"]: item for item in current_hashes}
golden = {item["path"]: item for item in golden_hashes}
missing = sorted(set(golden) - set(current))
extra = sorted(set(current) - set(golden))
mismatch = {}
for path in sorted(set(current) & set(golden)):
    if current[path].get("canonical_sha256") != golden[path].get("canonical_sha256"):
        mismatch[path] = {
            "current": current[path].get("canonical_sha256"),
            "golden": golden[path].get("canonical_sha256"),
        }
artifact_comparison = {
    "status": "match" if not missing and not extra and not mismatch else "mismatch",
    "current_records": len(current),
    "golden_records": len(golden),
    "missing": missing,
    "extra": extra,
    "mismatch": mismatch,
}

def timing_value(request, field):
    return request["response"]["timing_ms"].get(field)

all_wall = [request["audit"]["worker_wall_ms"] for request in requests]
all_request_total = [timing_value(request, "request_total") for request in requests]
warm_requests = requests[1:]
warm_wall = [request["audit"]["worker_wall_ms"] for request in warm_requests]
warm_request_total = [timing_value(request, "request_total") for request in warm_requests]
warm_kernel = [timing_value(request, "kernel") for request in warm_requests]

manifest = {
    "schema": "cuflye-m6o-session-scale-performance-gate-proof-v0",
    "milestone": "M6o-session-scale-performance-gate",
    "fixture": fixture,
    "proof_root": str(proof_root),
    "source_pack_query_ids": query_ids,
    "request_count": request_count,
    "positive_file_session": {
        "worker_lifecycle_mode": "session-file-v0",
        "session_dir": str(proof_root / "session"),
        "session_complete": session_complete,
        "requests": requests,
        "timing_summary_ms": {
            "cold_worker_wall": all_wall[0],
            "cold_request_total": all_request_total[0],
            "warm_worker_wall_min": min(warm_wall),
            "warm_worker_wall_max": max(warm_wall),
            "warm_worker_wall_avg": statistics.fmean(warm_wall),
            "warm_request_total_min": min(warm_request_total),
            "warm_request_total_max": max(warm_request_total),
            "warm_request_total_avg": statistics.fmean(warm_request_total),
            "warm_kernel_avg": statistics.fmean(warm_kernel),
            "all_worker_wall_avg": statistics.fmean(all_wall),
            "all_request_total_avg": statistics.fmean(all_request_total),
            "amortized_worker_wall_including_cold": sum(all_wall) / len(all_wall),
            "amortized_request_total_including_cold": (
                sum(all_request_total) / len(all_request_total)),
            "cold_to_warm_wall_improvement": (
                all_wall[0] / statistics.fmean(warm_wall)),
            "cold_to_warm_request_total_improvement": (
                all_request_total[0] / statistics.fmean(warm_request_total)),
        },
    },
    "negative_fail_closed": {
        "session_dir": str(proof_root / "negative-session"),
        "session_error": negative_session_error,
        "audit": {
            "status": negative_audit.get("status"),
            "decision": negative_audit.get("decision"),
            "worker_exit_status": negative_audit.get("worker_exit_status"),
            "worker_session_submit_ms": negative_audit.get("worker_session_submit_ms"),
            "failed_closed": negative_audit.get("failed_closed"),
            "worker_output_consumption_eligible": negative_audit.get(
                "worker_output_consumption_eligible"),
            "graph_mutation_consumed_worker_output": negative_audit.get(
                "graph_mutation_consumed_worker_output"),
            "row_key_diff": negative_audit.get("row_key_diff"),
            "error": negative_audit.get("error"),
        },
        "response": negative_response,
    },
    "default_cpu_artifacts": {
        "artifact_hashes_match_m0_golden": artifact_comparison["status"] == "match",
        "comparison": artifact_comparison,
    },
}

warm_timings_zero = all(
    timing_value(request, "parse") == 0.0 and
    timing_value(request, "device_allocation") == 0.0 and
    timing_value(request, "host_to_device") == 0.0
    for request in warm_requests
)
manifest["acceptance"] = {
    "one_file_backed_session_processes_at_least_four_compatible_requests": (
        session_complete.get("worker_session_processed_requests", 0) >= 4),
    "every_warm_request_reports_worker_cuda_context_warm": all(
        request["response"].get("worker_cuda_context_warm") is True
        for request in warm_requests),
    "warm_requests_report_zero_parse_device_allocation_and_host_to_device": (
        warm_timings_zero),
    "row_key_diff_matches_cpu_oracle_for_every_validated_actual_request": all(
        request["external_row_key_diff"].get("status") == "match"
        for request in requests),
    "negative_proof_fails_closed_before_graph_mutation": (
        negative_audit.get("status") == "failed-before-graph-mutation" and
        negative_audit.get("graph_mutation_consumed_worker_output") is False and
        negative_response.get("status") == "error"),
    "default_cpu_flye_artifacts_unchanged": artifact_comparison["status"] == "match",
}

(proof_root / "m6o-proof-summary.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n")
print(json.dumps(manifest["positive_file_session"]["timing_summary_ms"],
                 indent=2, sort_keys=True))
PY

echo "summary=${proof_root}/m6o-proof-summary.json"
