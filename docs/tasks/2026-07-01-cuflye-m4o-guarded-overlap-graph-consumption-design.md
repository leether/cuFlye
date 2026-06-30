# Task Card: cuFlye M4o Guarded Overlap Graph Consumption Design

Status: proposed

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

- Guarded-consumption mode is documented and disabled by default.
- The guard contract requires validation and shadow success before eligibility.
- Audit metadata distinguishes `eligible`, `consumed`, `not-consumed`, and
  `failed-closed`.
- Dry-run proof records that all guard preconditions are satisfied but graph
  mutation is still not performed.
- Negative dry-run proof fails closed when a guard precondition is false.
- Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Keep graph-consumption state explicit and local to the seam until the real
  mutation path is introduced.
- Use standard containers and stack objects for guard metadata.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.

## Deliverables

- Guarded-consumption ABI/design document.
- Flye seam dry-run metadata fields or patch if needed.
- DGX proof manifest for positive and negative dry-run guards.
- Roadmap and golden manifest index updates after proof.
