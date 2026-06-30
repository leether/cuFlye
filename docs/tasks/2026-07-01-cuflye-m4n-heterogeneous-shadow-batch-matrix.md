# Task Card: cuFlye M4n Heterogeneous Shadow Batch Matrix

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Expand the M4m shadow-consumption proof from the fixed top-9 replay-match batch
to a broader heterogeneous supported-shape overlap replay matrix, while keeping
GPU output out of Flye graph mutation.

## Background

M4m proves the in-memory shadow boundary for the top-9 packed replay batch:
validated worker output can be parsed back into Flye-side canonical overlap
records and compared against CPU overlap ranges captured in memory. The next
risk is coverage. Before any guarded graph-consumption milestone, cuFlye should
show that the same validation and shadow gates hold across more query shapes,
record counts, target-group counts, and candidate densities.

## In Scope

- Build a deterministic heterogeneous fixture selection from existing toy-raw
  replay captures or a fresh bounded DGX capture.
- Run the selected supported-shape fixtures through the packed CUDA overlap
  worker with validation and shadow mode enabled.
- Record per-fixture shape metadata: candidate records, target groups, overlap
  records, and query id.
- Preserve validation and shadow match gates for every selected fixture.
- Keep default CPU behavior unchanged.
- Keep graph mutation on CPU output only.

## Out of Scope

- No GPU output used by graph mutation.
- No default GPU mode.
- No arbitrary production dataset claim.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No silent CPU fallback.

## Acceptance Gates

- Default CPU Flye fixture output remains unchanged.
- The heterogeneous fixture set is deterministic and documented in the proof.
- Every selected fixture validates as `overlap-range-v1`.
- Every selected fixture canonical-diffs `match` against its CPU oracle.
- Every selected fixture shadow-compares `match` against captured CPU overlap
  ranges.
- At least one negative heterogeneous shadow mismatch case fails closed before
  graph mutation.
- DGX proof records timing and shape summaries for the matrix.
- Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Use standard containers and stack objects for selection and shadow state.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Do not silently drop unsupported shapes from the proof; unsupported exclusions
  must be explicit in metadata.

## Deliverables

- Task Card completion with deterministic fixture selection notes.
- DGX proof manifest for the heterogeneous shadow matrix.
- Roadmap and golden manifest index updates after proof.
