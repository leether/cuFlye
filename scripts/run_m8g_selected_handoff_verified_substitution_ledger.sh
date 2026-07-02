#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run_m8g_selected_handoff_verified_substitution_ledger.sh [options]

Run the M8g Flye-side selected handoff to verified-substitution ledger proof.

Options:
  --proof-root PATH       Proof output root. Default: /tmp/cuflye-m8g-proof-<utc>
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
  echo "--requests must be at least 4 for M8g" >&2
  exit 2
fi
if [ ! -d "${m8a_oracle_pack}" ]; then
  echo "M8a oracle pack not found: ${m8a_oracle_pack}" >&2
  exit 1
fi

if [ -z "${proof_root}" ]; then
  proof_root="/tmp/cuflye-m8g-proof-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "${proof_root}/logs"

positive_pid=""
negative_memory_pid=""
negative_verified_pid=""
cleanup() {
  for pid in "${positive_pid:-}" "${negative_memory_pid:-}" "${negative_verified_pid:-}"; do
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

run_flye_with_verified_substitution_ledger() {
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
    --read-to-graph-full-query-hit-graph-edge-binding-mode graph-edge-binding-dry-run-v0 \
    --read-to-graph-full-query-hit-object-vector-smoke-mode object-vector-smoke-v0 \
    --read-to-graph-full-query-hit-substitution-guard-mode substitution-guard-dry-run-v0 \
    --read-to-graph-full-query-hit-verified-substitution-mode verified-substitution-smoke-v0 \
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
  run_flye_with_verified_substitution_ledger \
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

run_flye_with_verified_substitution_ledger \
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

negative_verified_session="${proof_root}/negative-verified-session"
mkdir -p "${negative_verified_session}"
"${worker_bin}" \
  --worker-session-dir "${negative_verified_session}" \
  --worker-session-max-requests 1 \
  --worker-session-poll-ms "${session_poll_ms}" \
  --worker-session-timeout-ms "${session_timeout_ms}" \
  --device "${device}" \
  > "${proof_root}/logs/negative-verified-session-worker.stdout.log" \
  2> "${proof_root}/logs/negative-verified-session-worker.stderr.log" &
negative_verified_pid=$!
printf '%s\n' "${negative_verified_pid}" > "${proof_root}/negative-verified-session-worker.pid"
wait_for_session_ready "${negative_verified_session}" "${negative_verified_pid}" "negative-verified"
echo "negative_verified_session_ready"

run_flye_with_verified_substitution_ledger \
  "${proof_root}/negative-verified/flye" \
  "${proof_root}/negative-verified/source-pack" \
  "${proof_root}/negative-verified/worker" \
  "${negative_verified_session}" \
  --read-to-graph-full-query-hit-verified-substitution-proof-fault drop-first-substitution-ledger-row \
  > "${proof_root}/logs/negative-verified.stdout.log" \
  2> "${proof_root}/logs/negative-verified.stderr.log"
echo "negative_verified_flye_done"

wait "${negative_verified_pid}"
negative_verified_pid=""
echo "negative_verified_worker_done"

python3 "${repo_root}/tools/validate_read_to_graph_source_pack.py" \
  "${proof_root}/negative-verified/source-pack" \
  --json-output "${proof_root}/negative-verified-source-pack-validation.json" \
  > "${proof_root}/logs/negative-verified-source-pack-validation.stdout.log"
echo "negative_verified_source_pack_validation_done"

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
    binding = load(
        base / "worker/full-query-hit-worker-graph-edge-binding.json"
    )
    smoke = load(
        base / "worker/full-query-hit-worker-object-vector-smoke.json"
    )
    guard = load(
        base / "worker/full-query-hit-worker-substitution-guard.json"
    )
    verified = load(
        base / "worker/full-query-hit-worker-verified-substitution-smoke.json"
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
            "raw_overlap_graph_edge_binding_status": audit.get(
                "raw_overlap_graph_edge_binding_status"),
            "raw_overlap_graph_edge_binding_rows": audit.get(
                "raw_overlap_graph_edge_binding_rows"),
            "raw_overlap_graph_edge_binding_chain_input_rows": audit.get(
                "raw_overlap_graph_edge_binding_chain_input_rows"),
            "raw_overlap_graph_edge_binding_resolved_edge_id_rows": audit.get(
                "raw_overlap_graph_edge_binding_resolved_edge_id_rows"),
            "raw_overlap_graph_edge_binding_live_edge_rows": audit.get(
                "raw_overlap_graph_edge_binding_live_edge_rows"),
            "raw_overlap_graph_edge_binding_missing_edge_rows": audit.get(
                "raw_overlap_graph_edge_binding_missing_edge_rows"),
            "raw_overlap_object_vector_smoke_status": audit.get(
                "raw_overlap_object_vector_smoke_status"),
            "raw_overlap_object_vector_smoke_rows": audit.get(
                "raw_overlap_object_vector_smoke_rows"),
            "raw_overlap_object_vector_smoke_accounting_rows": audit.get(
                "raw_overlap_object_vector_smoke_accounting_rows"),
            "raw_overlap_object_vector_smoke_query_summary_rows": audit.get(
                "raw_overlap_object_vector_smoke_query_summary_rows"),
            "raw_overlap_object_vector_smoke_edge_summary_rows": audit.get(
                "raw_overlap_object_vector_smoke_edge_summary_rows"),
            "raw_overlap_object_vector_smoke_query_edge_summary_rows": audit.get(
                "raw_overlap_object_vector_smoke_query_edge_summary_rows"),
            "raw_overlap_substitution_guard_status": audit.get(
                "raw_overlap_substitution_guard_status"),
            "raw_overlap_substitution_guard_handoff_rows": audit.get(
                "raw_overlap_substitution_guard_handoff_rows"),
            "raw_overlap_substitution_guard_accounting_rows": audit.get(
                "raw_overlap_substitution_guard_accounting_rows"),
            "raw_overlap_substitution_guard_object_summary_rows": audit.get(
                "raw_overlap_substitution_guard_object_summary_rows"),
            "raw_overlap_verified_substitution_status": audit.get(
                "raw_overlap_verified_substitution_status"),
            "raw_overlap_verified_substitution_cpu_handoff_rows": audit.get(
                "raw_overlap_verified_substitution_cpu_handoff_rows"),
            "raw_overlap_verified_substitution_would_substitute_rows": audit.get(
                "raw_overlap_verified_substitution_would_substitute_rows"),
            "raw_overlap_verified_substitution_ledger_rows": audit.get(
                "raw_overlap_verified_substitution_ledger_rows"),
            "graph_mutation_consumed_worker_output": audit.get(
                "graph_mutation_consumed_worker_output"),
        },
        "response": response,
        "external_row_key_diff": diff,
        "rehydration": rehydration,
        "shadow_ledger": ledger,
        "graph_edge_binding": binding,
        "object_vector_smoke": smoke,
        "substitution_guard": guard,
        "verified_substitution": verified,
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
negative_verified_audit = load(
    proof_root / "negative-verified/worker/full-query-hit-worker-dry-run.json"
)
negative_verified_response = load(
    proof_root / "negative-verified/worker/full-query-hit-worker-response.json"
)
negative_verified_rehydration = load(
    proof_root /
    "negative-verified/worker/full-query-hit-worker-raw-overlap-rehydration.json"
)
negative_verified_ledger = load(
    proof_root /
    "negative-verified/worker/full-query-hit-worker-shadow-consumption-ledger.json"
)
negative_verified_binding = load(
    proof_root /
    "negative-verified/worker/full-query-hit-worker-graph-edge-binding.json"
)
negative_verified_smoke = load(
    proof_root /
    "negative-verified/worker/full-query-hit-worker-object-vector-smoke.json"
)
negative_verified_guard = load(
    proof_root /
    "negative-verified/worker/full-query-hit-worker-substitution-guard.json"
)
negative_verified_substitution = load(
    proof_root /
    "negative-verified/worker/full-query-hit-worker-verified-substitution-smoke.json"
)
negative_verified_source_pack = load(
    proof_root / "negative-verified-source-pack-validation.json"
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
warm_binding = [
    audit_timing(request["audit"], "raw_overlap_graph_edge_binding")
    for request in warm_requests
]
warm_object_smoke = [
    audit_timing(request["audit"], "raw_overlap_object_vector_smoke")
    for request in warm_requests
]
warm_handoff = [
    audit_timing(request["audit"], "raw_overlap_substitution_guard")
    for request in warm_requests
]
warm_verified = [
    audit_timing(request["audit"], "raw_overlap_verified_substitution")
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
    "warm_raw_overlap_graph_edge_binding_avg": statistics.fmean(warm_binding),
    "warm_raw_overlap_object_vector_smoke_avg": statistics.fmean(
        warm_object_smoke),
    "warm_raw_overlap_substitution_guard_avg": statistics.fmean(warm_handoff),
    "warm_raw_overlap_verified_substitution_avg": statistics.fmean(warm_verified),
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
    "all_graph_edge_bindings_passed": all(
        request["audit"].get("raw_overlap_graph_edge_binding_status") == "passed"
        and request["graph_edge_binding"].get("status") == "passed"
        for request in requests),
    "all_object_vector_smokes_passed": all(
        request["audit"].get("raw_overlap_object_vector_smoke_status") == "passed"
        and request["object_vector_smoke"].get("status") == "passed"
        for request in requests),
    "all_substitution_guards_passed": all(
        request["audit"].get("raw_overlap_substitution_guard_status") == "passed"
        and request["substitution_guard"].get("status") == "passed"
        for request in requests),
    "all_verified_substitutions_passed": all(
        request["audit"].get("raw_overlap_verified_substitution_status") ==
        "passed" and
        request["verified_substitution"].get("status") == "passed"
        for request in requests),
    "rehydrated_rows_match_worker_rows": all(
        request["audit"].get("raw_overlap_rehydrated_records") ==
        request["response"].get("output_records")
        for request in requests),
    "shadow_rows_match_rehydrated_rows": all(
        request["audit"].get("raw_overlap_shadow_ledger_rows") ==
        request["audit"].get("raw_overlap_rehydrated_records")
        for request in requests),
    "binding_rows_match_chain_input_rows": all(
        request["audit"].get("raw_overlap_graph_edge_binding_rows") ==
        request["audit"].get("raw_overlap_shadow_chain_input_filter_rows")
        for request in requests),
    "binding_rows_are_nonzero": all(
        request["audit"].get("raw_overlap_graph_edge_binding_rows", 0) > 0
        for request in requests),
    "binding_rows_have_live_graph_edges": all(
        request["audit"].get("raw_overlap_graph_edge_binding_rows") ==
        request["audit"].get("raw_overlap_graph_edge_binding_live_edge_rows")
        and request["audit"].get(
            "raw_overlap_graph_edge_binding_missing_edge_rows") == 0
        for request in requests),
    "object_rows_match_binding_rows": all(
        request["audit"].get("raw_overlap_object_vector_smoke_rows") ==
        request["audit"].get("raw_overlap_graph_edge_binding_rows")
        for request in requests),
    "object_accounting_rows_match_object_rows": all(
        request["audit"].get("raw_overlap_object_vector_smoke_accounting_rows") ==
        request["audit"].get("raw_overlap_object_vector_smoke_rows")
        for request in requests),
    "handoff_rows_match_object_rows": all(
        request["audit"].get("raw_overlap_substitution_guard_handoff_rows") ==
        request["audit"].get("raw_overlap_object_vector_smoke_rows")
        for request in requests),
    "handoff_accounting_rows_match_object_accounting_rows": all(
        request["audit"].get("raw_overlap_substitution_guard_accounting_rows") ==
        request["audit"].get("raw_overlap_object_vector_smoke_accounting_rows")
        for request in requests),
    "handoff_summary_rows_match_handoff_rows": all(
        request["audit"].get(
            "raw_overlap_substitution_guard_object_summary_rows") ==
        request["audit"].get("raw_overlap_substitution_guard_handoff_rows")
        for request in requests),
    "verified_would_substitute_rows_match_handoff_rows": all(
        request["audit"].get(
            "raw_overlap_verified_substitution_would_substitute_rows") ==
        request["audit"].get("raw_overlap_substitution_guard_handoff_rows")
        for request in requests),
    "verified_ledger_rows_match_handoff_accounting_rows": all(
        request["audit"].get("raw_overlap_verified_substitution_ledger_rows") ==
        request["audit"].get("raw_overlap_substitution_guard_accounting_rows")
        for request in requests),
    "verified_cpu_handoff_rows_match_ledger_rows": all(
        request["audit"].get(
            "raw_overlap_verified_substitution_cpu_handoff_rows") ==
        request["audit"].get("raw_overlap_verified_substitution_ledger_rows")
        for request in requests),
    "verified_substitution_row_key_and_order_match": all(
        request["verified_substitution"].get("row_key_matched") is True and
        request["verified_substitution"].get("ordered_row_key_matched") is True
        for request in requests),
    "graph_facing_timing_separates_binding_and_object": all(
        "raw_overlap_graph_edge_binding" in
        request["audit"].get("graph_facing_validation_timing_ms", {}) and
        "raw_overlap_object_vector_smoke" in
        request["audit"].get("graph_facing_validation_timing_ms", {})
        for request in requests),
    "graph_facing_timing_separates_handoff": all(
        "raw_overlap_substitution_guard" in
        request["audit"].get("graph_facing_validation_timing_ms", {})
        for request in requests),
    "graph_facing_timing_separates_verified_substitution": all(
        "raw_overlap_verified_substitution" in
        request["audit"].get("graph_facing_validation_timing_ms", {})
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
    "negative_verified_fails_closed_before_graph_mutation": (
        negative_verified_audit.get("status") ==
        "verified-substitution-smoke-failed-before-graph-mutation" and
        negative_verified_audit.get("raw_overlap_rehydration_status") == "passed" and
        negative_verified_audit.get("raw_overlap_shadow_ledger_status") ==
        "passed" and
        negative_verified_audit.get("raw_overlap_graph_edge_binding_status") ==
        "passed" and
        negative_verified_audit.get("raw_overlap_object_vector_smoke_status") ==
        "passed" and
        negative_verified_audit.get("raw_overlap_substitution_guard_status") ==
        "passed" and
        negative_verified_audit.get("raw_overlap_verified_substitution_status") ==
        "failed" and
        negative_verified_substitution.get("status") == "failed" and
        negative_verified_audit.get("graph_mutation_consumed_worker_output") is False),
    "negative_verified_source_pack_matches_m8b_sha": (
        negative_verified_source_pack.get("canonical_sha256") ==
        m8b_source_pack_sha),
    "warm_no_mutation_seam_below_m8a_quick_overlap": (
        timing_summary["warm_no_mutation_seam_total_avg"] < m8a_baseline_ms),
}

manifest = {
    "schema": "cuflye-m8g-selected-handoff-verified-substitution-ledger-proof-v0",
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
    "negative_verified_fail_closed": {
        "audit": {
            "status": negative_verified_audit.get("status"),
            "decision": negative_verified_audit.get("decision"),
            "row_key_matched": negative_verified_audit.get("row_key_matched"),
            "raw_overlap_rehydration_status": negative_verified_audit.get(
                "raw_overlap_rehydration_status"),
            "raw_overlap_shadow_ledger_status": negative_verified_audit.get(
                "raw_overlap_shadow_ledger_status"),
            "raw_overlap_shadow_ledger_rows": negative_verified_audit.get(
                "raw_overlap_shadow_ledger_rows"),
            "raw_overlap_rehydrated_records": negative_verified_audit.get(
                "raw_overlap_rehydrated_records"),
            "raw_overlap_graph_edge_binding_status": negative_verified_audit.get(
                "raw_overlap_graph_edge_binding_status"),
            "raw_overlap_graph_edge_binding_rows": negative_verified_audit.get(
                "raw_overlap_graph_edge_binding_rows"),
            "raw_overlap_object_vector_smoke_status": negative_verified_audit.get(
                "raw_overlap_object_vector_smoke_status"),
            "raw_overlap_object_vector_smoke_rows": negative_verified_audit.get(
                "raw_overlap_object_vector_smoke_rows"),
            "raw_overlap_object_vector_smoke_accounting_rows":
                negative_verified_audit.get(
                    "raw_overlap_object_vector_smoke_accounting_rows"),
            "raw_overlap_substitution_guard_status": negative_verified_audit.get(
                "raw_overlap_substitution_guard_status"),
            "raw_overlap_substitution_guard_handoff_rows":
                negative_verified_audit.get(
                    "raw_overlap_substitution_guard_handoff_rows"),
            "raw_overlap_substitution_guard_accounting_rows":
                negative_verified_audit.get(
                    "raw_overlap_substitution_guard_accounting_rows"),
            "raw_overlap_substitution_guard_object_summary_rows":
                negative_verified_audit.get(
                    "raw_overlap_substitution_guard_object_summary_rows"),
            "raw_overlap_verified_substitution_status":
                negative_verified_audit.get(
                    "raw_overlap_verified_substitution_status"),
            "raw_overlap_verified_substitution_cpu_handoff_rows":
                negative_verified_audit.get(
                    "raw_overlap_verified_substitution_cpu_handoff_rows"),
            "raw_overlap_verified_substitution_would_substitute_rows":
                negative_verified_audit.get(
                    "raw_overlap_verified_substitution_would_substitute_rows"),
            "raw_overlap_verified_substitution_ledger_rows":
                negative_verified_audit.get(
                    "raw_overlap_verified_substitution_ledger_rows"),
            "graph_facing_validation_timing_ms": negative_verified_audit.get(
                "graph_facing_validation_timing_ms"),
            "graph_mutation_consumed_worker_output": negative_verified_audit.get(
                "graph_mutation_consumed_worker_output"),
            "error": negative_verified_audit.get("error"),
        },
        "response": negative_verified_response,
        "rehydration": negative_verified_rehydration,
        "shadow_ledger": negative_verified_ledger,
        "graph_edge_binding": negative_verified_binding,
        "object_vector_smoke": negative_verified_smoke,
        "substitution_guard": negative_verified_guard,
        "verified_substitution": negative_verified_substitution,
        "source_pack": {
            "validation_status": negative_verified_source_pack.get("status"),
            "canonical_sha256": negative_verified_source_pack.get(
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
        "M8g proves the M8 selected handoff contract can be compared against "
        "a verified-substitution ledger by row key and deterministic order "
        "while preserving a bounded selected no-mutation advantage."
    ),
    "forbidden_claim": (
        "M8g does not prove default GPU mode, unguarded graph mutation, "
        "actual object-vector substitution into Flye graph update logic, "
        "selected CPU bypass, full non-key raw-overlap field parity, or "
        "whole-Flye speedup."
    ),
    "plain_language_benefit": (
        "M8g shows the selected CUDA path can take the guarded M8f handoff "
        "and prove its verified-substitution ledger matches the CPU-selected "
        "handoff by row key and order. The warm no-mutation seam total averages "
        f"{timing_summary['warm_no_mutation_seam_total_avg']:.6f} ms versus "
        f"the matched CPU quick-overlap baseline {m8a_baseline_ms:.6f} ms, "
        f"or {speedup['warm_no_mutation_seam_total_avg']:.3f}x faster."
    ),
    "next_recommended_step": (
        "M8h: turn the selected verified-substitution ledger into a "
        "selected bypass-plan ledger while still stopping before unguarded "
        "graph mutation."
    ),
}

(proof_root / "cuflye-m8g-selected-handoff-verified-substitution-ledger-dgx-aarch64.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n")
print(json.dumps({
    "checks": f"{manifest['summary_checks_passed']} / {manifest['summary_checks_required']}",
    "warm_graph_edge_binding_avg_ms": timing_summary[
        "warm_raw_overlap_graph_edge_binding_avg"],
    "warm_object_vector_smoke_avg_ms": timing_summary[
        "warm_raw_overlap_object_vector_smoke_avg"],
    "warm_handoff_contract_avg_ms": timing_summary[
        "warm_raw_overlap_substitution_guard_avg"],
    "warm_verified_substitution_avg_ms": timing_summary[
        "warm_raw_overlap_verified_substitution_avg"],
    "warm_no_mutation_seam_total_avg_ms": timing_summary[
        "warm_no_mutation_seam_total_avg"],
    "warm_no_mutation_speedup": speedup["warm_no_mutation_seam_total_avg"],
}, indent=2, sort_keys=True))
PY

echo "summary=${proof_root}/cuflye-m8g-selected-handoff-verified-substitution-ledger-dgx-aarch64.json"
