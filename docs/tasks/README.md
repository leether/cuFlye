# Task Cards

Task Cards define bounded implementation slices for cuFlye. They are intended to
be executable change contracts: each card states the goal, allowed scope,
excluded scope, deliverables, acceptance gates, and proof expected before a
change is considered complete.

Active cards:

- None.

Completed cards:

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
