# Task Cards

Task Cards define bounded implementation slices for cuFlye. They are intended to
be executable change contracts: each card states the goal, allowed scope,
excluded scope, deliverables, acceptance gates, and proof expected before a
change is considered complete.

Active cards:

- None.

Completed cards:

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
