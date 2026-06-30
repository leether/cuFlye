# Task Card: cuFlye M4j Flye Overlap Worker Seam

Status: completed

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
- Add a patch-series entry for Flye `2.9.6`.
- Extend the fixture runner with explicit M4j seam environment controls.

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

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with the upstream source tree.
- Use standard containers and stack objects for CPU-owned memory.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Keep external process invocation file-backed and explicit.
- Do not silently fall back to CPU when worker mode is requested.
- Throw before graph mutation after a successful proof-mode worker response.

## Deliverables

- Flye overlap worker seam ABI doc.
- Flye `2.9.6` patch that generates an M4i worker request and stops.
- Fixture runner options for the seam environment.
- DGX proof showing default CPU behavior and explicit worker proof mode.
- This Task Card completed after proof.

## Execution Checklist

- [x] Document Flye-side seam environment and outputs.
- [x] Add Flye patch for request generation, worker invocation, and stop.
- [x] Extend fixture runner options and metadata.
- [x] Build patched Flye on DGX.
- [x] Prove default CPU fixture behavior remains unchanged.
- [x] Prove explicit worker proof mode records response and stops before graph
  mutation.
- [x] Validate and diff worker outputs.
- [x] Record compact DGX proof and close this card.

## Merge Note

Implementation commit:
`4fe144cf745323d4ca73dff73c3ae990addd8029`.

DGX proof:
`tests/golden/cuflye-m4j-flye-overlap-worker-seam-dgx-aarch64.json`.

M4j added `docs/abi/flye-overlap-worker-seam-v0.md`, Flye patch
`0010-cuflye-flye-overlap-worker-seam.patch`, and fixture-runner controls for
`CUFLYE_OVERLAP_WORKER_MODE=packed-replay-v0`.

The proof passed all gates on DGX host `edgexpert-45d2`:

- Patched Flye `2.9.6` built through patch `0010`.
- Default `toy-hifi` CPU run completed with exit status `0`.
- Default CPU artifact hashes matched the M0 `toy-hifi` golden set for all
  `9` canonical artifacts.
- Explicit `toy-raw` worker proof captured `query -71`, generated a
  `cuflye-overlap-worker-request-v0` request, invoked the CUDA worker, and
  stopped with the expected proof-mode failure before graph mutation.
- `seam-summary.json` recorded
  `graph_mutation_consumed_worker_output=false`.
- The worker emitted `51` `overlap-range-v1` records, matching the Flye CPU
  oracle canonical SHA-256
  `1a3347f96c74e0297a80871b32fa6cce2bccbf2731a7facb95e9333185c23e73`.
- Local and DGX syntax/style gates passed, and the M4j ownership scan found no
  new direct owning resource APIs.

M4j proves a governed Flye-side request/response boundary. It still does not
feed GPU output into Flye graph logic and does not claim end-to-end GPU speed.
