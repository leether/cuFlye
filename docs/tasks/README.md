# Task Cards

Task Cards define bounded implementation slices for cuFlye. They are intended to
be executable change contracts: each card states the goal, allowed scope,
excluded scope, deliverables, acceptance gates, and proof expected before a
change is considered complete.

Active cards:

- None.

Completed cards:

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
