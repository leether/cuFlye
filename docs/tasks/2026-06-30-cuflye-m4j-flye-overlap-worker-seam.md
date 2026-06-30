# Task Card: cuFlye M4j Flye Overlap Worker Seam

Status: proposed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Introduce a fail-closed Flye-side seam that can invoke the M4i packed overlap
worker at a bounded replay boundary without feeding GPU output into graph
mutation.

## Background

M4h proved a bounded packed CUDA overlap-chain speedup on the top-9 real
replay-match fixture batch. M4i put that packed replay path behind an
overlap-specific worker protocol and proved warm worker requests preserve every
fixture oracle hash.

The next integration risk is not the CUDA kernel. It is the Flye boundary:
cuFlye needs a governed place where Flye can request overlap worker output,
validate it, and stop before graph logic consumes it.

## In Scope

- Define the Flye-side overlap worker seam and environment selector.
- Keep default Flye CPU behavior unchanged.
- Invoke the M4i overlap worker only in explicit proof mode.
- Emit request/response metadata and stop before downstream graph mutation.
- Validate worker output against CPU overlap oracle before any future graph
  consumption.
- Record compact DGX proof.

## Out of Scope

- No default GPU mode.
- No graph mutation from worker output.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No arbitrary-dataset overlap-chain speed claim.
- No end-to-end Flye speed claim.

## Acceptance Gates

- Default CPU Flye run remains unchanged.
- Explicit proof mode generates an M4i worker request from Flye-side metadata.
- Worker response is recorded and failure is fail-closed.
- The proof stops before graph mutation.
- Worker output validates as `overlap-range-v1` and canonical-diffs `match`
  against the CPU oracle.
- Local and DGX gates pass.
