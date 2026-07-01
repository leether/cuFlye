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
  --threads N          Flye thread count. Default: 1 for deterministic oracle
  --min-overlap N      Flye -m value. Default: 1000 for toy fixtures
  --genome-size SIZE   Flye -g value. Default: 500k for toy fixtures
  --reads PATH         Reads path. Required for --fixture custom
  --read-type TYPE     Flye read type for custom: pacbio-raw, pacbio-corr,
                       pacbio-hifi, nano-raw, nano-hq, nano-corr, subassemblies
  --candidate-dump PATH
                       Enable cuFlye patched candidate dump at PATH
  --overlap-dump PATH  Enable cuFlye patched overlap-range dump at PATH
  --read-alignment-dump PATH
                       Enable cuFlye patched read-alignment-v1 dump at PATH
  --read-alignment-replay-dump-dir PATH
                       Set CUFLYE_READ_ALIGNMENT_REPLAY_DUMP_DIR for M5b fixture
  --read-alignment-replay-query-id ID
                       Set CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_ID
  --read-alignment-replay-query-ids IDS
                       Set CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS comma-separated allowlist
  --read-alignment-worker-mode MODE
                       Set CUFLYE_READ_ALIGNMENT_WORKER_MODE
  --read-alignment-worker-bin PATH
                       Set CUFLYE_READ_ALIGNMENT_WORKER_BIN
  --read-alignment-worker-output-dir PATH
                       Set CUFLYE_READ_ALIGNMENT_WORKER_OUTPUT_DIR
  --read-alignment-worker-device ID
                       Set CUFLYE_READ_ALIGNMENT_WORKER_DEVICE
  --read-alignment-worker-warmup-runs N
                       Set CUFLYE_READ_ALIGNMENT_WORKER_WARMUP_RUNS
  --read-alignment-worker-benchmark-runs N
                       Set CUFLYE_READ_ALIGNMENT_WORKER_BENCHMARK_RUNS
  --read-alignment-worker-memory-budget-bytes N
                       Set CUFLYE_READ_ALIGNMENT_WORKER_MEMORY_BUDGET_BYTES
  --read-alignment-worker-validation-mode MODE
                       Set CUFLYE_READ_ALIGNMENT_WORKER_VALIDATION_MODE
  --read-alignment-worker-lifecycle-mode MODE
                       Set CUFLYE_READ_ALIGNMENT_WORKER_LIFECYCLE_MODE
  --read-alignment-worker-session-dir PATH
                       Set CUFLYE_READ_ALIGNMENT_WORKER_SESSION_DIR
  --read-alignment-worker-session-poll-ms N
                       Set CUFLYE_READ_ALIGNMENT_WORKER_SESSION_POLL_MS
  --read-alignment-worker-session-timeout-ms N
                       Set CUFLYE_READ_ALIGNMENT_WORKER_SESSION_TIMEOUT_MS
  --read-alignment-graph-consumption-mode MODE
                       Set CUFLYE_READ_ALIGNMENT_GRAPH_CONSUMPTION_MODE
  --read-alignment-rehydration-mode MODE
                       Set CUFLYE_READ_ALIGNMENT_REHYDRATION_MODE
  --read-alignment-rehydration-proof-fault NAME
                       Set CUFLYE_READ_ALIGNMENT_REHYDRATION_PROOF_FAULT
  --read-alignment-object-rehydration-mode MODE
                       Set CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_MODE
  --read-alignment-object-rehydration-proof-fault NAME
                       Set CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_PROOF_FAULT
  --read-alignment-vector-substitution-mode MODE
                       Set CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_MODE
  --read-alignment-vector-substitution-proof-fault NAME
                       Set CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_PROOF_FAULT
  --read-alignment-predivergence-chain-mode MODE
                       Set CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_MODE
  --read-alignment-predivergence-chain-proof-fault NAME
                       Set CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_PROOF_FAULT
  --read-alignment-input-boundary-dump PATH
                       Set CUFLYE_READ_ALIGNMENT_INPUT_BOUNDARY_DUMP
  --read-to-graph-source-pack-dir PATH
                       Set CUFLYE_READ_TO_GRAPH_SOURCE_PACK_DIR
  --read-to-graph-source-pack-query-ids IDS
                       Set CUFLYE_READ_TO_GRAPH_SOURCE_PACK_QUERY_IDS
  --read-to-graph-full-query-hit-worker-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE
  --read-to-graph-full-query-hit-worker-lifecycle-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_LIFECYCLE_MODE
  --read-to-graph-full-query-hit-worker-bin PATH
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_BIN
  --read-to-graph-full-query-hit-worker-output-dir PATH
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_OUTPUT_DIR
  --read-to-graph-full-query-hit-worker-session-dir PATH
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_DIR
  --read-to-graph-full-query-hit-worker-session-poll-ms N
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_POLL_MS
  --read-to-graph-full-query-hit-worker-session-timeout-ms N
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_TIMEOUT_MS
  --read-to-graph-full-query-hit-worker-device ID
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_DEVICE
  --read-to-graph-full-query-hit-worker-kernel-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_KERNEL_MODE
  --read-to-graph-full-query-hit-worker-memory-budget-bytes N
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MEMORY_BUDGET_BYTES
  --read-to-graph-full-query-hit-rehydration-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_MODE
  --read-to-graph-full-query-hit-rehydration-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_PROOF_FAULT
  --read-to-graph-full-query-hit-shadow-ledger-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_MODE
  --read-to-graph-full-query-hit-shadow-ledger-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_PROOF_FAULT
  --read-to-graph-full-query-hit-graph-edge-binding-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_GRAPH_EDGE_BINDING_MODE
  --read-to-graph-full-query-hit-graph-edge-binding-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_GRAPH_EDGE_BINDING_PROOF_FAULT
  --read-to-graph-full-query-hit-object-vector-smoke-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_OBJECT_VECTOR_SMOKE_MODE
  --read-to-graph-full-query-hit-object-vector-smoke-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_OBJECT_VECTOR_SMOKE_PROOF_FAULT
  --read-to-graph-full-query-hit-substitution-guard-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_MODE
  --read-to-graph-full-query-hit-substitution-guard-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_PROOF_FAULT
  --read-to-graph-full-query-hit-verified-substitution-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_VERIFIED_SUBSTITUTION_MODE
  --read-to-graph-full-query-hit-verified-substitution-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_VERIFIED_SUBSTITUTION_PROOF_FAULT
  --read-to-graph-full-query-hit-selected-bypass-plan-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_PLAN_MODE
  --read-to-graph-full-query-hit-selected-bypass-plan-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_PLAN_PROOF_FAULT
  --read-to-graph-full-query-hit-selected-bypass-dry-run-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_DRY_RUN_MODE
  --read-to-graph-full-query-hit-selected-bypass-dry-run-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_DRY_RUN_PROOF_FAULT
  --read-to-graph-full-query-hit-selected-cpu-bypass-smoke-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_MODE
  --read-to-graph-full-query-hit-selected-cpu-bypass-smoke-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_PROOF_FAULT
  --read-to-graph-full-query-hit-selected-graph-consumption-parity-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_MODE
  --read-to-graph-full-query-hit-selected-graph-consumption-parity-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_PROOF_FAULT
  --read-to-graph-full-query-hit-selected-graph-consumption-mutation-canary-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_MODE
  --read-to-graph-full-query-hit-selected-graph-consumption-mutation-canary-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_PROOF_FAULT
  --read-to-graph-full-query-hit-selected-cpu-skip-canary-mode MODE
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_MODE
  --read-to-graph-full-query-hit-selected-cpu-skip-canary-proof-fault NAME
                       Set CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_PROOF_FAULT
  --overlap-replay-dump-dir PATH
                       Set CUFLYE_OVERLAP_REPLAY_DUMP_DIR for M4b replay fixture
  --overlap-replay-query-id ID
                       Set CUFLYE_OVERLAP_REPLAY_QUERY_ID
  --overlap-replay-query-ids IDS
                       Set CUFLYE_OVERLAP_REPLAY_QUERY_IDS comma-separated allowlist
  --overlap-replay-max-fixtures N
                       Set CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES
  --overlap-replay-stop-after-dump
                       Set CUFLYE_OVERLAP_REPLAY_STOP_AFTER_DUMP=1
  --candidate-backend NAME
                       Set CUFLYE_CANDIDATE_BACKEND for patched Flye
  --cuda-device ID     Set CUFLYE_CUDA_DEVICE for CUDA backend experiments
  --cuda-memory-budget-bytes N
                       Set CUFLYE_CUDA_MEMORY_BUDGET_BYTES
  --cuda-adapter-mode NAME
                       Set CUFLYE_CUDA_ADAPTER_MODE
  --cuda-backend-bin PATH
                       Set CUFLYE_CUDA_BACKEND_BIN for external CUDA adapter shell
  --cuda-packed-fixture-dir PATH
                       Set CUFLYE_CUDA_PACKED_FIXTURE_DIR
  --cuda-adapter-output-tsv PATH
                       Set CUFLYE_CUDA_ADAPTER_OUTPUT_TSV
  --cuda-adapter-json PATH
                       Set CUFLYE_CUDA_ADAPTER_JSON
  --cuda-packed-kmer-size N
                       Set CUFLYE_CUDA_PACKED_KMER_SIZE
  --cuda-pack-dump-dir PATH
                       Set CUFLYE_CUDA_PACK_DUMP_DIR for M2b real-data pack dump
  --cuda-pack-query-id ID
                       Set CUFLYE_CUDA_PACK_QUERY_ID
  --cuda-stop-after-packed-query
                       Set CUFLYE_CUDA_STOP_AFTER_PACKED_QUERY=1
  --overlap-worker-mode MODE
                       Set CUFLYE_OVERLAP_WORKER_MODE for M4j seam proof
  --overlap-worker-bin PATH
                       Set CUFLYE_OVERLAP_WORKER_BIN
  --overlap-worker-output-dir PATH
                       Set CUFLYE_OVERLAP_WORKER_OUTPUT_DIR
  --overlap-worker-device ID
                       Set CUFLYE_OVERLAP_WORKER_DEVICE
  --overlap-worker-kernel-mode MODE
                       Set CUFLYE_OVERLAP_WORKER_KERNEL_MODE
  --overlap-worker-warmup-runs N
                       Set CUFLYE_OVERLAP_WORKER_WARMUP_RUNS
  --overlap-worker-benchmark-runs N
                       Set CUFLYE_OVERLAP_WORKER_BENCHMARK_RUNS
  --overlap-worker-memory-budget-bytes N
                       Set CUFLYE_OVERLAP_WORKER_MEMORY_BUDGET_BYTES
  --overlap-worker-validation-mode MODE
                       Set CUFLYE_OVERLAP_WORKER_VALIDATION_MODE
  --overlap-worker-shadow-mode MODE
                       Set CUFLYE_OVERLAP_WORKER_SHADOW_MODE
  --overlap-worker-lifecycle-mode MODE
                       Set CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE
  --overlap-worker-session-dir PATH
                       Set CUFLYE_OVERLAP_WORKER_SESSION_DIR
  --overlap-worker-session-poll-ms N
                       Set CUFLYE_OVERLAP_WORKER_SESSION_POLL_MS
  --overlap-worker-session-timeout-ms N
                       Set CUFLYE_OVERLAP_WORKER_SESSION_TIMEOUT_MS
  --overlap-graph-consumption-mode MODE
                       Set CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE
  --overlap-rehydration-mode MODE
                       Set CUFLYE_OVERLAP_REHYDRATION_MODE
  --overlap-rehydration-proof-fault NAME
                       Set CUFLYE_OVERLAP_REHYDRATION_PROOF_FAULT
  --overlap-object-rehydration-mode MODE
                       Set CUFLYE_OVERLAP_OBJECT_REHYDRATION_MODE
  --overlap-object-rehydration-proof-fault NAME
                       Set CUFLYE_OVERLAP_OBJECT_REHYDRATION_PROOF_FAULT
  --overlap-vector-substitution-mode MODE
                       Set CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE
  --overlap-vector-substitution-ledger-mode MODE
                       Set CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_LEDGER_MODE
  --overlap-gpu-first-audit-mode MODE
                       Set CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE
  --overlap-gpu-first-audit-query-ids IDS
                       Set CUFLYE_OVERLAP_GPU_FIRST_AUDIT_QUERY_IDS
  --overlap-vector-substitution-proof-fault NAME
                       Set CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT
  --extra-arg ARG      Extra Flye argument. May be repeated.
  --force              Remove existing output directory before running
  --expect-failure     Record non-zero Flye exit as expected metadata
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
threads="${THREADS:-1}"
min_overlap="1000"
genome_size="500k"
reads=""
read_type=""
force=0
expect_failure=0
candidate_dump=""
overlap_dump=""
read_alignment_dump="${CUFLYE_READ_ALIGNMENT_DUMP:-}"
read_alignment_input_boundary_dump="${CUFLYE_READ_ALIGNMENT_INPUT_BOUNDARY_DUMP:-}"
read_alignment_replay_dump_dir="${CUFLYE_READ_ALIGNMENT_REPLAY_DUMP_DIR:-}"
read_alignment_replay_query_id="${CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_ID:-}"
read_alignment_replay_query_ids="${CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS:-}"
read_alignment_worker_mode="${CUFLYE_READ_ALIGNMENT_WORKER_MODE:-}"
read_alignment_worker_bin="${CUFLYE_READ_ALIGNMENT_WORKER_BIN:-}"
read_alignment_worker_output_dir="${CUFLYE_READ_ALIGNMENT_WORKER_OUTPUT_DIR:-}"
read_alignment_worker_device="${CUFLYE_READ_ALIGNMENT_WORKER_DEVICE:-}"
read_alignment_worker_warmup_runs="${CUFLYE_READ_ALIGNMENT_WORKER_WARMUP_RUNS:-}"
read_alignment_worker_benchmark_runs="${CUFLYE_READ_ALIGNMENT_WORKER_BENCHMARK_RUNS:-}"
read_alignment_worker_memory_budget_bytes="${CUFLYE_READ_ALIGNMENT_WORKER_MEMORY_BUDGET_BYTES:-}"
read_alignment_worker_validation_mode="${CUFLYE_READ_ALIGNMENT_WORKER_VALIDATION_MODE:-}"
read_alignment_worker_lifecycle_mode="${CUFLYE_READ_ALIGNMENT_WORKER_LIFECYCLE_MODE:-}"
read_alignment_worker_session_dir="${CUFLYE_READ_ALIGNMENT_WORKER_SESSION_DIR:-}"
read_alignment_worker_session_poll_ms="${CUFLYE_READ_ALIGNMENT_WORKER_SESSION_POLL_MS:-}"
read_alignment_worker_session_timeout_ms="${CUFLYE_READ_ALIGNMENT_WORKER_SESSION_TIMEOUT_MS:-}"
read_alignment_graph_consumption_mode="${CUFLYE_READ_ALIGNMENT_GRAPH_CONSUMPTION_MODE:-}"
read_alignment_rehydration_mode="${CUFLYE_READ_ALIGNMENT_REHYDRATION_MODE:-}"
read_alignment_rehydration_proof_fault="${CUFLYE_READ_ALIGNMENT_REHYDRATION_PROOF_FAULT:-}"
read_alignment_object_rehydration_mode="${CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_MODE:-}"
read_alignment_object_rehydration_proof_fault="${CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_PROOF_FAULT:-}"
read_alignment_vector_substitution_mode="${CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_MODE:-}"
read_alignment_vector_substitution_proof_fault="${CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_PROOF_FAULT:-}"
read_alignment_predivergence_chain_mode="${CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_MODE:-}"
read_alignment_predivergence_chain_proof_fault="${CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_PROOF_FAULT:-}"
read_to_graph_source_pack_dir="${CUFLYE_READ_TO_GRAPH_SOURCE_PACK_DIR:-}"
read_to_graph_source_pack_query_ids="${CUFLYE_READ_TO_GRAPH_SOURCE_PACK_QUERY_IDS:-}"
read_to_graph_full_query_hit_worker_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE:-}"
read_to_graph_full_query_hit_worker_lifecycle_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_LIFECYCLE_MODE:-}"
read_to_graph_full_query_hit_worker_bin="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_BIN:-}"
read_to_graph_full_query_hit_worker_output_dir="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_OUTPUT_DIR:-}"
read_to_graph_full_query_hit_worker_session_dir="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_DIR:-}"
read_to_graph_full_query_hit_worker_session_poll_ms="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_POLL_MS:-}"
read_to_graph_full_query_hit_worker_session_timeout_ms="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_TIMEOUT_MS:-}"
read_to_graph_full_query_hit_worker_device="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_DEVICE:-}"
read_to_graph_full_query_hit_worker_kernel_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_KERNEL_MODE:-}"
read_to_graph_full_query_hit_worker_memory_budget_bytes="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MEMORY_BUDGET_BYTES:-}"
read_to_graph_full_query_hit_rehydration_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_MODE:-}"
read_to_graph_full_query_hit_rehydration_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_PROOF_FAULT:-}"
read_to_graph_full_query_hit_shadow_ledger_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_MODE:-}"
read_to_graph_full_query_hit_shadow_ledger_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_PROOF_FAULT:-}"
read_to_graph_full_query_hit_graph_edge_binding_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_GRAPH_EDGE_BINDING_MODE:-}"
read_to_graph_full_query_hit_graph_edge_binding_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_GRAPH_EDGE_BINDING_PROOF_FAULT:-}"
read_to_graph_full_query_hit_object_vector_smoke_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_OBJECT_VECTOR_SMOKE_MODE:-}"
read_to_graph_full_query_hit_object_vector_smoke_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_OBJECT_VECTOR_SMOKE_PROOF_FAULT:-}"
read_to_graph_full_query_hit_substitution_guard_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_MODE:-}"
read_to_graph_full_query_hit_substitution_guard_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_PROOF_FAULT:-}"
read_to_graph_full_query_hit_verified_substitution_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_VERIFIED_SUBSTITUTION_MODE:-}"
read_to_graph_full_query_hit_verified_substitution_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_VERIFIED_SUBSTITUTION_PROOF_FAULT:-}"
read_to_graph_full_query_hit_selected_bypass_plan_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_PLAN_MODE:-}"
read_to_graph_full_query_hit_selected_bypass_plan_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_PLAN_PROOF_FAULT:-}"
read_to_graph_full_query_hit_selected_bypass_dry_run_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_DRY_RUN_MODE:-}"
read_to_graph_full_query_hit_selected_bypass_dry_run_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_DRY_RUN_PROOF_FAULT:-}"
read_to_graph_full_query_hit_selected_cpu_bypass_smoke_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_MODE:-}"
read_to_graph_full_query_hit_selected_cpu_bypass_smoke_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_PROOF_FAULT:-}"
read_to_graph_full_query_hit_selected_graph_consumption_parity_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_MODE:-}"
read_to_graph_full_query_hit_selected_graph_consumption_parity_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_PROOF_FAULT:-}"
read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_MODE:-}"
read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_PROOF_FAULT:-}"
read_to_graph_full_query_hit_selected_cpu_skip_canary_mode="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_MODE:-}"
read_to_graph_full_query_hit_selected_cpu_skip_canary_proof_fault="${CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_PROOF_FAULT:-}"
overlap_replay_dump_dir="${CUFLYE_OVERLAP_REPLAY_DUMP_DIR:-}"
overlap_replay_query_id="${CUFLYE_OVERLAP_REPLAY_QUERY_ID:-}"
overlap_replay_query_ids="${CUFLYE_OVERLAP_REPLAY_QUERY_IDS:-}"
overlap_replay_max_fixtures="${CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES:-}"
overlap_replay_stop_after_dump="${CUFLYE_OVERLAP_REPLAY_STOP_AFTER_DUMP:-}"
candidate_backend="${CUFLYE_CANDIDATE_BACKEND:-}"
cuda_device="${CUFLYE_CUDA_DEVICE:-}"
cuda_memory_budget_bytes="${CUFLYE_CUDA_MEMORY_BUDGET_BYTES:-}"
cuda_adapter_mode="${CUFLYE_CUDA_ADAPTER_MODE:-}"
cuda_backend_bin="${CUFLYE_CUDA_BACKEND_BIN:-}"
cuda_packed_fixture_dir="${CUFLYE_CUDA_PACKED_FIXTURE_DIR:-}"
cuda_adapter_output_tsv="${CUFLYE_CUDA_ADAPTER_OUTPUT_TSV:-}"
cuda_adapter_json="${CUFLYE_CUDA_ADAPTER_JSON:-}"
cuda_packed_kmer_size="${CUFLYE_CUDA_PACKED_KMER_SIZE:-}"
cuda_pack_dump_dir="${CUFLYE_CUDA_PACK_DUMP_DIR:-}"
cuda_pack_query_id="${CUFLYE_CUDA_PACK_QUERY_ID:-}"
cuda_stop_after_packed_query="${CUFLYE_CUDA_STOP_AFTER_PACKED_QUERY:-}"
overlap_worker_mode="${CUFLYE_OVERLAP_WORKER_MODE:-}"
overlap_worker_bin="${CUFLYE_OVERLAP_WORKER_BIN:-}"
overlap_worker_output_dir="${CUFLYE_OVERLAP_WORKER_OUTPUT_DIR:-}"
overlap_worker_device="${CUFLYE_OVERLAP_WORKER_DEVICE:-}"
overlap_worker_kernel_mode="${CUFLYE_OVERLAP_WORKER_KERNEL_MODE:-}"
overlap_worker_warmup_runs="${CUFLYE_OVERLAP_WORKER_WARMUP_RUNS:-}"
overlap_worker_benchmark_runs="${CUFLYE_OVERLAP_WORKER_BENCHMARK_RUNS:-}"
overlap_worker_memory_budget_bytes="${CUFLYE_OVERLAP_WORKER_MEMORY_BUDGET_BYTES:-}"
overlap_worker_validation_mode="${CUFLYE_OVERLAP_WORKER_VALIDATION_MODE:-}"
overlap_worker_shadow_mode="${CUFLYE_OVERLAP_WORKER_SHADOW_MODE:-}"
overlap_worker_lifecycle_mode="${CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE:-}"
overlap_worker_session_dir="${CUFLYE_OVERLAP_WORKER_SESSION_DIR:-}"
overlap_worker_session_poll_ms="${CUFLYE_OVERLAP_WORKER_SESSION_POLL_MS:-}"
overlap_worker_session_timeout_ms="${CUFLYE_OVERLAP_WORKER_SESSION_TIMEOUT_MS:-}"
overlap_graph_consumption_mode="${CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE:-}"
overlap_rehydration_mode="${CUFLYE_OVERLAP_REHYDRATION_MODE:-}"
overlap_rehydration_proof_fault="${CUFLYE_OVERLAP_REHYDRATION_PROOF_FAULT:-}"
overlap_object_rehydration_mode="${CUFLYE_OVERLAP_OBJECT_REHYDRATION_MODE:-}"
overlap_object_rehydration_proof_fault="${CUFLYE_OVERLAP_OBJECT_REHYDRATION_PROOF_FAULT:-}"
overlap_vector_substitution_mode="${CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE:-}"
overlap_vector_substitution_ledger_mode="${CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_LEDGER_MODE:-}"
overlap_gpu_first_audit_mode="${CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE:-}"
overlap_gpu_first_audit_query_ids="${CUFLYE_OVERLAP_GPU_FIRST_AUDIT_QUERY_IDS:-}"
overlap_vector_substitution_proof_fault="${CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT:-}"
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
    --candidate-dump)
      candidate_dump="$2"
      shift 2
      ;;
    --overlap-dump)
      overlap_dump="$2"
      shift 2
      ;;
    --read-alignment-dump)
      read_alignment_dump="$2"
      shift 2
      ;;
    --read-alignment-replay-dump-dir)
      read_alignment_replay_dump_dir="$2"
      shift 2
      ;;
    --read-alignment-replay-query-id)
      read_alignment_replay_query_id="$2"
      shift 2
      ;;
    --read-alignment-replay-query-ids)
      read_alignment_replay_query_ids="$2"
      shift 2
      ;;
    --read-alignment-worker-mode)
      read_alignment_worker_mode="$2"
      shift 2
      ;;
    --read-alignment-worker-bin)
      read_alignment_worker_bin="$2"
      shift 2
      ;;
    --read-alignment-worker-output-dir)
      read_alignment_worker_output_dir="$2"
      shift 2
      ;;
    --read-alignment-worker-device)
      read_alignment_worker_device="$2"
      shift 2
      ;;
    --read-alignment-worker-warmup-runs)
      read_alignment_worker_warmup_runs="$2"
      shift 2
      ;;
    --read-alignment-worker-benchmark-runs)
      read_alignment_worker_benchmark_runs="$2"
      shift 2
      ;;
    --read-alignment-worker-memory-budget-bytes)
      read_alignment_worker_memory_budget_bytes="$2"
      shift 2
      ;;
    --read-alignment-worker-validation-mode)
      read_alignment_worker_validation_mode="$2"
      shift 2
      ;;
    --read-alignment-worker-lifecycle-mode)
      read_alignment_worker_lifecycle_mode="$2"
      shift 2
      ;;
    --read-alignment-worker-session-dir)
      read_alignment_worker_session_dir="$2"
      shift 2
      ;;
    --read-alignment-worker-session-poll-ms)
      read_alignment_worker_session_poll_ms="$2"
      shift 2
      ;;
    --read-alignment-worker-session-timeout-ms)
      read_alignment_worker_session_timeout_ms="$2"
      shift 2
      ;;
    --read-alignment-graph-consumption-mode)
      read_alignment_graph_consumption_mode="$2"
      shift 2
      ;;
    --read-alignment-rehydration-mode)
      read_alignment_rehydration_mode="$2"
      shift 2
      ;;
    --read-alignment-rehydration-proof-fault)
      read_alignment_rehydration_proof_fault="$2"
      shift 2
      ;;
    --read-alignment-object-rehydration-mode)
      read_alignment_object_rehydration_mode="$2"
      shift 2
      ;;
    --read-alignment-object-rehydration-proof-fault)
      read_alignment_object_rehydration_proof_fault="$2"
      shift 2
      ;;
    --read-alignment-vector-substitution-mode)
      read_alignment_vector_substitution_mode="$2"
      shift 2
      ;;
    --read-alignment-vector-substitution-proof-fault)
      read_alignment_vector_substitution_proof_fault="$2"
      shift 2
      ;;
    --read-alignment-predivergence-chain-mode)
      read_alignment_predivergence_chain_mode="$2"
      shift 2
      ;;
    --read-alignment-predivergence-chain-proof-fault)
      read_alignment_predivergence_chain_proof_fault="$2"
      shift 2
      ;;
    --read-alignment-input-boundary-dump)
      read_alignment_input_boundary_dump="$2"
      shift 2
      ;;
    --read-to-graph-source-pack-dir)
      read_to_graph_source_pack_dir="$2"
      shift 2
      ;;
    --read-to-graph-source-pack-query-ids)
      read_to_graph_source_pack_query_ids="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-mode)
      read_to_graph_full_query_hit_worker_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-lifecycle-mode)
      read_to_graph_full_query_hit_worker_lifecycle_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-bin)
      read_to_graph_full_query_hit_worker_bin="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-output-dir)
      read_to_graph_full_query_hit_worker_output_dir="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-session-dir)
      read_to_graph_full_query_hit_worker_session_dir="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-session-poll-ms)
      read_to_graph_full_query_hit_worker_session_poll_ms="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-session-timeout-ms)
      read_to_graph_full_query_hit_worker_session_timeout_ms="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-device)
      read_to_graph_full_query_hit_worker_device="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-kernel-mode)
      read_to_graph_full_query_hit_worker_kernel_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-worker-memory-budget-bytes)
      read_to_graph_full_query_hit_worker_memory_budget_bytes="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-rehydration-mode)
      read_to_graph_full_query_hit_rehydration_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-rehydration-proof-fault)
      read_to_graph_full_query_hit_rehydration_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-shadow-ledger-mode)
      read_to_graph_full_query_hit_shadow_ledger_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-shadow-ledger-proof-fault)
      read_to_graph_full_query_hit_shadow_ledger_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-graph-edge-binding-mode)
      read_to_graph_full_query_hit_graph_edge_binding_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-graph-edge-binding-proof-fault)
      read_to_graph_full_query_hit_graph_edge_binding_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-object-vector-smoke-mode)
      read_to_graph_full_query_hit_object_vector_smoke_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-object-vector-smoke-proof-fault)
      read_to_graph_full_query_hit_object_vector_smoke_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-substitution-guard-mode)
      read_to_graph_full_query_hit_substitution_guard_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-substitution-guard-proof-fault)
      read_to_graph_full_query_hit_substitution_guard_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-verified-substitution-mode)
      read_to_graph_full_query_hit_verified_substitution_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-verified-substitution-proof-fault)
      read_to_graph_full_query_hit_verified_substitution_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-bypass-plan-mode)
      read_to_graph_full_query_hit_selected_bypass_plan_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-bypass-plan-proof-fault)
      read_to_graph_full_query_hit_selected_bypass_plan_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-bypass-dry-run-mode)
      read_to_graph_full_query_hit_selected_bypass_dry_run_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-bypass-dry-run-proof-fault)
      read_to_graph_full_query_hit_selected_bypass_dry_run_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-cpu-bypass-smoke-mode)
      read_to_graph_full_query_hit_selected_cpu_bypass_smoke_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-cpu-bypass-smoke-proof-fault)
      read_to_graph_full_query_hit_selected_cpu_bypass_smoke_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-graph-consumption-parity-mode)
      read_to_graph_full_query_hit_selected_graph_consumption_parity_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-graph-consumption-parity-proof-fault)
      read_to_graph_full_query_hit_selected_graph_consumption_parity_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-graph-consumption-mutation-canary-mode)
      read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-graph-consumption-mutation-canary-proof-fault)
      read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_proof_fault="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-cpu-skip-canary-mode)
      read_to_graph_full_query_hit_selected_cpu_skip_canary_mode="$2"
      shift 2
      ;;
    --read-to-graph-full-query-hit-selected-cpu-skip-canary-proof-fault)
      read_to_graph_full_query_hit_selected_cpu_skip_canary_proof_fault="$2"
      shift 2
      ;;
    --overlap-replay-dump-dir)
      overlap_replay_dump_dir="$2"
      shift 2
      ;;
    --overlap-replay-query-id)
      overlap_replay_query_id="$2"
      shift 2
      ;;
    --overlap-replay-query-ids)
      overlap_replay_query_ids="$2"
      shift 2
      ;;
    --overlap-replay-max-fixtures)
      overlap_replay_max_fixtures="$2"
      shift 2
      ;;
    --overlap-replay-stop-after-dump)
      overlap_replay_stop_after_dump=1
      shift
      ;;
    --candidate-backend)
      candidate_backend="$2"
      shift 2
      ;;
    --cuda-device)
      cuda_device="$2"
      shift 2
      ;;
    --cuda-memory-budget-bytes)
      cuda_memory_budget_bytes="$2"
      shift 2
      ;;
    --cuda-adapter-mode)
      cuda_adapter_mode="$2"
      shift 2
      ;;
    --cuda-backend-bin)
      cuda_backend_bin="$2"
      shift 2
      ;;
    --cuda-packed-fixture-dir)
      cuda_packed_fixture_dir="$2"
      shift 2
      ;;
    --cuda-adapter-output-tsv)
      cuda_adapter_output_tsv="$2"
      shift 2
      ;;
    --cuda-adapter-json)
      cuda_adapter_json="$2"
      shift 2
      ;;
    --cuda-packed-kmer-size)
      cuda_packed_kmer_size="$2"
      shift 2
      ;;
    --cuda-pack-dump-dir)
      cuda_pack_dump_dir="$2"
      shift 2
      ;;
    --cuda-pack-query-id)
      cuda_pack_query_id="$2"
      shift 2
      ;;
    --cuda-stop-after-packed-query)
      cuda_stop_after_packed_query=1
      shift
      ;;
    --overlap-worker-mode)
      overlap_worker_mode="$2"
      shift 2
      ;;
    --overlap-worker-bin)
      overlap_worker_bin="$2"
      shift 2
      ;;
    --overlap-worker-output-dir)
      overlap_worker_output_dir="$2"
      shift 2
      ;;
    --overlap-worker-device)
      overlap_worker_device="$2"
      shift 2
      ;;
    --overlap-worker-kernel-mode)
      overlap_worker_kernel_mode="$2"
      shift 2
      ;;
    --overlap-worker-warmup-runs)
      overlap_worker_warmup_runs="$2"
      shift 2
      ;;
    --overlap-worker-benchmark-runs)
      overlap_worker_benchmark_runs="$2"
      shift 2
      ;;
    --overlap-worker-memory-budget-bytes)
      overlap_worker_memory_budget_bytes="$2"
      shift 2
      ;;
    --overlap-worker-validation-mode)
      overlap_worker_validation_mode="$2"
      shift 2
      ;;
    --overlap-worker-shadow-mode)
      overlap_worker_shadow_mode="$2"
      shift 2
      ;;
    --overlap-worker-lifecycle-mode)
      overlap_worker_lifecycle_mode="$2"
      shift 2
      ;;
    --overlap-worker-session-dir)
      overlap_worker_session_dir="$2"
      shift 2
      ;;
    --overlap-worker-session-poll-ms)
      overlap_worker_session_poll_ms="$2"
      shift 2
      ;;
    --overlap-worker-session-timeout-ms)
      overlap_worker_session_timeout_ms="$2"
      shift 2
      ;;
    --overlap-graph-consumption-mode)
      overlap_graph_consumption_mode="$2"
      shift 2
      ;;
    --overlap-rehydration-mode)
      overlap_rehydration_mode="$2"
      shift 2
      ;;
    --overlap-rehydration-proof-fault)
      overlap_rehydration_proof_fault="$2"
      shift 2
      ;;
    --overlap-object-rehydration-mode)
      overlap_object_rehydration_mode="$2"
      shift 2
      ;;
    --overlap-object-rehydration-proof-fault)
      overlap_object_rehydration_proof_fault="$2"
      shift 2
      ;;
    --overlap-vector-substitution-mode)
      overlap_vector_substitution_mode="$2"
      shift 2
      ;;
    --overlap-vector-substitution-ledger-mode)
      overlap_vector_substitution_ledger_mode="$2"
      shift 2
      ;;
    --overlap-gpu-first-audit-mode)
      overlap_gpu_first_audit_mode="$2"
      shift 2
      ;;
    --overlap-gpu-first-audit-query-ids)
      overlap_gpu_first_audit_query_ids="$2"
      shift 2
      ;;
    --overlap-vector-substitution-proof-fault)
      overlap_vector_substitution_proof_fault="$2"
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
    --expect-failure)
      expect_failure=1
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
if [ -n "${candidate_dump}" ]; then
  mkdir -p "$(dirname "${candidate_dump}")"
  rm -f "${candidate_dump}"
fi
if [ -n "${overlap_dump}" ]; then
  mkdir -p "$(dirname "${overlap_dump}")"
  rm -f "${overlap_dump}"
fi
if [ -n "${read_alignment_dump}" ]; then
  mkdir -p "$(dirname "${read_alignment_dump}")"
  rm -f "${read_alignment_dump}"
fi
if [ -n "${read_alignment_replay_dump_dir}" ]; then
  rm -rf "${read_alignment_replay_dump_dir}"
  mkdir -p "${read_alignment_replay_dump_dir}"
fi
if [ -n "${read_alignment_worker_output_dir}" ]; then
  rm -rf "${read_alignment_worker_output_dir}"
  mkdir -p "${read_alignment_worker_output_dir}"
fi
if [ -n "${read_to_graph_source_pack_dir}" ]; then
  rm -rf "${read_to_graph_source_pack_dir}"
  mkdir -p "${read_to_graph_source_pack_dir}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_output_dir}" ]; then
  rm -rf "${read_to_graph_full_query_hit_worker_output_dir}"
  mkdir -p "${read_to_graph_full_query_hit_worker_output_dir}"
fi
if [ -n "${overlap_replay_dump_dir}" ]; then
  rm -rf "${overlap_replay_dump_dir}"
  mkdir -p "${overlap_replay_dump_dir}"
fi
if [ -n "${cuda_adapter_output_tsv}" ]; then
  mkdir -p "$(dirname "${cuda_adapter_output_tsv}")"
  rm -f "${cuda_adapter_output_tsv}"
fi
if [ -n "${cuda_adapter_json}" ]; then
  mkdir -p "$(dirname "${cuda_adapter_json}")"
  rm -f "${cuda_adapter_json}"
fi
if [ -n "${cuda_pack_dump_dir}" ]; then
  rm -rf "${cuda_pack_dump_dir}"
  mkdir -p "${cuda_pack_dump_dir}"
fi
if [ -n "${overlap_worker_output_dir}" ]; then
  rm -rf "${overlap_worker_output_dir}"
  mkdir -p "${overlap_worker_output_dir}"
fi

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

if [ -n "${candidate_dump}" ]; then
  export CUFLYE_CANDIDATE_DUMP="${candidate_dump}"
fi
if [ -n "${overlap_dump}" ]; then
  export CUFLYE_OVERLAP_DUMP="${overlap_dump}"
fi
if [ -n "${read_alignment_dump}" ]; then
  export CUFLYE_READ_ALIGNMENT_DUMP="${read_alignment_dump}"
fi
if [ -n "${read_alignment_input_boundary_dump}" ]; then
  export CUFLYE_READ_ALIGNMENT_INPUT_BOUNDARY_DUMP="${read_alignment_input_boundary_dump}"
fi
if [ -n "${read_alignment_replay_dump_dir}" ]; then
  export CUFLYE_READ_ALIGNMENT_REPLAY_DUMP_DIR="${read_alignment_replay_dump_dir}"
fi
if [ -n "${read_alignment_replay_query_id}" ]; then
  export CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_ID="${read_alignment_replay_query_id}"
fi
if [ -n "${read_alignment_replay_query_ids}" ]; then
  export CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS="${read_alignment_replay_query_ids}"
fi
if [ -n "${read_alignment_worker_mode}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_MODE="${read_alignment_worker_mode}"
fi
if [ -n "${read_alignment_worker_bin}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_BIN="${read_alignment_worker_bin}"
fi
if [ -n "${read_alignment_worker_output_dir}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_OUTPUT_DIR="${read_alignment_worker_output_dir}"
fi
if [ -n "${read_alignment_worker_device}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_DEVICE="${read_alignment_worker_device}"
fi
if [ -n "${read_alignment_worker_warmup_runs}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_WARMUP_RUNS="${read_alignment_worker_warmup_runs}"
fi
if [ -n "${read_alignment_worker_benchmark_runs}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_BENCHMARK_RUNS="${read_alignment_worker_benchmark_runs}"
fi
if [ -n "${read_alignment_worker_memory_budget_bytes}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_MEMORY_BUDGET_BYTES="${read_alignment_worker_memory_budget_bytes}"
fi
if [ -n "${read_alignment_worker_validation_mode}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_VALIDATION_MODE="${read_alignment_worker_validation_mode}"
fi
if [ -n "${read_alignment_worker_lifecycle_mode}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_LIFECYCLE_MODE="${read_alignment_worker_lifecycle_mode}"
fi
if [ -n "${read_alignment_worker_session_dir}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_SESSION_DIR="${read_alignment_worker_session_dir}"
fi
if [ -n "${read_alignment_worker_session_poll_ms}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_SESSION_POLL_MS="${read_alignment_worker_session_poll_ms}"
fi
if [ -n "${read_alignment_worker_session_timeout_ms}" ]; then
  export CUFLYE_READ_ALIGNMENT_WORKER_SESSION_TIMEOUT_MS="${read_alignment_worker_session_timeout_ms}"
fi
if [ -n "${read_alignment_graph_consumption_mode}" ]; then
  export CUFLYE_READ_ALIGNMENT_GRAPH_CONSUMPTION_MODE="${read_alignment_graph_consumption_mode}"
fi
if [ -n "${read_alignment_rehydration_mode}" ]; then
  export CUFLYE_READ_ALIGNMENT_REHYDRATION_MODE="${read_alignment_rehydration_mode}"
fi
if [ -n "${read_alignment_rehydration_proof_fault}" ]; then
  export CUFLYE_READ_ALIGNMENT_REHYDRATION_PROOF_FAULT="${read_alignment_rehydration_proof_fault}"
fi
if [ -n "${read_alignment_object_rehydration_mode}" ]; then
  export CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_MODE="${read_alignment_object_rehydration_mode}"
fi
if [ -n "${read_alignment_object_rehydration_proof_fault}" ]; then
  export CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_PROOF_FAULT="${read_alignment_object_rehydration_proof_fault}"
fi
if [ -n "${read_alignment_vector_substitution_mode}" ]; then
  export CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_MODE="${read_alignment_vector_substitution_mode}"
fi
if [ -n "${read_alignment_vector_substitution_proof_fault}" ]; then
  export CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_PROOF_FAULT="${read_alignment_vector_substitution_proof_fault}"
fi
if [ -n "${read_alignment_predivergence_chain_mode}" ]; then
  export CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_MODE="${read_alignment_predivergence_chain_mode}"
fi
if [ -n "${read_alignment_predivergence_chain_proof_fault}" ]; then
  export CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_PROOF_FAULT="${read_alignment_predivergence_chain_proof_fault}"
fi
if [ -n "${read_to_graph_source_pack_dir}" ]; then
  export CUFLYE_READ_TO_GRAPH_SOURCE_PACK_DIR="${read_to_graph_source_pack_dir}"
fi
if [ -n "${read_to_graph_source_pack_query_ids}" ]; then
  export CUFLYE_READ_TO_GRAPH_SOURCE_PACK_QUERY_IDS="${read_to_graph_source_pack_query_ids}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE="${read_to_graph_full_query_hit_worker_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_lifecycle_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_LIFECYCLE_MODE="${read_to_graph_full_query_hit_worker_lifecycle_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_bin}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_BIN="${read_to_graph_full_query_hit_worker_bin}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_output_dir}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_OUTPUT_DIR="${read_to_graph_full_query_hit_worker_output_dir}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_session_dir}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_DIR="${read_to_graph_full_query_hit_worker_session_dir}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_session_poll_ms}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_POLL_MS="${read_to_graph_full_query_hit_worker_session_poll_ms}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_session_timeout_ms}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_TIMEOUT_MS="${read_to_graph_full_query_hit_worker_session_timeout_ms}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_device}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_DEVICE="${read_to_graph_full_query_hit_worker_device}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_kernel_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_KERNEL_MODE="${read_to_graph_full_query_hit_worker_kernel_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_worker_memory_budget_bytes}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MEMORY_BUDGET_BYTES="${read_to_graph_full_query_hit_worker_memory_budget_bytes}"
fi
if [ -n "${read_to_graph_full_query_hit_rehydration_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_MODE="${read_to_graph_full_query_hit_rehydration_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_rehydration_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_PROOF_FAULT="${read_to_graph_full_query_hit_rehydration_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_shadow_ledger_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_MODE="${read_to_graph_full_query_hit_shadow_ledger_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_shadow_ledger_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_PROOF_FAULT="${read_to_graph_full_query_hit_shadow_ledger_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_graph_edge_binding_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_GRAPH_EDGE_BINDING_MODE="${read_to_graph_full_query_hit_graph_edge_binding_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_graph_edge_binding_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_GRAPH_EDGE_BINDING_PROOF_FAULT="${read_to_graph_full_query_hit_graph_edge_binding_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_object_vector_smoke_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_OBJECT_VECTOR_SMOKE_MODE="${read_to_graph_full_query_hit_object_vector_smoke_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_object_vector_smoke_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_OBJECT_VECTOR_SMOKE_PROOF_FAULT="${read_to_graph_full_query_hit_object_vector_smoke_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_substitution_guard_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_MODE="${read_to_graph_full_query_hit_substitution_guard_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_substitution_guard_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_PROOF_FAULT="${read_to_graph_full_query_hit_substitution_guard_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_verified_substitution_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_VERIFIED_SUBSTITUTION_MODE="${read_to_graph_full_query_hit_verified_substitution_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_verified_substitution_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_VERIFIED_SUBSTITUTION_PROOF_FAULT="${read_to_graph_full_query_hit_verified_substitution_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_bypass_plan_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_PLAN_MODE="${read_to_graph_full_query_hit_selected_bypass_plan_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_bypass_plan_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_PLAN_PROOF_FAULT="${read_to_graph_full_query_hit_selected_bypass_plan_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_bypass_dry_run_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_DRY_RUN_MODE="${read_to_graph_full_query_hit_selected_bypass_dry_run_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_bypass_dry_run_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_DRY_RUN_PROOF_FAULT="${read_to_graph_full_query_hit_selected_bypass_dry_run_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_cpu_bypass_smoke_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_MODE="${read_to_graph_full_query_hit_selected_cpu_bypass_smoke_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_cpu_bypass_smoke_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_PROOF_FAULT="${read_to_graph_full_query_hit_selected_cpu_bypass_smoke_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_graph_consumption_parity_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_MODE="${read_to_graph_full_query_hit_selected_graph_consumption_parity_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_graph_consumption_parity_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_PROOF_FAULT="${read_to_graph_full_query_hit_selected_graph_consumption_parity_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_MODE="${read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_PROOF_FAULT="${read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_proof_fault}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_cpu_skip_canary_mode}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_MODE="${read_to_graph_full_query_hit_selected_cpu_skip_canary_mode}"
fi
if [ -n "${read_to_graph_full_query_hit_selected_cpu_skip_canary_proof_fault}" ]; then
  export CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_PROOF_FAULT="${read_to_graph_full_query_hit_selected_cpu_skip_canary_proof_fault}"
fi
if [ -n "${overlap_replay_dump_dir}" ]; then
  export CUFLYE_OVERLAP_REPLAY_DUMP_DIR="${overlap_replay_dump_dir}"
fi
if [ -n "${overlap_replay_query_id}" ]; then
  export CUFLYE_OVERLAP_REPLAY_QUERY_ID="${overlap_replay_query_id}"
fi
if [ -n "${overlap_replay_query_ids}" ]; then
  export CUFLYE_OVERLAP_REPLAY_QUERY_IDS="${overlap_replay_query_ids}"
fi
if [ -n "${overlap_replay_max_fixtures}" ]; then
  export CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES="${overlap_replay_max_fixtures}"
fi
if [ -n "${overlap_replay_stop_after_dump}" ]; then
  export CUFLYE_OVERLAP_REPLAY_STOP_AFTER_DUMP="${overlap_replay_stop_after_dump}"
fi
if [ -n "${candidate_backend}" ]; then
  export CUFLYE_CANDIDATE_BACKEND="${candidate_backend}"
fi
if [ -n "${cuda_device}" ]; then
  export CUFLYE_CUDA_DEVICE="${cuda_device}"
fi
if [ -n "${cuda_memory_budget_bytes}" ]; then
  export CUFLYE_CUDA_MEMORY_BUDGET_BYTES="${cuda_memory_budget_bytes}"
fi
if [ -n "${cuda_adapter_mode}" ]; then
  export CUFLYE_CUDA_ADAPTER_MODE="${cuda_adapter_mode}"
fi
if [ -n "${cuda_backend_bin}" ]; then
  export CUFLYE_CUDA_BACKEND_BIN="${cuda_backend_bin}"
fi
if [ -n "${cuda_packed_fixture_dir}" ]; then
  export CUFLYE_CUDA_PACKED_FIXTURE_DIR="${cuda_packed_fixture_dir}"
fi
if [ -n "${cuda_adapter_output_tsv}" ]; then
  export CUFLYE_CUDA_ADAPTER_OUTPUT_TSV="${cuda_adapter_output_tsv}"
fi
if [ -n "${cuda_adapter_json}" ]; then
  export CUFLYE_CUDA_ADAPTER_JSON="${cuda_adapter_json}"
fi
if [ -n "${cuda_packed_kmer_size}" ]; then
  export CUFLYE_CUDA_PACKED_KMER_SIZE="${cuda_packed_kmer_size}"
fi
if [ -n "${cuda_pack_dump_dir}" ]; then
  export CUFLYE_CUDA_PACK_DUMP_DIR="${cuda_pack_dump_dir}"
fi
if [ -n "${cuda_pack_query_id}" ]; then
  export CUFLYE_CUDA_PACK_QUERY_ID="${cuda_pack_query_id}"
fi
if [ -n "${cuda_stop_after_packed_query}" ]; then
  export CUFLYE_CUDA_STOP_AFTER_PACKED_QUERY="${cuda_stop_after_packed_query}"
fi
if [ -n "${overlap_worker_mode}" ]; then
  export CUFLYE_OVERLAP_WORKER_MODE="${overlap_worker_mode}"
fi
if [ -n "${overlap_worker_bin}" ]; then
  export CUFLYE_OVERLAP_WORKER_BIN="${overlap_worker_bin}"
fi
if [ -n "${overlap_worker_output_dir}" ]; then
  export CUFLYE_OVERLAP_WORKER_OUTPUT_DIR="${overlap_worker_output_dir}"
fi
if [ -n "${overlap_worker_device}" ]; then
  export CUFLYE_OVERLAP_WORKER_DEVICE="${overlap_worker_device}"
fi
if [ -n "${overlap_worker_kernel_mode}" ]; then
  export CUFLYE_OVERLAP_WORKER_KERNEL_MODE="${overlap_worker_kernel_mode}"
fi
if [ -n "${overlap_worker_warmup_runs}" ]; then
  export CUFLYE_OVERLAP_WORKER_WARMUP_RUNS="${overlap_worker_warmup_runs}"
fi
if [ -n "${overlap_worker_benchmark_runs}" ]; then
  export CUFLYE_OVERLAP_WORKER_BENCHMARK_RUNS="${overlap_worker_benchmark_runs}"
fi
if [ -n "${overlap_worker_memory_budget_bytes}" ]; then
  export CUFLYE_OVERLAP_WORKER_MEMORY_BUDGET_BYTES="${overlap_worker_memory_budget_bytes}"
fi
if [ -n "${overlap_worker_validation_mode}" ]; then
  export CUFLYE_OVERLAP_WORKER_VALIDATION_MODE="${overlap_worker_validation_mode}"
fi
if [ -n "${overlap_worker_shadow_mode}" ]; then
  export CUFLYE_OVERLAP_WORKER_SHADOW_MODE="${overlap_worker_shadow_mode}"
fi
if [ -n "${overlap_worker_lifecycle_mode}" ]; then
  export CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE="${overlap_worker_lifecycle_mode}"
fi
if [ -n "${overlap_worker_session_dir}" ]; then
  export CUFLYE_OVERLAP_WORKER_SESSION_DIR="${overlap_worker_session_dir}"
fi
if [ -n "${overlap_worker_session_poll_ms}" ]; then
  export CUFLYE_OVERLAP_WORKER_SESSION_POLL_MS="${overlap_worker_session_poll_ms}"
fi
if [ -n "${overlap_worker_session_timeout_ms}" ]; then
  export CUFLYE_OVERLAP_WORKER_SESSION_TIMEOUT_MS="${overlap_worker_session_timeout_ms}"
fi
if [ -n "${overlap_graph_consumption_mode}" ]; then
  export CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE="${overlap_graph_consumption_mode}"
fi
if [ -n "${overlap_rehydration_mode}" ]; then
  export CUFLYE_OVERLAP_REHYDRATION_MODE="${overlap_rehydration_mode}"
fi
if [ -n "${overlap_rehydration_proof_fault}" ]; then
  export CUFLYE_OVERLAP_REHYDRATION_PROOF_FAULT="${overlap_rehydration_proof_fault}"
fi
if [ -n "${overlap_object_rehydration_mode}" ]; then
  export CUFLYE_OVERLAP_OBJECT_REHYDRATION_MODE="${overlap_object_rehydration_mode}"
fi
if [ -n "${overlap_object_rehydration_proof_fault}" ]; then
  export CUFLYE_OVERLAP_OBJECT_REHYDRATION_PROOF_FAULT="${overlap_object_rehydration_proof_fault}"
fi
if [ -n "${overlap_vector_substitution_mode}" ]; then
  export CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE="${overlap_vector_substitution_mode}"
fi
if [ -n "${overlap_vector_substitution_ledger_mode}" ]; then
  export CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_LEDGER_MODE="${overlap_vector_substitution_ledger_mode}"
fi
if [ -n "${overlap_gpu_first_audit_mode}" ]; then
  export CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE="${overlap_gpu_first_audit_mode}"
fi
if [ -n "${overlap_gpu_first_audit_query_ids}" ]; then
  export CUFLYE_OVERLAP_GPU_FIRST_AUDIT_QUERY_IDS="${overlap_gpu_first_audit_query_ids}"
fi
if [ -n "${overlap_vector_substitution_proof_fault}" ]; then
  export CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT="${overlap_vector_substitution_proof_fault}"
fi

metadata_tmp="${out_dir}/run_metadata.pre.json"
python3 - "$metadata_tmp" "$repo_root" "$flye_dir" "$fixture" "$reads" "$read_type" "$genome_size" "$min_overlap" "$threads" "$candidate_dump" "$overlap_dump" "$read_alignment_dump" "$read_alignment_replay_dump_dir" "$read_alignment_replay_query_id" "$read_alignment_replay_query_ids" "$read_alignment_worker_mode" "$read_alignment_worker_bin" "$read_alignment_worker_output_dir" "$read_alignment_worker_device" "$read_alignment_worker_warmup_runs" "$read_alignment_worker_benchmark_runs" "$read_alignment_worker_memory_budget_bytes" "$read_alignment_worker_validation_mode" "$read_alignment_worker_lifecycle_mode" "$read_alignment_worker_session_dir" "$read_alignment_worker_session_poll_ms" "$read_alignment_worker_session_timeout_ms" "$read_alignment_graph_consumption_mode" "$read_alignment_rehydration_mode" "$read_alignment_rehydration_proof_fault" "$read_alignment_object_rehydration_mode" "$read_alignment_object_rehydration_proof_fault" "$read_alignment_vector_substitution_mode" "$read_alignment_vector_substitution_proof_fault" "$read_alignment_predivergence_chain_mode" "$read_alignment_predivergence_chain_proof_fault" "$read_to_graph_source_pack_dir" "$read_to_graph_source_pack_query_ids" "$read_to_graph_full_query_hit_worker_mode" "$read_to_graph_full_query_hit_worker_lifecycle_mode" "$read_to_graph_full_query_hit_worker_bin" "$read_to_graph_full_query_hit_worker_output_dir" "$read_to_graph_full_query_hit_worker_session_dir" "$read_to_graph_full_query_hit_worker_session_poll_ms" "$read_to_graph_full_query_hit_worker_session_timeout_ms" "$read_to_graph_full_query_hit_worker_device" "$read_to_graph_full_query_hit_worker_kernel_mode" "$read_to_graph_full_query_hit_worker_memory_budget_bytes" "$read_to_graph_full_query_hit_rehydration_mode" "$read_to_graph_full_query_hit_rehydration_proof_fault" "$read_to_graph_full_query_hit_shadow_ledger_mode" "$read_to_graph_full_query_hit_shadow_ledger_proof_fault" "$read_to_graph_full_query_hit_graph_edge_binding_mode" "$read_to_graph_full_query_hit_graph_edge_binding_proof_fault" "$read_to_graph_full_query_hit_object_vector_smoke_mode" "$read_to_graph_full_query_hit_object_vector_smoke_proof_fault" "$read_to_graph_full_query_hit_substitution_guard_mode" "$read_to_graph_full_query_hit_substitution_guard_proof_fault" "$read_to_graph_full_query_hit_verified_substitution_mode" "$read_to_graph_full_query_hit_verified_substitution_proof_fault" "$read_to_graph_full_query_hit_selected_bypass_plan_mode" "$read_to_graph_full_query_hit_selected_bypass_plan_proof_fault" "$read_to_graph_full_query_hit_selected_bypass_dry_run_mode" "$read_to_graph_full_query_hit_selected_bypass_dry_run_proof_fault" "$read_to_graph_full_query_hit_selected_cpu_bypass_smoke_mode" "$read_to_graph_full_query_hit_selected_cpu_bypass_smoke_proof_fault" "$read_to_graph_full_query_hit_selected_graph_consumption_parity_mode" "$read_to_graph_full_query_hit_selected_graph_consumption_parity_proof_fault" "$overlap_replay_dump_dir" "$overlap_replay_query_id" "$overlap_replay_query_ids" "$overlap_replay_max_fixtures" "$overlap_replay_stop_after_dump" "$candidate_backend" "$cuda_device" "$cuda_memory_budget_bytes" "$cuda_adapter_mode" "$cuda_backend_bin" "$cuda_packed_fixture_dir" "$cuda_adapter_output_tsv" "$cuda_adapter_json" "$cuda_packed_kmer_size" "$cuda_pack_dump_dir" "$cuda_pack_query_id" "$cuda_stop_after_packed_query" "$overlap_worker_mode" "$overlap_worker_bin" "$overlap_worker_output_dir" "$overlap_worker_device" "$overlap_worker_kernel_mode" "$overlap_worker_warmup_runs" "$overlap_worker_benchmark_runs" "$overlap_worker_memory_budget_bytes" "$overlap_worker_validation_mode" "$overlap_worker_shadow_mode" "$overlap_worker_lifecycle_mode" "$overlap_worker_session_dir" "$overlap_worker_session_poll_ms" "$overlap_worker_session_timeout_ms" "$overlap_graph_consumption_mode" "$overlap_rehydration_mode" "$overlap_rehydration_proof_fault" "$overlap_object_rehydration_mode" "$overlap_object_rehydration_proof_fault" "$overlap_vector_substitution_mode" "$overlap_vector_substitution_ledger_mode" "$overlap_gpu_first_audit_mode" "$overlap_gpu_first_audit_query_ids" "$overlap_vector_substitution_proof_fault" "${cmd[@]}" <<'PY'
import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone

metadata_path, repo_root, flye_dir, fixture, reads, read_type, genome_size, min_overlap, threads, candidate_dump, overlap_dump, read_alignment_dump, read_alignment_replay_dump_dir, read_alignment_replay_query_id, read_alignment_replay_query_ids, read_alignment_worker_mode, read_alignment_worker_bin, read_alignment_worker_output_dir, read_alignment_worker_device, read_alignment_worker_warmup_runs, read_alignment_worker_benchmark_runs, read_alignment_worker_memory_budget_bytes, read_alignment_worker_validation_mode, read_alignment_worker_lifecycle_mode, read_alignment_worker_session_dir, read_alignment_worker_session_poll_ms, read_alignment_worker_session_timeout_ms, read_alignment_graph_consumption_mode, read_alignment_rehydration_mode, read_alignment_rehydration_proof_fault, read_alignment_object_rehydration_mode, read_alignment_object_rehydration_proof_fault, read_alignment_vector_substitution_mode, read_alignment_vector_substitution_proof_fault, read_alignment_predivergence_chain_mode, read_alignment_predivergence_chain_proof_fault, read_to_graph_source_pack_dir, read_to_graph_source_pack_query_ids, read_to_graph_full_query_hit_worker_mode, read_to_graph_full_query_hit_worker_lifecycle_mode, read_to_graph_full_query_hit_worker_bin, read_to_graph_full_query_hit_worker_output_dir, read_to_graph_full_query_hit_worker_session_dir, read_to_graph_full_query_hit_worker_session_poll_ms, read_to_graph_full_query_hit_worker_session_timeout_ms, read_to_graph_full_query_hit_worker_device, read_to_graph_full_query_hit_worker_kernel_mode, read_to_graph_full_query_hit_worker_memory_budget_bytes, read_to_graph_full_query_hit_rehydration_mode, read_to_graph_full_query_hit_rehydration_proof_fault, read_to_graph_full_query_hit_shadow_ledger_mode, read_to_graph_full_query_hit_shadow_ledger_proof_fault, read_to_graph_full_query_hit_graph_edge_binding_mode, read_to_graph_full_query_hit_graph_edge_binding_proof_fault, read_to_graph_full_query_hit_object_vector_smoke_mode, read_to_graph_full_query_hit_object_vector_smoke_proof_fault, read_to_graph_full_query_hit_substitution_guard_mode, read_to_graph_full_query_hit_substitution_guard_proof_fault, read_to_graph_full_query_hit_verified_substitution_mode, read_to_graph_full_query_hit_verified_substitution_proof_fault, read_to_graph_full_query_hit_selected_bypass_plan_mode, read_to_graph_full_query_hit_selected_bypass_plan_proof_fault, read_to_graph_full_query_hit_selected_bypass_dry_run_mode, read_to_graph_full_query_hit_selected_bypass_dry_run_proof_fault, read_to_graph_full_query_hit_selected_cpu_bypass_smoke_mode, read_to_graph_full_query_hit_selected_cpu_bypass_smoke_proof_fault, read_to_graph_full_query_hit_selected_graph_consumption_parity_mode, read_to_graph_full_query_hit_selected_graph_consumption_parity_proof_fault, overlap_replay_dump_dir, overlap_replay_query_id, overlap_replay_query_ids, overlap_replay_max_fixtures, overlap_replay_stop_after_dump, candidate_backend, cuda_device, cuda_memory_budget_bytes, cuda_adapter_mode, cuda_backend_bin, cuda_packed_fixture_dir, cuda_adapter_output_tsv, cuda_adapter_json, cuda_packed_kmer_size, cuda_pack_dump_dir, cuda_pack_query_id, cuda_stop_after_packed_query, overlap_worker_mode, overlap_worker_bin, overlap_worker_output_dir, overlap_worker_device, overlap_worker_kernel_mode, overlap_worker_warmup_runs, overlap_worker_benchmark_runs, overlap_worker_memory_budget_bytes, overlap_worker_validation_mode, overlap_worker_shadow_mode, overlap_worker_lifecycle_mode, overlap_worker_session_dir, overlap_worker_session_poll_ms, overlap_worker_session_timeout_ms, overlap_graph_consumption_mode, overlap_rehydration_mode, overlap_rehydration_proof_fault, overlap_object_rehydration_mode, overlap_object_rehydration_proof_fault, overlap_vector_substitution_mode, overlap_vector_substitution_ledger_mode, overlap_gpu_first_audit_mode, overlap_gpu_first_audit_query_ids, overlap_vector_substitution_proof_fault, *cmd = sys.argv[1:]

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
if candidate_dump:
    payload["candidate_dump"] = os.path.abspath(candidate_dump)
if overlap_dump:
    payload["overlap_dump"] = os.path.abspath(overlap_dump)
if read_alignment_dump:
    payload["read_alignment_dump"] = os.path.abspath(read_alignment_dump)
read_alignment_input_boundary_dump = os.environ.get("CUFLYE_READ_ALIGNMENT_INPUT_BOUNDARY_DUMP", "")
if read_alignment_input_boundary_dump:
    payload["read_alignment_input_boundary_dump"] = os.path.abspath(read_alignment_input_boundary_dump)
if read_alignment_replay_dump_dir:
    payload["read_alignment_replay_dump_dir"] = os.path.abspath(read_alignment_replay_dump_dir)
if read_alignment_replay_query_id:
    payload["read_alignment_replay_query_id"] = read_alignment_replay_query_id
if read_alignment_replay_query_ids:
    payload["read_alignment_replay_query_ids"] = read_alignment_replay_query_ids
if read_alignment_worker_mode:
    payload["read_alignment_worker_mode"] = read_alignment_worker_mode
if read_alignment_worker_bin:
    payload["read_alignment_worker_bin"] = os.path.abspath(read_alignment_worker_bin)
if read_alignment_worker_output_dir:
    payload["read_alignment_worker_output_dir"] = os.path.abspath(read_alignment_worker_output_dir)
if read_alignment_worker_device:
    payload["read_alignment_worker_device"] = read_alignment_worker_device
if read_alignment_worker_warmup_runs:
    payload["read_alignment_worker_warmup_runs"] = read_alignment_worker_warmup_runs
if read_alignment_worker_benchmark_runs:
    payload["read_alignment_worker_benchmark_runs"] = read_alignment_worker_benchmark_runs
if read_alignment_worker_memory_budget_bytes:
    payload["read_alignment_worker_memory_budget_bytes"] = read_alignment_worker_memory_budget_bytes
if read_alignment_worker_validation_mode:
    payload["read_alignment_worker_validation_mode"] = read_alignment_worker_validation_mode
if read_alignment_worker_lifecycle_mode:
    payload["read_alignment_worker_lifecycle_mode"] = read_alignment_worker_lifecycle_mode
if read_alignment_worker_session_dir:
    payload["read_alignment_worker_session_dir"] = os.path.abspath(read_alignment_worker_session_dir)
if read_alignment_worker_session_poll_ms:
    payload["read_alignment_worker_session_poll_ms"] = read_alignment_worker_session_poll_ms
if read_alignment_worker_session_timeout_ms:
    payload["read_alignment_worker_session_timeout_ms"] = read_alignment_worker_session_timeout_ms
if read_alignment_graph_consumption_mode:
    payload["read_alignment_graph_consumption_mode"] = read_alignment_graph_consumption_mode
if read_alignment_rehydration_mode:
    payload["read_alignment_rehydration_mode"] = read_alignment_rehydration_mode
if read_alignment_rehydration_proof_fault:
    payload["read_alignment_rehydration_proof_fault"] = read_alignment_rehydration_proof_fault
if read_alignment_object_rehydration_mode:
    payload["read_alignment_object_rehydration_mode"] = read_alignment_object_rehydration_mode
if read_alignment_object_rehydration_proof_fault:
    payload["read_alignment_object_rehydration_proof_fault"] = read_alignment_object_rehydration_proof_fault
if read_alignment_vector_substitution_mode:
    payload["read_alignment_vector_substitution_mode"] = read_alignment_vector_substitution_mode
if read_alignment_vector_substitution_proof_fault:
    payload["read_alignment_vector_substitution_proof_fault"] = read_alignment_vector_substitution_proof_fault
if read_alignment_predivergence_chain_mode:
    payload["read_alignment_predivergence_chain_mode"] = read_alignment_predivergence_chain_mode
if read_alignment_predivergence_chain_proof_fault:
    payload["read_alignment_predivergence_chain_proof_fault"] = read_alignment_predivergence_chain_proof_fault
if read_to_graph_source_pack_dir:
    payload["read_to_graph_source_pack_dir"] = os.path.abspath(read_to_graph_source_pack_dir)
if read_to_graph_source_pack_query_ids:
    payload["read_to_graph_source_pack_query_ids"] = read_to_graph_source_pack_query_ids
if read_to_graph_full_query_hit_worker_mode:
    payload["read_to_graph_full_query_hit_worker_mode"] = read_to_graph_full_query_hit_worker_mode
if read_to_graph_full_query_hit_worker_lifecycle_mode:
    payload["read_to_graph_full_query_hit_worker_lifecycle_mode"] = read_to_graph_full_query_hit_worker_lifecycle_mode
if read_to_graph_full_query_hit_worker_bin:
    payload["read_to_graph_full_query_hit_worker_bin"] = os.path.abspath(read_to_graph_full_query_hit_worker_bin)
if read_to_graph_full_query_hit_worker_output_dir:
    payload["read_to_graph_full_query_hit_worker_output_dir"] = os.path.abspath(read_to_graph_full_query_hit_worker_output_dir)
if read_to_graph_full_query_hit_worker_session_dir:
    payload["read_to_graph_full_query_hit_worker_session_dir"] = os.path.abspath(read_to_graph_full_query_hit_worker_session_dir)
if read_to_graph_full_query_hit_worker_session_poll_ms:
    payload["read_to_graph_full_query_hit_worker_session_poll_ms"] = read_to_graph_full_query_hit_worker_session_poll_ms
if read_to_graph_full_query_hit_worker_session_timeout_ms:
    payload["read_to_graph_full_query_hit_worker_session_timeout_ms"] = read_to_graph_full_query_hit_worker_session_timeout_ms
if read_to_graph_full_query_hit_worker_device:
    payload["read_to_graph_full_query_hit_worker_device"] = read_to_graph_full_query_hit_worker_device
if read_to_graph_full_query_hit_worker_kernel_mode:
    payload["read_to_graph_full_query_hit_worker_kernel_mode"] = read_to_graph_full_query_hit_worker_kernel_mode
if read_to_graph_full_query_hit_worker_memory_budget_bytes:
    payload["read_to_graph_full_query_hit_worker_memory_budget_bytes"] = read_to_graph_full_query_hit_worker_memory_budget_bytes
if read_to_graph_full_query_hit_rehydration_mode:
    payload["read_to_graph_full_query_hit_rehydration_mode"] = read_to_graph_full_query_hit_rehydration_mode
if read_to_graph_full_query_hit_rehydration_proof_fault:
    payload["read_to_graph_full_query_hit_rehydration_proof_fault"] = read_to_graph_full_query_hit_rehydration_proof_fault
if read_to_graph_full_query_hit_shadow_ledger_mode:
    payload["read_to_graph_full_query_hit_shadow_ledger_mode"] = read_to_graph_full_query_hit_shadow_ledger_mode
if read_to_graph_full_query_hit_shadow_ledger_proof_fault:
    payload["read_to_graph_full_query_hit_shadow_ledger_proof_fault"] = read_to_graph_full_query_hit_shadow_ledger_proof_fault
if read_to_graph_full_query_hit_graph_edge_binding_mode:
    payload["read_to_graph_full_query_hit_graph_edge_binding_mode"] = read_to_graph_full_query_hit_graph_edge_binding_mode
if read_to_graph_full_query_hit_graph_edge_binding_proof_fault:
    payload["read_to_graph_full_query_hit_graph_edge_binding_proof_fault"] = read_to_graph_full_query_hit_graph_edge_binding_proof_fault
if read_to_graph_full_query_hit_object_vector_smoke_mode:
    payload["read_to_graph_full_query_hit_object_vector_smoke_mode"] = read_to_graph_full_query_hit_object_vector_smoke_mode
if read_to_graph_full_query_hit_object_vector_smoke_proof_fault:
    payload["read_to_graph_full_query_hit_object_vector_smoke_proof_fault"] = read_to_graph_full_query_hit_object_vector_smoke_proof_fault
if read_to_graph_full_query_hit_substitution_guard_mode:
    payload["read_to_graph_full_query_hit_substitution_guard_mode"] = read_to_graph_full_query_hit_substitution_guard_mode
if read_to_graph_full_query_hit_substitution_guard_proof_fault:
    payload["read_to_graph_full_query_hit_substitution_guard_proof_fault"] = read_to_graph_full_query_hit_substitution_guard_proof_fault
if read_to_graph_full_query_hit_verified_substitution_mode:
    payload["read_to_graph_full_query_hit_verified_substitution_mode"] = read_to_graph_full_query_hit_verified_substitution_mode
if read_to_graph_full_query_hit_verified_substitution_proof_fault:
    payload["read_to_graph_full_query_hit_verified_substitution_proof_fault"] = read_to_graph_full_query_hit_verified_substitution_proof_fault
if read_to_graph_full_query_hit_selected_bypass_plan_mode:
    payload["read_to_graph_full_query_hit_selected_bypass_plan_mode"] = read_to_graph_full_query_hit_selected_bypass_plan_mode
if read_to_graph_full_query_hit_selected_bypass_plan_proof_fault:
    payload["read_to_graph_full_query_hit_selected_bypass_plan_proof_fault"] = read_to_graph_full_query_hit_selected_bypass_plan_proof_fault
if read_to_graph_full_query_hit_selected_bypass_dry_run_mode:
    payload["read_to_graph_full_query_hit_selected_bypass_dry_run_mode"] = read_to_graph_full_query_hit_selected_bypass_dry_run_mode
if read_to_graph_full_query_hit_selected_bypass_dry_run_proof_fault:
    payload["read_to_graph_full_query_hit_selected_bypass_dry_run_proof_fault"] = read_to_graph_full_query_hit_selected_bypass_dry_run_proof_fault
if read_to_graph_full_query_hit_selected_cpu_bypass_smoke_mode:
    payload["read_to_graph_full_query_hit_selected_cpu_bypass_smoke_mode"] = read_to_graph_full_query_hit_selected_cpu_bypass_smoke_mode
if read_to_graph_full_query_hit_selected_cpu_bypass_smoke_proof_fault:
    payload["read_to_graph_full_query_hit_selected_cpu_bypass_smoke_proof_fault"] = read_to_graph_full_query_hit_selected_cpu_bypass_smoke_proof_fault
if read_to_graph_full_query_hit_selected_graph_consumption_parity_mode:
    payload["read_to_graph_full_query_hit_selected_graph_consumption_parity_mode"] = read_to_graph_full_query_hit_selected_graph_consumption_parity_mode
if read_to_graph_full_query_hit_selected_graph_consumption_parity_proof_fault:
    payload["read_to_graph_full_query_hit_selected_graph_consumption_parity_proof_fault"] = read_to_graph_full_query_hit_selected_graph_consumption_parity_proof_fault
read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_mode = os.environ.get(
    "CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_MODE", "")
read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_proof_fault = os.environ.get(
    "CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_PROOF_FAULT", "")
if read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_mode:
    payload["read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_mode"] = read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_mode
if read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_proof_fault:
    payload["read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_proof_fault"] = read_to_graph_full_query_hit_selected_graph_consumption_mutation_canary_proof_fault
read_to_graph_full_query_hit_selected_cpu_skip_canary_mode = os.environ.get(
    "CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_MODE", "")
read_to_graph_full_query_hit_selected_cpu_skip_canary_proof_fault = os.environ.get(
    "CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_PROOF_FAULT", "")
if read_to_graph_full_query_hit_selected_cpu_skip_canary_mode:
    payload["read_to_graph_full_query_hit_selected_cpu_skip_canary_mode"] = read_to_graph_full_query_hit_selected_cpu_skip_canary_mode
if read_to_graph_full_query_hit_selected_cpu_skip_canary_proof_fault:
    payload["read_to_graph_full_query_hit_selected_cpu_skip_canary_proof_fault"] = read_to_graph_full_query_hit_selected_cpu_skip_canary_proof_fault
if overlap_replay_dump_dir:
    payload["overlap_replay_dump_dir"] = os.path.abspath(overlap_replay_dump_dir)
if overlap_replay_query_id:
    payload["overlap_replay_query_id"] = overlap_replay_query_id
if overlap_replay_query_ids:
    payload["overlap_replay_query_ids"] = overlap_replay_query_ids
if overlap_replay_max_fixtures:
    payload["overlap_replay_max_fixtures"] = overlap_replay_max_fixtures
if overlap_replay_stop_after_dump:
    payload["overlap_replay_stop_after_dump"] = overlap_replay_stop_after_dump
if candidate_backend:
    payload["candidate_backend"] = candidate_backend
if cuda_device:
    payload["cuda_device"] = cuda_device
if cuda_memory_budget_bytes:
    payload["cuda_memory_budget_bytes"] = cuda_memory_budget_bytes
if cuda_adapter_mode:
    payload["cuda_adapter_mode"] = cuda_adapter_mode
if cuda_backend_bin:
    payload["cuda_backend_bin"] = os.path.abspath(cuda_backend_bin)
if cuda_packed_fixture_dir:
    payload["cuda_packed_fixture_dir"] = os.path.abspath(cuda_packed_fixture_dir)
if cuda_adapter_output_tsv:
    payload["cuda_adapter_output_tsv"] = os.path.abspath(cuda_adapter_output_tsv)
if cuda_adapter_json:
    payload["cuda_adapter_json"] = os.path.abspath(cuda_adapter_json)
if cuda_packed_kmer_size:
    payload["cuda_packed_kmer_size"] = cuda_packed_kmer_size
if cuda_pack_dump_dir:
    payload["cuda_pack_dump_dir"] = os.path.abspath(cuda_pack_dump_dir)
if cuda_pack_query_id:
    payload["cuda_pack_query_id"] = cuda_pack_query_id
if cuda_stop_after_packed_query:
    payload["cuda_stop_after_packed_query"] = cuda_stop_after_packed_query
if overlap_worker_mode:
    payload["overlap_worker_mode"] = overlap_worker_mode
if overlap_worker_bin:
    payload["overlap_worker_bin"] = os.path.abspath(overlap_worker_bin)
if overlap_worker_output_dir:
    payload["overlap_worker_output_dir"] = os.path.abspath(overlap_worker_output_dir)
if overlap_worker_device:
    payload["overlap_worker_device"] = overlap_worker_device
if overlap_worker_kernel_mode:
    payload["overlap_worker_kernel_mode"] = overlap_worker_kernel_mode
if overlap_worker_warmup_runs:
    payload["overlap_worker_warmup_runs"] = overlap_worker_warmup_runs
if overlap_worker_benchmark_runs:
    payload["overlap_worker_benchmark_runs"] = overlap_worker_benchmark_runs
if overlap_worker_memory_budget_bytes:
    payload["overlap_worker_memory_budget_bytes"] = overlap_worker_memory_budget_bytes
if overlap_worker_validation_mode:
    payload["overlap_worker_validation_mode"] = overlap_worker_validation_mode
if overlap_worker_shadow_mode:
    payload["overlap_worker_shadow_mode"] = overlap_worker_shadow_mode
if overlap_worker_lifecycle_mode:
    payload["overlap_worker_lifecycle_mode"] = overlap_worker_lifecycle_mode
if overlap_worker_session_dir:
    payload["overlap_worker_session_dir"] = os.path.abspath(overlap_worker_session_dir)
if overlap_worker_session_poll_ms:
    payload["overlap_worker_session_poll_ms"] = overlap_worker_session_poll_ms
if overlap_worker_session_timeout_ms:
    payload["overlap_worker_session_timeout_ms"] = overlap_worker_session_timeout_ms
if overlap_graph_consumption_mode:
    payload["overlap_graph_consumption_mode"] = overlap_graph_consumption_mode
if overlap_rehydration_mode:
    payload["overlap_rehydration_mode"] = overlap_rehydration_mode
if overlap_rehydration_proof_fault:
    payload["overlap_rehydration_proof_fault"] = overlap_rehydration_proof_fault
if overlap_object_rehydration_mode:
    payload["overlap_object_rehydration_mode"] = overlap_object_rehydration_mode
if overlap_object_rehydration_proof_fault:
    payload["overlap_object_rehydration_proof_fault"] = overlap_object_rehydration_proof_fault
if overlap_vector_substitution_mode:
    payload["overlap_vector_substitution_mode"] = overlap_vector_substitution_mode
if overlap_vector_substitution_ledger_mode:
    payload["overlap_vector_substitution_ledger_mode"] = overlap_vector_substitution_ledger_mode
if overlap_gpu_first_audit_mode:
    payload["overlap_gpu_first_audit_mode"] = overlap_gpu_first_audit_mode
if overlap_gpu_first_audit_query_ids:
    payload["overlap_gpu_first_audit_query_ids"] = overlap_gpu_first_audit_query_ids
if overlap_vector_substitution_proof_fault:
    payload["overlap_vector_substitution_proof_fault"] = overlap_vector_substitution_proof_fault

with open(metadata_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

start_epoch="$(date +%s)"
time_log="${out_dir}/time.log"
run_status=0

set +e
if /usr/bin/time -v true >/dev/null 2>&1; then
  /usr/bin/time -v "${cmd[@]}" > "${out_dir}/stdout.log" 2> >(tee "${out_dir}/stderr.log" > "${time_log}")
  run_status=$?
elif /usr/bin/time -l true >/dev/null 2>&1; then
  /usr/bin/time -l "${cmd[@]}" > "${out_dir}/stdout.log" 2> >(tee "${out_dir}/stderr.log" > "${time_log}")
  run_status=$?
else
  "${cmd[@]}" > "${out_dir}/stdout.log" 2> "${out_dir}/stderr.log"
  run_status=$?
fi
set -e

if [ "${run_status}" -ne 0 ] && [ "${expect_failure}" != "1" ]; then
  exit "${run_status}"
fi

end_epoch="$(date +%s)"
elapsed_seconds="$((end_epoch - start_epoch))"

python3 - "$metadata_tmp" "${out_dir}/run_metadata.json" "$elapsed_seconds" "$run_status" "$expect_failure" <<'PY'
import json
import sys
from datetime import datetime, timezone

src, dst, elapsed, run_status, expect_failure = sys.argv[1:]
with open(src, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
payload["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
payload["elapsed_seconds"] = int(elapsed)
payload["exit_status"] = int(run_status)
payload["expected_failure"] = expect_failure == "1"
with open(dst, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
rm -f "${metadata_tmp}"

"${repo_root}/tools/canonicalize_flye_artifacts.py" --manifest "${out_dir}" \
  > "${out_dir}/artifact_hashes.json"

if [ -n "${candidate_dump}" ] || [ -n "${overlap_dump}" ] || [ -n "${read_alignment_dump}" ] || [ -n "${read_alignment_replay_dump_dir}" ] || [ -n "${overlap_replay_dump_dir}" ] || [ -n "${candidate_backend}" ]; then
  python3 - "$out_dir/run_metadata.json" "$candidate_dump" "$overlap_dump" "$read_alignment_dump" "$read_alignment_replay_dump_dir" "$read_alignment_replay_query_id" "$read_alignment_replay_query_ids" "$overlap_replay_dump_dir" "$candidate_backend" <<'PY'
import json
import os
import sys

metadata_path, candidate_dump, overlap_dump, read_alignment_dump, read_alignment_replay_dump_dir, read_alignment_replay_query_id, read_alignment_replay_query_ids, overlap_replay_dump_dir, candidate_backend = sys.argv[1:]
with open(metadata_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
if candidate_dump:
    payload["candidate_dump"] = os.path.abspath(candidate_dump)
if overlap_dump:
    payload["overlap_dump"] = os.path.abspath(overlap_dump)
if read_alignment_dump:
    payload["read_alignment_dump"] = os.path.abspath(read_alignment_dump)
if read_alignment_replay_dump_dir:
    payload["read_alignment_replay_dump_dir"] = os.path.abspath(read_alignment_replay_dump_dir)
if read_alignment_replay_query_id:
    payload["read_alignment_replay_query_id"] = read_alignment_replay_query_id
if read_alignment_replay_query_ids:
    payload["read_alignment_replay_query_ids"] = read_alignment_replay_query_ids
if overlap_replay_dump_dir:
    payload["overlap_replay_dump_dir"] = os.path.abspath(overlap_replay_dump_dir)
if candidate_backend:
    payload["candidate_backend"] = candidate_backend
with open(metadata_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
fi

echo "Flye fixture run complete: ${out_dir}"
echo "Metadata: ${out_dir}/run_metadata.json"
echo "Artifact hashes: ${out_dir}/artifact_hashes.json"

if [ "${run_status}" -ne 0 ] && [ "${expect_failure}" != "1" ]; then
  exit "${run_status}"
fi
