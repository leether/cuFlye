# Task Cards

Task Cards define bounded implementation slices for cuFlye. They are intended to
be executable change contracts: each card states the goal, allowed scope,
excluded scope, deliverables, acceptance gates, and proof expected before a
change is considered complete.

Active cards:

- None.

Proposed cards:

- `2026-07-01-cuflye-m6h-cuda-full-query-hit-replay-consumer.md`:
  build the first CUDA consumer for the M6g full-query-hit replay boundary,
  emitting row-key-compatible raw-overlap records for the selected source pack.

Completed cards:

- `2026-07-01-cuflye-m6g-query-hit-replay-tie-closure.md`:
  model libstdc++ `std::sort` equal-key ordering in the external replay
  harness, close the final M6f query `11` / edge sequence `-3587` mismatch, and
  reach row-key `36/36` equality while keeping non-key fields in a ledger.
- `2026-07-01-cuflye-m6f-full-query-hit-source-pack.md`:
  extend read-to-graph capture from query minimizer hits to the full Flye
  `IterKmers` query-hit stream, preserve exact Flye artifacts, and improve
  replay from M6e's `14/36` exact rows to `35/36`.
- `2026-07-01-cuflye-m6e-minimizer-source-replay-gap-closure.md`:
  consume the M6d source pack with an external CPU replay harness, reproduce
  deterministic KmerMatch grouping, chain DP, overlapTest, and primary-overlap
  filtering, and narrow the remaining gap to missing full query-hit source
  data with row-level examples.
- `2026-07-01-cuflye-m6d-read-to-graph-minimizer-source-pack.md`:
  capture deterministic read-to-graph minimizer source packs with query
  sequence, graph edge sequences, VertexIndex buckets, raw-overlap oracle rows,
  and chain-input oracle rows while preserving exact Flye canonical artifacts.
- `2026-07-01-cuflye-m6c-cuda-raw-overlap-filter-sort-replay.md`:
  consume the M6b replay pack with a bounded CUDA raw-overlap filter/sort
  prototype, prove CUDA output matches both oracle and CPU replay, and identify
  CUDA startup overhead as dominant on the tiny pack.
- `2026-07-01-cuflye-m6b-read-to-graph-input-boundary-replay-pack.md`:
  turn the M6a input-boundary oracle into an external replay/packing harness,
  prove deterministic pack export and CPU replay match, record unsupported
  exclusions, and identify what is still missing for true minimizer discovery.
- `2026-07-01-cuflye-m6a-read-to-graph-overlap-input-boundary.md`:
  define the read-to-graph overlap/minimizer input-boundary oracle, prove two
  deterministic CPU oracle runs canonical-diff `match`, preserve full Flye
  canonical artifacts, and show quick overlap discovery is the next higher-ROI
  CUDA target.
- `2026-07-01-cuflye-m5y-read-alignment-post-bypass-attribution.md`:
  attribute the remaining Flye wall time after M5x selected CPU-bypass, prove
  selected CPU pre-divergence chain and divergence-filter work are really
  bypassed while canonical artifacts still match, and choose M6a as the next
  CUDA boundary.
- `2026-07-01-cuflye-m5x-read-alignment-selected-cpu-bypass.md`:
  run an opt-in selected-read CPU-bypass mode for the full3546 selected set,
  skip selected CPU pre-divergence chain DP, consume verified compact-binary
  CUDA goodChains, preserve exact artifacts, and fail closed on corrupted
  compact binary payloads before graph mutation.
- `2026-07-01-cuflye-m5w-read-alignment-compact-binary-substitution-scaleup.md`:
  scale the M5v compact-binary vector-substitution proof from selected batch64
  to the full3546 selected read-alignment fixture set, preserve exact artifacts,
  and prove corrupted compact binary payloads still fail closed before graph
  mutation.
- `2026-07-01-cuflye-m5v-read-alignment-compact-binary-vector-substitution-smoke.md`:
  feed verified compact-binary CUDA-derived goodChains into Flye's selected
  `_readAlignments` slice, preserve exact artifacts, and prove mismatch or
  corrupted compact binary payloads fail closed before graph mutation.
- `2026-07-01-cuflye-m5u-read-alignment-compact-binary-flye-rehydration.md`:
  move the M5t compact binary payload into the Flye-side pre-divergence
  dry-run seam, validate and rehydrate it inside Flye, match CPU goodChains for
  the selected batch, preserve exact canonical artifacts, and fail closed on
  truncated/checksum-corrupted payloads before graph mutation.
- `2026-07-01-cuflye-m5t-read-alignment-compact-binary-payload.md`: replace
  the M5s compact JSONL proof payload with `compact-binary-v0`, byte-match the
  CPU compact binary oracle, reduce payload size from `1126769` bytes to
  `332736` bytes, and reduce CUDA full3546 compact request time from
  `4.450572 ms` to `2.273654 ms`.
- `2026-07-01-cuflye-m5s-read-alignment-session-output-overhead-reduction.md`:
  bypass per-fixture TSV emission in the read-alignment CUDA session path with
  a deterministic compact JSONL payload, preserve byte-level CPU equivalence,
  and reduce full3546 session request time from M5r's `91.698238 ms` to
  `4.450572 ms`.
- `2026-07-01-cuflye-m5r-read-alignment-pre-divergence-persistent-session.md`:
  remove fresh worker/context setup from Flye-side selected pre-divergence
  batches with a long-lived CUDA session proof, preserve exact artifacts and
  fail-closed behavior, and show a full3546 CUDA backend hot-path advantage
  over CPU while identifying file output as the next bottleneck.
- `2026-07-01-cuflye-m5q-read-alignment-pre-divergence-batch-crossover.md`:
  benchmark larger selected pre-divergence read-alignment batches, prove CUDA
  output parity, find a warm persistent-bulk hot-path win at full batch size,
  and identify fresh worker/CUDA setup as the integration blocker.
- `2026-07-01-cuflye-m5p-read-alignment-pre-divergence-batch-dry-run.md`:
  batch selected pre-divergence CUDA read-alignment chain output into one worker
  invocation, compare Flye-filtered goodChains per query, preserve exact
  artifacts, and fail closed on mismatch.
- `2026-07-01-cuflye-m5o-read-alignment-pre-divergence-flye-dry-run.md`:
  invoke CUDA pre-divergence read-alignment chain output from inside Flye, run
  Flye's divergence filter on GPU-produced chains, compare goodChains against
  CPU, preserve exact artifacts, and fail closed on mismatch.
- `2026-07-01-cuflye-m5n-read-alignment-pre-divergence-chain-output.md`:
  emit CUDA read-alignment chain DP results before CPU divergence acceptance,
  proving the worker no longer needs `chain-divergence.tsv` for that substage.
- `2026-07-01-cuflye-m5m-read-alignment-vector-substitution-smoke.md`:
  substitute a verified CUDA-derived `std::vector<GraphAlignment>` slice into
  `_readAlignments`, preserve exact artifacts, and fail closed on mismatch.
- `2026-07-01-cuflye-m5l-read-alignment-graph-alignment-object-vector-dry-run.md`:
  group typed CUDA read-alignment rows into a shadow `std::vector<GraphAlignment>`
  object vector, compare it with the CPU `_readAlignments` slice, and still
  stop before graph mutation.
- `2026-07-01-cuflye-m5k-read-alignment-typed-rehydration-dry-run.md`:
  convert validated CUDA read-alignment rows into GraphAlignment-shaped typed
  records in a no-consumption dry-run.
- `2026-07-01-cuflye-m5j-read-alignment-graph-dry-run-seam.md`: invoke and
  validate the M5i CUDA read-alignment backend from Flye in a no-mutation
  graph-facing dry-run seam.
- `2026-07-01-cuflye-m5i-persistent-bulk-output-copy.md`: reduce persistent
  read-alignment device-to-host overhead with explicit per-shape bulk output
  copies while preserving per-read oracle diffs and beating the bounded CPU
  replay pre-write benchmark.
- `2026-07-01-cuflye-m5h-larger-read-alignment-fixture-harvest.md`: expand
  real read-alignment replay work for the persistent CUDA arena while
  preserving per-read oracle diffs.
- `2026-07-01-cuflye-m5g-persistent-read-alignment-arena.md`: reduce grouped
  read-alignment CUDA overhead with reusable per-shape device buffers while
  preserving per-read oracle diffs.
- `2026-07-01-cuflye-m5f-heterogeneous-read-alignment-batch.md`: allow a
  heterogeneous real read-alignment fixture list to be grouped by supported
  CUDA shape while preserving per-read oracle diffs.
- `2026-07-01-cuflye-m5e-real-multiread-replay-batch.md`: replace
  replicated-batch read-alignment evidence with real multi-read fixture harvest
  and packed CUDA execution while preserving per-read oracle diffs.
- `2026-07-01-cuflye-m5d-read-alignment-replicated-batch.md`:
  turn the M5c single-read correctness benchmark into a replicated-batch CUDA
  occupancy test without changing the representative oracle.
- `2026-07-01-cuflye-m5c-cuda-read-alignment-chain-benchmark.md`:
  implement the first CUDA/CPU benchmark prototype for the bounded M5b
  read-alignment replay fixture while preserving the `read-alignment-v1`
  oracle.
- `2026-07-01-cuflye-m5b-read-alignment-replay-fixture.md`:
  isolate one bounded read-to-graph alignment chain fixture and replay it
  outside full Flye before CUDA read-alignment work starts.
- `2026-07-01-cuflye-m5a-read-alignment-oracle.md`:
  define `read-alignment-v1`, add an opt-in CPU oracle dump after
  `ReadAligner::alignReads`, and prove deterministic read-to-graph alignment
  dumps before any CUDA replacement work.
- `2026-07-01-cuflye-m4z-validation-safe-selection-planner.md`:
  rank validation-safe GPU-first query allowlists, reject known validation
  failures such as query `798`, and compare serial versus parallel-reduce
  worker timing on the accepted M4y fixture batch.
- `2026-07-01-cuflye-m4y-sparse-gpu-first-selection-audit-sampling.md`:
  reduce GPU-first proof overhead with selected-only substitution ledger output,
  use a bounded 7-query GPU-first selection set, preserve exact toy-raw
  artifacts, and fail closed on sampled GPU-first audit mismatch.
- `2026-07-01-cuflye-m4x-gpu-first-overlap-substitution-perf-gate.md`:
  reuse a verified file-backed CUDA session batch cache for a later allowlisted
  supported overlap query before live CPU overlap, preserve exact toy-raw
  artifacts, and fail closed on GPU-first audit mismatch.
- `2026-07-01-cuflye-m4w-true-persistent-overlap-worker-session.md`:
  submit a verified Flye overlap worker request to a true file-backed
  persistent CUDA session without a duplicate warmup request, preserve exact
  toy-raw artifacts, and reduce the selected worker/process segment versus
  M4u/M4v.
- `2026-07-01-cuflye-m4v-persistent-overlap-worker-lifecycle.md`:
  invoke the overlap worker through a two-request persistent JSONL lifecycle,
  keep the actual request warm, preserve exact toy-raw artifacts, and reduce
  measured request lifecycle cost versus the M4u cold batch worker process.
- `2026-07-01-cuflye-m4u-substitution-worker-overhead-reduction.md`:
  add opt-in session batch/cache substitution, preserving exact artifacts while
  reducing selected substitution worker-process and seam-total average timing
  versus M4t.
- `2026-07-01-cuflye-m4t-substitution-session-timing-attribution.md`:
  add per-decision timing attribution to graph-facing substitution sessions and
  prove exact artifact preservation while identifying worker/process overhead
  as the next optimization target.
- `2026-07-01-cuflye-m4s-substitution-supported-shape-expansion.md`:
  expand verified graph-facing substitution from one selected query to a
  deterministic supported-shape session ledger with substituted, skipped, and
  failed-closed decisions.
- `2026-07-01-cuflye-m4r-verified-overlap-vector-substitution-smoke.md`:
  return a verified `OverlapRange` object vector as an opt-in graph-facing
  substitution smoke for one selected query, with unchanged canonical Flye
  artifacts and negative fail-closed proof.
- `2026-07-01-cuflye-m4q-overlap-range-object-rehydration-dry-run.md`:
  convert validated typed overlap records into actual Flye `OverlapRange`
  objects in a no-mutation dry-run before graph consumption is enabled.
- `2026-07-01-cuflye-m4p-overlap-graph-consumption-rehydration-dry-run.md`:
  rehydrate validated CUDA overlap worker output into Flye-side typed overlap
  data in a no-mutation dry-run before any graph consumption path is enabled.
- `2026-07-01-cuflye-m4o-guarded-overlap-graph-consumption-design.md`: define
  the guarded-consumption contract and dry-run proof before any CUDA overlap
  output is allowed to affect Flye graph mutation.
- `2026-07-01-cuflye-m4n-heterogeneous-shadow-batch-matrix.md`: expand the
  validation and shadow-consumption proof from the fixed top-9 batch to a
  deterministic heterogeneous supported-shape replay matrix.
- `2026-06-30-cuflye-m4m-overlap-worker-shadow-consumption.md`: parse
  validated worker output into a Flye-side shadow overlap range structure and
  compare it against CPU overlap ranges without changing graph mutation.
- `2026-06-30-cuflye-m4l-overlap-worker-validated-consumption-gate.md`: add a
  fail-closed validation gate before any future graph-consumption path can treat
  CUDA overlap worker output as consumption-eligible.
- `2026-06-30-cuflye-m4k-flye-overlap-worker-batch-seam.md`: make the Flye
  seam collect an explicit replay-match query allowlist and invoke the packed
  overlap worker as a batch before graph mutation.
- `2026-06-30-cuflye-m4j-flye-overlap-worker-seam.md`: add a fail-closed
  Flye-side overlap worker seam without feeding GPU output into graph mutation.
- `2026-06-30-cuflye-m4i-packed-overlap-worker-protocol.md`: move the packed
  overlap speedup toward a governed worker boundary without changing Flye graph
  semantics.
- `2026-06-30-cuflye-m4h-packed-multi-query-overlap-kernel.md`: pack multiple
  replay-match overlap fixtures into fewer CUDA launches while preserving
  per-query overlap hashes.
- `2026-06-30-cuflye-m4g-batched-overlap-worker.md`: run real replay-match
  overlap fixtures through one long-lived batched CUDA worker.
- `2026-06-30-cuflye-m4f-overlap-chain-batched-fixtures.md`: collect or derive
  real batched overlap-chain fixtures before making further speed claims.
- `2026-06-30-cuflye-m4e-overlap-chain-parallel-reduction.md`: increase CUDA
  overlap-chain occupancy with group-internal parallel predecessor reduction.
- `2026-06-30-cuflye-m4d-overlap-chain-hotpath-benchmark.md`: add a fair CPU
  baseline and warm CUDA hotpath benchmark for the M4c supported fixture.
- `2026-06-30-cuflye-m4c-cuda-overlap-chain-dp-prototype.md`: implement the
  first CUDA overlap-chain DP prototype for the M4b supported fixture shape.
- `2026-06-30-cuflye-m4b-overlap-chain-replay-harness.md`: isolate Flye's
  candidate-to-overlap chaining contract in a bounded CPU replay before CUDA
  chain DP.
- `2026-06-30-cuflye-m4a-overlap-range-oracle.md`: define overlap-range ABI
  and CPU oracle dump tooling before CUDA overlap chaining.
- `2026-06-30-cuflye-m3e-sampled-pack-batch-planner.md`: generate sampled
  real-pack fixtures and plan heterogeneous worker requests.
- `2026-06-30-cuflye-m3d-worker-device-buffer-arena.md`: reuse worker device
  buffers across warm requests while preserving candidate equivalence.
- `2026-06-30-cuflye-m3c-device-prefix-compaction.md`: move sparse output
  prefix/compaction into the CUDA backend while preserving worker equivalence.
- `2026-06-30-cuflye-m3b-long-lived-cuda-worker.md`: build the first
  long-lived CUDA worker proof boundary for repeated pack-dump-v0 requests.
- `2026-06-30-cuflye-m3a-integration-path-decision.md`: choose the
  long-lived external CUDA worker path and seed the M3b worker protocol.
- `2026-06-30-cuflye-m2f-sparse-output-compaction.md`: replace dense
  pair-count-sized output materialization with sparse/compacted candidate output
  for the real-pack CUDA backend.
- `2026-06-30-cuflye-m2e-real-pack-timing-proof.md`: add real-pack
  candidate-boundary timing for CPU oracle generation, CUDA backend stages, and
  external adapter overhead without changing candidate semantics.
- `2026-06-30-cuflye-m2d-external-pack-query-stop.md`: make Flye invoke the
  external CUDA packed backend on one real packed query, parse records into the
  candidate boundary, and fail closed before downstream graph logic.
- `2026-06-30-cuflye-m2c-real-pack-cuda-consumer.md`: make the CUDA
  read-window backend consume a real `pack-dump-v0` bundle and match the
  packed CPU oracle.
- `2026-06-30-cuflye-cuda-raii-resource-layer.md`: add a move-only CUDA RAII
  resource layer and migrate standalone prototypes away from direct CUDA
  allocation/event ownership.
- `2026-06-30-cuflye-governance-memory-ownership-scan.md`: add memory/resource
  ownership rules and scan existing code for common C++/CUDA leak patterns.
- `2026-06-30-cuflye-governance-coding-style-v0.md`: define local C++/CUDA
  style rules and formatter scope without reformatting upstream or patch code.
- `2026-06-30-cuflye-m2b-real-data-pack-dump.md`: extract real Flye
  query/index data into a replayable packed candidate-backend bundle.
- `2026-06-30-cuflye-m2a-cuda-candidate-adapter-shell.md`: replace the CUDA
  backend stub with an external packed adapter shell and fail-closed guards.
- `2026-06-30-cuflye-m1j-cuda-candidate-core-benchmark.md`: benchmark the
  candidate equality-scan core and prove a bounded CUDA-over-CPU speedup.
- `2026-06-30-cuflye-m1i-cuda-read-window-smoke.md`: slide bounded read
  sequences on GPU to generate query k-mers before candidate equality join.
- `2026-06-30-cuflye-m1h-cuda-kmer-encoding-smoke.md`: compute Flye-style
  k-mer encodings and standard-form lookup keys on GPU before generating a
  small candidate-record-v1 TSV.
- `2026-06-30-cuflye-m1g-cuda-kmer-join-smoke.md`: generate a small
  candidate-record-v1 TSV on GPU from query k-mers and a k-mer index fixture.
- `2026-06-30-cuflye-m1f-cuda-candidate-smoke.md`: build the first CUDA kernel
  that emits a small candidate-record-v1 TSV matching a CPU oracle sample.
- `2026-06-30-cuflye-m1e-cuda-runtime-probe.md`: build and validate a
  standalone CUDA Runtime API probe on DGX.
- `2026-06-30-cuflye-m1d-cuda-backend-stub.md`: add a fail-fast CUDA backend
  adapter path before implementing kernels.
- `2026-06-30-cuflye-m1c-candidate-abi-contract.md`: define and validate the
  candidate record ABI for future CUDA backend output.
- `2026-06-30-cuflye-m1b-candidate-backend-seam.md`: add the first backend
  selector seam for future CUDA candidate generation.
- `2026-06-30-cuflye-m1a-candidate-oracle-backend-seam.md`: build the M1a
  candidate-generation oracle and patch overlay.
- `2026-06-29-cuflye-m0-cpu-oracle-profiling.md`: build the M0 CPU oracle,
  canonical artifact diff, and profiling harness.
