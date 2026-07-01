# Task Cards

Task Cards define bounded implementation slices for cuFlye. They are intended to
be executable change contracts: each card states the goal, allowed scope,
excluded scope, deliverables, acceptance gates, and proof expected before a
change is considered complete.

Active cards:

- None.

Proposed cards:

- None.

Completed cards:

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
