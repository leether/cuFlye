# Task Card: cuFlye M4o Guarded Overlap Graph Consumption Design

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Define the first safe contract for allowing validated CUDA overlap worker output
to approach Flye graph mutation, without enabling graph mutation by default.

## Background

M4l proved file-level validation, M4m proved in-memory shadow comparison for the
top-9 batch, and M4n expanded that proof to a deterministic heterogeneous
supported-shape matrix. The remaining risk is not whether the worker can emit
matching records on selected fixtures; it is how Flye would consume those
records without hiding divergence, fallback, or graph-level changes.

## In Scope

- Define an opt-in guarded-consumption mode that is off by default.
- Specify CPU/GPU dual-run behavior at the overlap boundary.
- Specify exact preconditions for consuming worker output:
  validation passed, shadow passed, selected mode is explicit, fixture count
  matches, and graph-consumption audit metadata can be written.
- Specify fail-closed behavior for mismatches, missing metadata, unsupported
  shapes, worker errors, and partial batches.
- Define the graph-consumption audit schema before writing mutation code.
- Add a no-mutation dry-run proof that exercises the new guard contract.

## Out of Scope

- No default GPU mode.
- No unverified GPU overlap output consumed by graph mutation.
- No end-to-end speed claim.
- No broad production dataset compatibility claim.
- No silent CPU fallback.

## Acceptance Gates

- [x] Guarded-consumption mode is documented and disabled by default.
- [x] The guard contract requires validation and shadow success before eligibility.
- [x] Audit metadata distinguishes `eligible`, `consumed`, `not-consumed`, and
  `failed-closed`.
- [x] Dry-run proof records that all guard preconditions are satisfied but graph
  mutation is still not performed.
- [x] Negative dry-run proof fails closed when a guard precondition is false.
- [x] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Keep graph-consumption state explicit and local to the seam until the real
  mutation path is introduced.
- Use standard containers and stack objects for guard metadata.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.

## Deliverables

- [x] Guarded-consumption ABI/design document.
- [x] Flye seam dry-run metadata fields or patch if needed.
- [x] DGX proof manifest for positive and negative dry-run guards.
- [x] Roadmap and golden manifest index updates after proof.

## Completion Notes

- Added `CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE=dry-run-v0`.
- Added `worker-graph-consumption-guard.json` with schema
  `cuflye-overlap-graph-consumption-guard-v0`.
- Added guard fields to `seam-summary.json`:
  `graph_guard_status`, `graph_guard_eligibility`,
  `graph_consumption_state`, `graph_consumption_decision`, and
  `graph_consumption_eligible`.
- Positive DGX proof used the M4n 12-fixture heterogeneous matrix with
  validation and shadow enabled. The guard wrote `status=passed`,
  `guard_eligibility=eligible`, `graph_consumption_state=not-consumed`, and
  `graph_mutation_consumed_worker_output=false`.
- Negative DGX proof enabled the guard without shadow mode. Validation still
  passed, but guard checks `shadow_mode_selected` and `shadow_passed` failed,
  producing `status=guard-failed-before-graph-mutation` before graph mutation.
- Proof manifest:
  `tests/golden/cuflye-m4o-guarded-overlap-graph-consumption-dgx-aarch64.json`.

## Plain-Language CUDA Benefit Assessment

This step does not make Flye faster. Its benefit is safety and engineering
discipline: before any CUDA overlap output is allowed to influence Flye graph
construction, the code now has a named dry-run guard that requires validation
and shadow success, writes clear audit metadata, and fails closed when a
precondition is missing. In practical terms, M4o reduces the risk of the next
CUDA integration step; it is not a performance milestone.

Implementation commit:

- `14b96fa064786899ee80f764c795d07d0fc21237`
