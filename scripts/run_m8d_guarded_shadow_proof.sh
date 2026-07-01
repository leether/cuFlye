#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run_m8d_guarded_shadow_proof.sh [options]

Run the M8d Flye-side full-query-hit guarded rehydration/shadow proof.

Options:
  --proof-root PATH       Proof output root. Default: /tmp/cuflye-m8d-proof-<utc>
  --worker-bin PATH       CUDA full-query-hit worker binary. Required.
  --requests N            Compatible positive requests. Default: 4, minimum: 4
  --fixture NAME          Flye fixture name. Default: toy-hifi
  --query-ids IDS         Source-pack query ids. Default: M8a selected ids
  --threads N             Flye threads. Default: 1
  --device ID             CUDA device id. Default: 0
  --session-poll-ms N     Worker session poll interval. Default: 2
  --session-timeout-ms N  Worker session timeout. Default: 600000
  --negative-memory-budget-bytes N
                          Negative proof memory budget. Default: 1
  --m8a-baseline-ms N     Matched M8a quick-overlap CPU baseline. Default: 79.294112
  --m8b-source-pack-sha SHA
                          Expected M8b/M8c source-pack canonical SHA.
  --m8a-oracle-pack PATH  M8a input-boundary oracle pack. Required to exist.
  -h, --help              Show this help.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

proof_root=""
worker_bin=""
request_count=4
fixture="toy-hifi"
query_ids="2145,2160,2146,2152,2161,2167,2148,2154,2157,2163,2165,2149,84,2150,5,361"
threads=1
device=0
session_poll_ms=2
session_timeout_ms=600000
negative_memory_budget_bytes=1
m8a_baseline_ms=79.294112
m8b_source_pack_sha="5fb1df86185f3cdce0bc0c15087b7bead53db6d46b523740650d4092a89c25aa"
m8a_oracle_pack="/tmp/cuflye-m8a-proof-20260701T203000Z/oracle-pack"

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
    --m8a-baseline-ms)
      m8a_baseline_ms="$2"
      shift 2
      ;;
    --m8b-source-pack-sha)
      m8b_source_pack_sha="$2"
      shift 2
      ;;
    --m8a-oracle-pack)
      m8a_oracle_pack="$2"
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
  echo "--requests must be at least 4 for M8d" >&2
  exit 2
fi
if [ ! -d "${m8a_oracle_pack}" ]; then
  echo "M8a oracle pack not found: ${m8a_oracle_pack}" >&2
  exit 1
fi

if [ -z "${proof_root}" ]; then
  proof_root="/tmp/cuflye-m8d-proof-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "${proof_root}/logs"

positive_pid=""
negative_memory_pid=""
negative_ledger_pid=""
cleanup() {
  for pid in "${positive_pid:-}" "${negative_memory_pid:-}" "${negative_ledger_pid:-}"; do
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

run_flye_with_guarded_shadow() {
  local out_dir="$1"
  local source_pack_dir="$2"
  local worker_output_dir="$3"
  local session_dir="$4"
  shift 4
  "${repo_root}/scripts/run_flye_fixture.sh" \
    --fixture "${fixture}" \
    --out-dir "${out_dir}" \
    --threads "${threads}" \
    --read-to-graph-source-pack-dir "${source_pack_dir}" \
    --read-to-graph-source-pack-query-ids "${query_ids}" \
    --read-to-graph-full-query-hit-worker-mode full-query-hit-dry-run-v0 \
    --read-to-graph-full-query-hit-worker-lifecycle-mode session-file-v0 \
    --read-to-graph-full-query-hit-worker-session-dir "${session_dir}" \
    --read-to-graph-full-query-hit-worker-output-dir "${worker_output_dir}" \
    --read-to-graph-full-query-hit-worker-device "${device}" \
    --read-to-graph-full-query-hit-rehydration-mode raw-overlap-vector-dry-run-v0 \
    --read-to-graph-full-query-hit-shadow-ledger-mode raw-overlap-chain-input-shadow-v0 \
    "$@" \
    --expect-failure \
    --force
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
  run_flye_with_guarded_shadow \
    "${proof_root}/positive/${request_name}/flye" \
    "${source_pack_dir}" \
    "${proof_root}/positive/${request_name}/worker" \
    "${positive_session}" \
    > "${proof_root}/logs/${request_name}.stdout.log" \
    2> "${proof_root}/logs/${request_name}.stderr.log"
  echo "positive_${request_name}_done"
done

wait "${positive_pid}"
positive_pid=""
echo "positive_session_worker_done"

python3 "${repo_root}/tools/validate_read_to_graph_source_pack.py" \
  "${source_pack_dir}" \
  --json-output "${proof_root}/source-pack-validation.json" \
  > "${proof_root}/logs/source-pack-validation.stdout.log"
echo "source_pack_validation_done"

python3 "${repo_root}/tools/replay_read_to_graph_input_boundary_pack.py" \
  "${m8a_oracle_pack}" \
  --json-output "${proof_root}/m8a-oracle-pack-replay.json" \
  > "${proof_root}/logs/m8a-oracle-pack-replay.stdout.log"
echo "m8a_oracle_replay_done"

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

negative_memory_session="${proof_root}/negative-memory-session"
mkdir -p "${negative_memory_session}"
"${worker_bin}" \
  --worker-session-dir "${negative_memory_session}" \
  --worker-session-max-requests 1 \
  --worker-session-poll-ms "${session_poll_ms}" \
  --worker-session-timeout-ms "${session_timeout_ms}" \
  --device "${device}" \
  > "${proof_root}/logs/negative-memory-session-worker.stdout.log" \
  2> "${proof_root}/logs/negative-memory-session-worker.stderr.log" &
negative_memory_pid=$!
printf '%s\n' "${negative_memory_pid}" > "${proof_root}/negative-memory-session-worker.pid"
wait_for_session_ready "${negative_memory_session}" "${negative_memory_pid}" "negative-memory"
echo "negative_memory_session_ready"

run_flye_with_guarded_shadow \
  "${proof_root}/negative-memory/flye" \
  "${proof_root}/negative-memory/source-pack" \
  "${proof_root}/negative-memory/worker" \
  "${negative_memory_session}" \
  --read-to-graph-full-query-hit-worker-memory-budget-bytes "${negative_memory_budget_bytes}" \
  > "${proof_root}/logs/negative-memory.stdout.log" \
  2> "${proof_root}/logs/negative-memory.stderr.log"
echo "negative_memory_flye_done"

if wait "${negative_memory_pid}"; then
  negative_memory_pid=""
  echo "negative memory worker unexpectedly exited zero" >&2
  exit 1
else
  negative_memory_pid=""
  echo "negative_memory_worker_failed_closed"
fi

negative_ledger_session="${proof_root}/negative-ledger-session"
mkdir -p "${negative_ledger_session}"
"${worker_bin}" \
  --worker-session-dir "${negative_ledger_session}" \
  --worker-session-max-requests 1 \
  --worker-session-poll-ms "${session_poll_ms}" \
  --worker-session-timeout-ms "${session_timeout_ms}" \
  --device "${device}" \
  > "${proof_root}/logs/negative-ledger-session-worker.stdout.log" \
  2> "${proof_root}/logs/negative-ledger-session-worker.stderr.log" &
negative_ledger_pid=$!
printf '%s\n' "${negative_ledger_pid}" > "${proof_root}/negative-ledger-session-worker.pid"
wait_for_session_ready "${negative_ledger_session}" "${negative_ledger_pid}" "negative-ledger"
echo "negative_ledger_session_ready"

run_flye_with_guarded_shadow \
  "${proof_root}/negative-ledger/flye" \
  "${proof_root}/negative-ledger/source-pack" \
  "${proof_root}/negative-ledger/worker" \
  "${negative_ledger_session}" \
  --read-to-graph-full-query-hit-shadow-ledger-proof-fault drop-first-ledger-row \
  > "${proof_root}/logs/negative-ledger.stdout.log" \
  2> "${proof_root}/logs/negative-ledger.stderr.log"
echo "negative_ledger_flye_done"

wait "${negative_ledger_pid}"
negative_ledger_pid=""
echo "negative_ledger_worker_done"

python3 "${repo_root}/tools/validate_read_to_graph_source_pack.py" \
  "${proof_root}/negative-ledger/source-pack" \
  --json-output "${proof_root}/negative-ledger-source-pack-validation.json" \
  > "${proof_root}/logs/negative-ledger-source-pack-validation.stdout.log"
echo "negative_ledger_source_pack_validation_done"

python3 - "${repo_root}" "${proof_root}" "${request_count}" "${fixture}" \
  "${query_ids}" "${m8a_baseline_ms}" "${m8b_source_pack_sha}" \
  "${m8a_oracle_pack}" <<'PY'
import json
import pathlib
import statistics
import sys

repo_root = pathlib.Path(sys.argv[1])
proof_root = pathlib.Path(sys.argv[2])
request_count = int(sys.argv[3])
fixture = sys.argv[4]
query_ids = [int(value) for value in sys.argv[5].split(",") if value]
m8a_baseline_ms = float(sys.argv[6])
m8b_source_pack_sha = sys.argv[7]
m8a_oracle_pack = pathlib.Path(sys.argv[8])


def load(path):
    return json.loads(path.read_text())


def timing_value(request, field):
    return request["response"]["timing_ms"].get(field)


def audit_timing(audit, field):
    timing = audit.get("graph_facing_validation_timing_ms", {})
    return float(timing.get(field, 0.0))


requests = []
for index in range(1, request_count + 1):
    request_name = f"request-{index:02d}"
    base = proof_root / "positive" / request_name
    audit = load(base / "worker/full-query-hit-worker-dry-run.json")
    response = load(base / "worker/full-query-hit-worker-response.json")
    diff = load(base / "oracle-vs-worker-row-key-diff.json")
    rehydration = load(
        base / "worker/full-query-hit-worker-raw-overlap-rehydration.json"
    )
    ledger = load(
        base / "worker/full-query-hit-worker-shadow-consumption-ledger.json"
    )
    requests.append({
        "index": index,
        "name": request_name,
        "audit": {
            "status": audit.get("status"),
            "decision": audit.get("decision"),
            "worker_wall_ms": audit.get("worker_wall_ms"),
            "worker_session_submit_ms": audit.get("worker_session_submit_ms"),
            "actual_worker_cuda_context_warm": audit.get(
                "actual_worker_cuda_context_warm"),
            "actual_request_timing_ms": audit.get("actual_request_timing_ms"),
            "graph_facing_validation_timing_ms": audit.get(
                "graph_facing_validation_timing_ms"),
            "row_key_diff": audit.get("row_key_diff"),
            "row_key_matched": audit.get("row_key_matched"),
            "raw_overlap_rehydration_status": audit.get(
                "raw_overlap_rehydration_status"),
            "raw_overlap_rehydrated_records": audit.get(
                "raw_overlap_rehydrated_records"),
            "raw_overlap_shadow_ledger_status": audit.get(
                "raw_overlap_shadow_ledger_status"),
            "raw_overlap_shadow_ledger_rows": audit.get(
                "raw_overlap_shadow_ledger_rows"),
            "raw_overlap_shadow_chain_input_filter_rows": audit.get(
                "raw_overlap_shadow_chain_input_filter_rows"),
            "raw_overlap_shadow_unresolved_edge_id_zero_rows": audit.get(
                "raw_overlap_shadow_unresolved_edge_id_zero_rows"),
            "raw_overlap_shadow_resolved_edge_id_rows": audit.get(
                "raw_overlap_shadow_resolved_edge_id_rows"),
            "raw_overlap_shadow_graph_edge_consumption_candidate_rows": audit.get(
                "raw_overlap_shadow_graph_edge_consumption_candidate_rows"),
            "graph_mutation_consumed_worker_output": audit.get(
                "graph_mutation_consumed_worker_output"),
        },
        "response": response,
        "external_row_key_diff": diff,
        "rehydration": rehydration,
        "shadow_ledger": ledger,
    })

session_complete = load(proof_root / "session/session-complete.json")
source_pack = load(proof_root / "source-pack-validation.json")
m8a_replay = load(proof_root / "m8a-oracle-pack-replay.json")
negative_memory_audit = load(
    proof_root / "negative-memory/worker/full-query-hit-worker-dry-run.json"
)
negative_memory_response = load(
    proof_root / "negative-memory/worker/full-query-hit-worker-response.json"
)
negative_memory_session_error = load(
    proof_root / "negative-memory-session/session-error.json"
)
negative_ledger_audit = load(
    proof_root / "negative-ledger/worker/full-query-hit-worker-dry-run.json"
)
negative_ledger_response = load(
    proof_root / "negative-ledger/worker/full-query-hit-worker-response.json"
)
negative_ledger_rehydration = load(
    proof_root /
    "negative-ledger/worker/full-query-hit-worker-raw-overlap-rehydration.json"
)
negative_ledger = load(
    proof_root /
    "negative-ledger/worker/full-query-hit-worker-shadow-consumption-ledger.json"
)
negative_ledger_source_pack = load(
    proof_root / "negative-ledger-source-pack-validation.json"
)

current_hashes = load(proof_root / "baseline/flye/artifact_hashes.json")["artifacts"]
golden_hashes = load(repo_root / "tests/golden/toy-hifi-dgx-aarch64.json")[
    "artifact_hashes"
]
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

warm_requests = requests[1:]
all_wall = [request["audit"]["worker_wall_ms"] for request in requests]
all_request_total = [timing_value(request, "request_total") for request in requests]
all_no_mutation_total = [
    audit_timing(request["audit"], "no_mutation_seam_total")
    for request in requests
]
warm_wall = [request["audit"]["worker_wall_ms"] for request in warm_requests]
warm_request_total = [timing_value(request, "request_total") for request in warm_requests]
warm_kernel = [timing_value(request, "kernel") for request in warm_requests]
warm_row_key = [
    audit_timing(request["audit"], "row_key_diff") for request in warm_requests
]
warm_rehydration = [
    audit_timing(request["audit"], "raw_overlap_rehydration")
    for request in warm_requests
]
warm_shadow = [
    audit_timing(request["audit"], "raw_overlap_shadow_ledger")
    for request in warm_requests
]
warm_graph_validation = [
    audit_timing(request["audit"], "graph_facing_validation_total")
    for request in warm_requests
]
warm_no_mutation_total = [
    audit_timing(request["audit"], "no_mutation_seam_total")
    for request in warm_requests
]

timing_summary = {
    "cold_worker_wall": all_wall[0],
    "cold_request_total": all_request_total[0],
    "cold_no_mutation_seam_total": all_no_mutation_total[0],
    "warm_worker_wall_avg": statistics.fmean(warm_wall),
    "warm_request_total_avg": statistics.fmean(warm_request_total),
    "warm_kernel_avg": statistics.fmean(warm_kernel),
    "warm_row_key_diff_avg": statistics.fmean(warm_row_key),
    "warm_raw_overlap_rehydration_avg": statistics.fmean(warm_rehydration),
    "warm_raw_overlap_shadow_ledger_avg": statistics.fmean(warm_shadow),
    "warm_graph_facing_validation_total_avg": statistics.fmean(
        warm_graph_validation),
    "warm_no_mutation_seam_total_avg": statistics.fmean(warm_no_mutation_total),
    "all_worker_wall_avg": statistics.fmean(all_wall),
    "all_request_total_avg": statistics.fmean(all_request_total),
    "all_no_mutation_seam_total_avg": statistics.fmean(all_no_mutation_total),
}
speedup = {
    "warm_worker_wall_avg": m8a_baseline_ms / timing_summary[
        "warm_worker_wall_avg"],
    "warm_request_total_avg": m8a_baseline_ms / timing_summary[
        "warm_request_total_avg"],
    "warm_no_mutation_seam_total_avg": m8a_baseline_ms / timing_summary[
        "warm_no_mutation_seam_total_avg"],
    "all_no_mutation_seam_total_avg": m8a_baseline_ms / timing_summary[
        "all_no_mutation_seam_total_avg"],
}

positive_rows = requests[-1]["audit"]
checks = {
    "source_pack_status_ok": source_pack.get("status") == "ok",
    "source_pack_matches_m8b_sha": source_pack.get("canonical_sha256") ==
        m8b_source_pack_sha,
    "source_pack_query_ids_match_selected": source_pack.get("query_ids") ==
        sorted(query_ids),
    "session_processed_four_requests": session_complete.get(
        "worker_session_processed_requests", 0) >= 4,
    "warm_requests_report_cuda_context_warm": all(
        request["response"].get("worker_cuda_context_warm") is True
        for request in warm_requests),
    "all_worker_row_key_diffs_match": all(
        request["external_row_key_diff"].get("status") == "match"
        for request in requests),
    "all_rehydration_passed": all(
        request["audit"].get("raw_overlap_rehydration_status") == "passed"
        for request in requests),
    "all_shadow_ledgers_passed": all(
        request["audit"].get("raw_overlap_shadow_ledger_status") == "passed"
        for request in requests),
    "rehydrated_rows_match_worker_rows": all(
        request["audit"].get("raw_overlap_rehydrated_records") ==
        request["response"].get("output_records")
        for request in requests),
    "shadow_rows_match_rehydrated_rows": all(
        request["audit"].get("raw_overlap_shadow_ledger_rows") ==
        request["audit"].get("raw_overlap_rehydrated_records")
        for request in requests),
    "selected_cpu_oracle_shape_matches": (
        positive_rows.get("raw_overlap_rehydrated_records") ==
        source_pack.get("total_counts", {}).get("raw_overlap_records") and
        positive_rows.get("raw_overlap_shadow_chain_input_filter_rows") ==
        source_pack.get("total_counts", {}).get("chain_input_records")),
    "m8a_chain_input_oracle_replay_match": m8a_replay.get("status") == "match",
    "default_cpu_artifacts_unchanged": artifact_comparison["status"] == "match",
    "negative_memory_fails_closed_before_graph_mutation": (
        negative_memory_audit.get("status") == "failed-before-graph-mutation" and
        negative_memory_audit.get("graph_mutation_consumed_worker_output") is False and
        negative_memory_response.get("status") == "error"),
    "negative_ledger_fails_closed_before_graph_mutation": (
        negative_ledger_audit.get("status") ==
        "shadow-ledger-failed-before-graph-mutation" and
        negative_ledger_audit.get("raw_overlap_rehydration_status") == "passed" and
        negative_ledger_audit.get("raw_overlap_shadow_ledger_status") == "failed" and
        negative_ledger_audit.get("graph_mutation_consumed_worker_output") is False),
    "negative_ledger_source_pack_matches_m8b_sha": (
        negative_ledger_source_pack.get("canonical_sha256") ==
        m8b_source_pack_sha),
    "warm_no_mutation_seam_below_m8a_quick_overlap": (
        timing_summary["warm_no_mutation_seam_total_avg"] < m8a_baseline_ms),
}

manifest = {
    "schema": "cuflye-m8d-m8c-guarded-rehydration-shadow-consumption-proof-v0",
    "fixture": fixture,
    "proof_root": str(proof_root),
    "work_root": str(repo_root),
    "m8a_baseline": {
        "selected_quick_overlap_ms": m8a_baseline_ms,
        "selected_query_ids": query_ids,
    },
    "m8b_reference": {
        "source_pack_canonical_sha256": m8b_source_pack_sha,
    },
    "source_pack": {
        "validation_status": source_pack.get("status"),
        "canonical_sha256": source_pack.get("canonical_sha256"),
        "query_count": source_pack.get("query_count"),
        "query_ids": source_pack.get("query_ids"),
        "total_counts": source_pack.get("total_counts"),
    },
    "m8a_chain_input_oracle_replay": {
        **m8a_replay,
        "pack_dir": str(m8a_oracle_pack),
    },
    "positive_file_session": {
        "worker_lifecycle_mode": "session-file-v0",
        "request_count": request_count,
        "session_complete": session_complete,
        "requests": requests,
        "timing_summary_ms": timing_summary,
        "speedup_vs_m8a_quick_overlap": speedup,
    },
    "negative_memory_fail_closed": {
        "audit": {
            "status": negative_memory_audit.get("status"),
            "decision": negative_memory_audit.get("decision"),
            "failed_closed": negative_memory_audit.get("failed_closed"),
            "worker_output_consumption_eligible": negative_memory_audit.get(
                "worker_output_consumption_eligible"),
            "graph_mutation_consumed_worker_output": negative_memory_audit.get(
                "graph_mutation_consumed_worker_output"),
            "error": negative_memory_audit.get("error"),
        },
        "response": negative_memory_response,
        "session_error": negative_memory_session_error,
    },
    "negative_shadow_ledger_fail_closed": {
        "audit": {
            "status": negative_ledger_audit.get("status"),
            "decision": negative_ledger_audit.get("decision"),
            "row_key_matched": negative_ledger_audit.get("row_key_matched"),
            "raw_overlap_rehydration_status": negative_ledger_audit.get(
                "raw_overlap_rehydration_status"),
            "raw_overlap_shadow_ledger_status": negative_ledger_audit.get(
                "raw_overlap_shadow_ledger_status"),
            "raw_overlap_shadow_ledger_rows": negative_ledger_audit.get(
                "raw_overlap_shadow_ledger_rows"),
            "raw_overlap_rehydrated_records": negative_ledger_audit.get(
                "raw_overlap_rehydrated_records"),
            "graph_facing_validation_timing_ms": negative_ledger_audit.get(
                "graph_facing_validation_timing_ms"),
            "graph_mutation_consumed_worker_output": negative_ledger_audit.get(
                "graph_mutation_consumed_worker_output"),
            "error": negative_ledger_audit.get("error"),
        },
        "response": negative_ledger_response,
        "rehydration": negative_ledger_rehydration,
        "shadow_ledger": negative_ledger,
        "source_pack": {
            "validation_status": negative_ledger_source_pack.get("status"),
            "canonical_sha256": negative_ledger_source_pack.get(
                "canonical_sha256"),
        },
    },
    "default_cpu_artifacts": {
        "artifact_hashes_match_m0_golden": artifact_comparison["status"] ==
        "match",
        "comparison": artifact_comparison,
    },
    "checks": checks,
    "summary_checks_passed": sum(1 for passed in checks.values() if passed),
    "summary_checks_required": len(checks),
    "allowed_claim": (
        "M8d proves the M8c worker/session seam can also pass guarded "
        "raw-overlap rehydration and shadow-ledger accounting while preserving "
        "the bounded selected hot-path advantage in no-mutation mode."
    ),
    "forbidden_claim": (
        "M8d does not prove default GPU mode, unguarded graph mutation, "
        "GraphEdge object-vector consumption, full non-key raw-overlap field "
        "parity, or whole-Flye speedup."
    ),
    "plain_language_benefit": (
        "M8d shows the graph-facing validation layer does not erase the M8c "
        f"CUDA advantage on the selected pack: warm no-mutation seam total "
        f"averages {timing_summary['warm_no_mutation_seam_total_avg']:.6f} ms "
        f"versus the matched CPU quick-overlap baseline {m8a_baseline_ms:.6f} "
        f"ms, or {speedup['warm_no_mutation_seam_total_avg']:.3f}x faster."
    ),
    "next_recommended_step": (
        "M8e: move from shadow ledger to the next guarded selected graph-facing "
        "object/binding proof only if M8d warm no-mutation seam remains below "
        "the matched CPU quick-overlap baseline."
    ),
}

(proof_root / "cuflye-m8d-m8c-guarded-rehydration-shadow-consumption-dgx-aarch64.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n")
print(json.dumps({
    "checks": f"{manifest['summary_checks_passed']} / {manifest['summary_checks_required']}",
    "warm_no_mutation_seam_total_avg_ms": timing_summary[
        "warm_no_mutation_seam_total_avg"],
    "warm_no_mutation_speedup": speedup["warm_no_mutation_seam_total_avg"],
}, indent=2, sort_keys=True))
PY

echo "summary=${proof_root}/cuflye-m8d-m8c-guarded-rehydration-shadow-consumption-dgx-aarch64.json"
