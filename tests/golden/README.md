# Golden Manifests

This directory stores small, reviewable golden manifests for oracle fixtures.

Do not commit full Flye run directories, generated assemblies, BAM/SAM files, or
profiler dumps here. Store compact manifests, canonical hashes, and summary
proof only.

Accepted fixtures:

- `toy-hifi`: upstream Flye E. coli 500 kb HiFi toy fixture from
  `upstream-flye/flye/tests/data/ecoli_500kb_reads_hifi.fastq.gz`.
  - Manifest: `toy-hifi-dgx-aarch64.json`
  - Candidate oracle manifest: `toy-hifi-candidate-dgx-aarch64.json`
  - Candidate backend seam manifest: `toy-hifi-backend-dgx-aarch64.json`
  - Candidate ABI manifest: `toy-hifi-candidate-abi-dgx-aarch64.json`
  - CUDA backend stub manifest: `toy-hifi-cuda-stub-dgx-aarch64.json`

ABI proof manifests use the same fixture and must reference compact validator
summaries, not full candidate TSV files.

CUDA runtime proof:

- Runtime probe manifest: `cuda-runtime-probe-dgx-aarch64.json`

CUDA candidate smoke proof:

- Candidate smoke manifest: `cuda-candidate-smoke-dgx-aarch64.json`

CUDA k-mer join smoke proof:

- K-mer join smoke manifest: `cuda-kmer-join-smoke-dgx-aarch64.json`

CUDA k-mer encode smoke proof:

- K-mer encode smoke manifest: `cuda-kmer-encode-smoke-dgx-aarch64.json`

CUDA read-window smoke proof:

- Read-window smoke manifest: `cuda-read-window-smoke-dgx-aarch64.json`

CUDA candidate-core benchmark proof:

- Candidate-core benchmark manifest: `cuda-candidate-core-bench-dgx-aarch64.json`

CUDA RAII resource-layer proof:

- CUDA RAII resource-layer manifest: `cuda-raii-resource-layer-dgx-aarch64.json`

M2 real-pack CUDA consumer proof:

- Real-pack CUDA consumer manifest:
  `cuflye-m2c-real-pack-cuda-consumer-dgx-aarch64.json`

M3 long-lived CUDA worker proof:

- Long-lived worker manifest:
  `cuflye-m3b-long-lived-cuda-worker-dgx-aarch64.json`
- Device prefix compaction manifest:
  `cuflye-m3c-device-prefix-compaction-dgx-aarch64.json`
- Worker device-buffer arena manifest:
  `cuflye-m3d-worker-device-buffer-arena-dgx-aarch64.json`
- Sampled pack batch planner manifest:
  `cuflye-m3e-sampled-pack-batch-planner-dgx-aarch64.json`

M4 overlap-range oracle proof:

- Overlap-range CPU oracle manifest:
  `cuflye-m4a-overlap-range-oracle-dgx-aarch64.json`
- Overlap-chain replay manifest:
  `cuflye-m4b-overlap-chain-replay-dgx-aarch64.json`
- CUDA overlap-chain DP prototype manifest:
  `cuflye-m4c-cuda-overlap-chain-dp-dgx-aarch64.json`
- Overlap-chain hotpath benchmark manifest:
  `cuflye-m4d-overlap-chain-hotpath-benchmark-dgx-aarch64.json`
- Overlap-chain parallel-reduction manifest:
  `cuflye-m4e-overlap-chain-parallel-reduction-dgx-aarch64.json`
- Overlap-chain batched-fixtures manifest:
  `cuflye-m4f-overlap-chain-batched-fixtures-dgx-aarch64.json`
- Batched overlap worker manifest:
  `cuflye-m4g-batched-overlap-worker-dgx-aarch64.json`
- Packed multi-query overlap kernel manifest:
  `cuflye-m4h-packed-multi-query-overlap-kernel-dgx-aarch64.json`
- Packed overlap worker protocol manifest:
  `cuflye-m4i-packed-overlap-worker-protocol-dgx-aarch64.json`
- Flye overlap worker seam manifest:
  `cuflye-m4j-flye-overlap-worker-seam-dgx-aarch64.json`
- Flye overlap worker batch seam manifest:
  `cuflye-m4k-flye-overlap-worker-batch-seam-dgx-aarch64.json`
- Overlap worker validated consumption gate manifest:
  `cuflye-m4l-overlap-worker-validated-consumption-gate-dgx-aarch64.json`
- Overlap worker shadow consumption manifest:
  `cuflye-m4m-overlap-worker-shadow-consumption-dgx-aarch64.json`
- Heterogeneous shadow batch matrix manifest:
  `cuflye-m4n-heterogeneous-shadow-batch-matrix-dgx-aarch64.json`
- Guarded overlap graph-consumption dry-run manifest:
  `cuflye-m4o-guarded-overlap-graph-consumption-dgx-aarch64.json`
- Overlap rehydration dry-run manifest:
  `cuflye-m4p-overlap-rehydration-dry-run-dgx-aarch64.json`
- OverlapRange object rehydration dry-run manifest:
  `cuflye-m4q-overlap-range-object-rehydration-dry-run-dgx-aarch64.json`
- Verified overlap-vector substitution smoke manifest:
  `cuflye-m4r-verified-overlap-vector-substitution-smoke-dgx-aarch64.json`
- Substitution session ledger manifest:
  `cuflye-m4s-substitution-session-ledger-dgx-aarch64.json`
- Substitution session timing attribution manifest:
  `cuflye-m4t-substitution-session-timing-attribution-dgx-aarch64.json`
- Substitution worker overhead-reduction manifest:
  `cuflye-m4u-substitution-worker-overhead-reduction-dgx-aarch64.json`
- Persistent overlap worker lifecycle manifest:
  `cuflye-m4v-persistent-overlap-worker-lifecycle-dgx-aarch64.json`
- True persistent overlap worker session manifest:
  `cuflye-m4w-true-persistent-overlap-worker-session-dgx-aarch64.json`
- GPU-first overlap substitution perf-gate manifest:
  `cuflye-m4x-gpu-first-overlap-substitution-perf-gate-dgx-aarch64.json`
- Sparse GPU-first selection and audit sampling manifest:
  `cuflye-m4y-sparse-gpu-first-selection-audit-sampling-dgx-aarch64.json`
- Validation-safe GPU-first selection planner manifest:
  `cuflye-m4z-validation-safe-selection-planner-dgx-aarch64.json`

M5 read-to-graph alignment proof:

- Read alignment oracle manifest:
  `cuflye-m5a-read-alignment-oracle-dgx-aarch64.json`
- Read alignment replay fixture manifest:
  `cuflye-m5b-read-alignment-replay-fixture-dgx-aarch64.json`
- CUDA read alignment chain benchmark manifest:
  `cuflye-m5c-cuda-read-alignment-chain-benchmark-dgx-aarch64.json`
- Read alignment replicated-batch benchmark manifest:
  `cuflye-m5d-read-alignment-replicated-batch-dgx-aarch64.json`
- Real multi-read replay batch manifest:
  `cuflye-m5e-real-multiread-replay-batch-dgx-aarch64.json`
- Heterogeneous read alignment batch manifest:
  `cuflye-m5f-heterogeneous-read-alignment-batch-dgx-aarch64.json`
- Persistent read alignment arena manifest:
  `cuflye-m5g-persistent-read-alignment-arena-dgx-aarch64.json`
- Larger read alignment fixture harvest manifest:
  `cuflye-m5h-larger-read-alignment-fixture-harvest-dgx-aarch64.json`
- Persistent read alignment bulk-output manifest:
  `cuflye-m5i-persistent-bulk-output-copy-dgx-aarch64.json`
- Read alignment graph dry-run seam manifest:
  `cuflye-m5j-read-alignment-graph-dry-run-seam-dgx-aarch64.json`
- Read alignment typed rehydration dry-run manifest:
  `cuflye-m5k-read-alignment-typed-rehydration-dry-run-dgx-aarch64.json`
- Read alignment GraphAlignment object-vector dry-run manifest:
  `cuflye-m5l-read-alignment-graph-alignment-object-vector-dry-run-dgx-aarch64.json`
- Read alignment vector substitution smoke manifest:
  `cuflye-m5m-read-alignment-vector-substitution-smoke-dgx-aarch64.json`
- Read alignment pre-divergence chain output manifest:
  `cuflye-m5n-read-alignment-pre-divergence-chain-output-dgx-aarch64.json`
- Read alignment pre-divergence Flye dry-run manifest:
  `cuflye-m5o-read-alignment-pre-divergence-flye-dry-run-dgx-aarch64.json`
- Read alignment pre-divergence batch dry-run manifest:
  `cuflye-m5p-read-alignment-pre-divergence-batch-dry-run-dgx-aarch64.json`
- Read alignment pre-divergence batch crossover manifest:
  `cuflye-m5q-read-alignment-pre-divergence-batch-crossover-dgx-aarch64.json`
- Read alignment pre-divergence persistent session manifest:
  `cuflye-m5r-read-alignment-pre-divergence-persistent-session-dgx-aarch64.json`
- Read alignment session output overhead-reduction manifest:
  `cuflye-m5s-read-alignment-session-output-overhead-reduction-dgx-aarch64.json`
- Read alignment compact binary payload manifest:
  `cuflye-m5t-read-alignment-compact-binary-payload-dgx-aarch64.json`
- Read alignment compact binary Flye rehydration manifest:
  `cuflye-m5u-read-alignment-compact-binary-flye-rehydration-dgx-aarch64.json`
- Read alignment compact binary vector substitution smoke manifest:
  `cuflye-m5v-read-alignment-compact-binary-vector-substitution-smoke-dgx-aarch64.json`
- Read alignment compact binary substitution scale-up manifest:
  `cuflye-m5w-read-alignment-compact-binary-substitution-scaleup-dgx-aarch64.json`
- Read alignment selected CPU-bypass manifest:
  `cuflye-m5x-read-alignment-selected-cpu-bypass-dgx-aarch64.json`
- Read alignment post-bypass attribution manifest:
  `cuflye-m5y-read-alignment-post-bypass-attribution-dgx-aarch64.json`

M6 read-to-graph input-boundary proof:

- Read-to-graph overlap input-boundary oracle manifest:
  `cuflye-m6a-read-to-graph-overlap-input-boundary-dgx-aarch64.json`
- Read-to-graph input-boundary replay pack manifest:
  `cuflye-m6b-read-to-graph-input-boundary-replay-pack-dgx-aarch64.json`
- CUDA raw-overlap filter/sort replay manifest:
  `cuflye-m6c-cuda-raw-overlap-filter-sort-replay-dgx-aarch64.json`
- Read-to-graph minimizer source-pack manifest:
  `cuflye-m6d-read-to-graph-minimizer-source-pack-dgx-aarch64.json`
- Minimizer source replay gap-closure manifest:
  `cuflye-m6e-minimizer-source-replay-gap-closure-dgx-aarch64.json`
- Full query-hit source-pack manifest:
  `cuflye-m6f-full-query-hit-source-pack-dgx-aarch64.json`
- Query-hit replay tie-closure manifest:
  `cuflye-m6g-query-hit-replay-tie-closure-dgx-aarch64.json`
- CUDA full query-hit replay consumer manifest:
  `cuflye-m6h-cuda-full-query-hit-replay-consumer-dgx-aarch64.json`
- Parallel full query-hit replay benchmark manifest:
  `cuflye-m6i-parallel-full-query-hit-replay-benchmark-dgx-aarch64.json`
- Persistent full query-hit replay session manifest:
  `cuflye-m6j-persistent-full-query-hit-replay-session-dgx-aarch64.json`
- Full query-hit worker seam manifest:
  `cuflye-m6k-full-query-hit-worker-seam-dgx-aarch64.json`
- Flye full query-hit worker dry-run seam manifest:
  `cuflye-m6l-flye-full-query-hit-worker-dry-run-seam-dgx-aarch64.json`
- Persistent Flye full query-hit worker lifecycle manifest:
  `cuflye-m6m-persistent-flye-full-query-hit-worker-lifecycle-dgx-aarch64.json`
- File-backed full query-hit worker session manifest:
  `cuflye-m6n-file-backed-full-query-hit-worker-session-dgx-aarch64.json`
- Session-scale full query-hit performance gate manifest:
  `cuflye-m6o-session-scale-performance-gate-dgx-aarch64.json`
- Full query-hit guarded consumption dry-run manifest:
  `cuflye-m6p-full-query-hit-guarded-consumption-dry-run-dgx-aarch64.json`
- Full query-hit shadow consumption ledger manifest:
  `cuflye-m6q-full-query-hit-shadow-consumption-ledger-dgx-aarch64.json`
- Full query-hit non-key field propagation manifest:
  `cuflye-m6r-full-query-hit-non-key-field-propagation-dgx-aarch64.json`
- Full query-hit graph-edge binding dry-run manifest:
  `cuflye-m6s-full-query-hit-graph-edge-binding-dry-run-dgx-aarch64.json`
- Full query-hit object-vector smoke manifest:
  `cuflye-m6t-full-query-hit-object-vector-smoke-dgx-aarch64.json`
- Full query-hit substitution-guard manifest:
  `cuflye-m6u-full-query-hit-substitution-guard-dgx-aarch64.json`
- Full query-hit verified-substitution smoke manifest:
  `cuflye-m6v-full-query-hit-verified-substitution-smoke-dgx-aarch64.json`
- Full query-hit selected bypass-plan manifest:
  `cuflye-m6w-full-query-hit-selected-bypass-plan-dgx-aarch64.json`
- Full query-hit selected bypass dry-run manifest:
  `cuflye-m6x-full-query-hit-selected-bypass-dry-run-dgx-aarch64.json`
- Full query-hit selected CPU-bypass smoke manifest:
  `cuflye-m6y-full-query-hit-selected-cpu-bypass-smoke-dgx-aarch64.json`
- Full query-hit selected CPU-bypass timing attribution manifest:
  `cuflye-m6z-full-query-hit-selected-cpu-bypass-timing-attribution-dgx-aarch64.json`
- Full query-hit selected graph-consumption parity manifest:
  `cuflye-m7a-full-query-hit-selected-graph-consumption-parity-dgx-aarch64.json`
- Full query-hit selected graph-consumption mutation canary manifest:
  `cuflye-m7b-full-query-hit-selected-graph-consumption-mutation-canary-dgx-aarch64.json`
- Read-to-graph selected CPU-skip canary manifest:
  `cuflye-m7c-read-to-graph-selected-cpu-skip-canary-dgx-aarch64.json`
- Read-to-graph selected CPU-skip timing manifest:
  `cuflye-m7d-read-to-graph-selected-cpu-skip-timing-dgx-aarch64.json`
- Read-to-graph quick-overlap/minimizer target manifest:
  `cuflye-m8a-read-to-graph-quick-overlap-minimizer-target-dgx-aarch64.json`
- Full-query-hit source pack for M8a target manifest:
  `cuflye-m8b-full-query-hit-source-pack-for-m8a-target-dgx-aarch64.json`
- Flye-side M8b worker session seam manifest:
  `cuflye-m8c-flye-side-m8b-worker-session-seam-dgx-aarch64.json`
- M8c guarded rehydration/shadow consumption manifest:
  `cuflye-m8d-m8c-guarded-rehydration-shadow-consumption-dgx-aarch64.json`
