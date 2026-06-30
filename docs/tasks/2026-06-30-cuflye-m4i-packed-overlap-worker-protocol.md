# Task Card: cuFlye M4i Packed Overlap Worker Protocol

Status: proposed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M4h packed overlap-chain speedup from a standalone replay executable
toward a governed worker boundary that can be called from Flye without changing
downstream graph semantics.

This card is intentionally proposed, not active. M4h reached the current stop
condition by proving a bounded CUDA-over-CPU overlap-chain speedup.

## In Scope

- Define a packed overlap worker request/response contract.
- Preserve per-query fixture provenance, hashes, and fail-closed behavior.
- Keep CPU oracle diff gates before any downstream Flye graph mutation.
- Measure worker overhead separately from packed CUDA kernel time.
- Decide whether M4h should integrate through the existing long-lived external
  CUDA worker lane or through a new overlap-specific worker.

## Out of Scope

- No default GPU mode.
- No end-to-end Flye speed claim.
- No graph integration before parity gates.
- No base-level alignment or bad-mapping trim replay.

## Acceptance Gates

- Worker contract is documented before implementation.
- A replay request can round-trip through the worker and reproduce M4h packed
  output hashes.
- Unsupported shapes fail closed with explicit metadata.
- Worker overhead is measured and compared with M4h standalone packed timing.
