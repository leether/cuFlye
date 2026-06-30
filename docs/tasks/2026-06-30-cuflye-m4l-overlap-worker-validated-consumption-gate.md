# Task Card: cuFlye M4l Overlap Worker Validated Consumption Gate

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Add a fail-closed validation gate between Flye's overlap worker output and any
future graph-consumption path. The gate should prove that worker output is
ABI-valid and oracle-equivalent before a later milestone is allowed to replace
CPU overlap ranges with GPU-produced overlap ranges.

## Background

M4k proved Flye can collect an explicit replay-match query allowlist, generate
one packed CUDA overlap worker request, and stop before graph mutation. It also
proved the worker output for all captured fixtures matches the Flye CPU oracle.

The next risk is not raw speed; it is letting GPU output cross into Flye graph
logic without a governed check. M4l should build the validation machinery and
metadata that makes graph consumption impossible unless every selected worker
output passes the same ABI and diff gates used in the golden proof.

## In Scope

- Define a Flye-side validation gate for packed overlap worker outputs.
- Require `overlap-range-v1` validation before any consumption-eligible state is
  recorded.
- In proof mode, diff worker output against the CPU oracle fixture before
  allowing the seam to mark the batch as consumption-eligible.
- Record a compact validation summary for every fixture.
- Keep default CPU behavior unchanged.
- Keep graph mutation disabled in M4l unless a separate later card explicitly
  enables guarded consumption.

## Out of Scope

- No actual graph mutation from worker output.
- No default GPU mode.
- No arbitrary dataset claim.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No silent CPU fallback.

## Acceptance Gates

- Default CPU Flye fixture output remains unchanged.
- Explicit worker proof mode validates every worker TSV as `overlap-range-v1`.
- Explicit worker proof mode canonical-diffs every worker TSV against its CPU
  oracle before marking the batch consumption-eligible.
- A failed validation or diff prevents consumption eligibility and fails closed.
- The seam summary records both `graph_mutation_consumed_worker_output=false`
  and a separate consumption eligibility flag.
- DGX proof records one passing batch and at least one negative validation case.
- Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Use standard containers and stack objects for Flye-side gate state.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Keep validator invocation file-backed, explicit, and fail-closed.
- Do not silently continue when validator output is missing or malformed.

## Deliverables

- ABI/seam doc update for the consumption eligibility gate.
- Flye `2.9.6` patch-series entry after `0011`.
- Runner controls and metadata for validation-gated worker proof mode.
- DGX proof with one positive batch and one negative fail-closed case.
- This Task Card completed after proof.

## Execution Checklist

- [x] Define validation mode and seam-summary eligibility fields.
- [x] Add Flye patch for worker output validation and fail-closed summaries.
- [x] Extend fixture runner controls and metadata.
- [x] Build patched Flye on DGX.
- [x] Prove default CPU fixture behavior remains unchanged.
- [x] Prove positive batch mode validates and marks worker output eligible.
- [x] Prove negative validation mode fails closed and marks worker output
  ineligible.
- [x] Record compact DGX proof and close this card.

## Merge Note

Implementation commit: `fbc26e67cc8e4d0c5a1c38804ec06de9fb255ccb`

DGX proof:
`tests/golden/cuflye-m4l-overlap-worker-validated-consumption-gate-dgx-aarch64.json`

Results:

- Default `toy-hifi` CPU run completed and all 9 canonical artifact hashes
  matched the M0 golden manifest.
- Positive `toy-raw` batch worker run validated 9 worker TSV outputs in Flye,
  marked `worker_output_consumption_eligible=true`, and still recorded
  `graph_mutation_consumed_worker_output=false`.
- External Python validation confirmed all 9 positive worker outputs
  canonical-diffed `match` against their CPU oracles.
- Negative proof used a wrapper that ran the real worker, then removed one
  overlap record from `query_381`. Flye validation recorded `failed`, marked
  `worker_output_consumption_eligible=false`, wrote
  `status=validation-failed-before-graph-mutation`, and exited non-zero before
  graph mutation.
- DGX build, patch-series, syntax/style, and ownership gates passed.
