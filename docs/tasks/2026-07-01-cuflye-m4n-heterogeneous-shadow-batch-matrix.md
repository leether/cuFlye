# Task Card: cuFlye M4n Heterogeneous Shadow Batch Matrix

Status: completed

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

- [x] Default CPU Flye fixture output remains unchanged.
- [x] The heterogeneous fixture set is deterministic and documented in the proof.
- [x] Every selected fixture validates as `overlap-range-v1`.
- [x] Every selected fixture canonical-diffs `match` against its CPU oracle.
- [x] Every selected fixture shadow-compares `match` against captured CPU overlap
  ranges.
- [x] At least one negative heterogeneous shadow mismatch case fails closed before
  graph mutation.
- [x] DGX proof records timing and shape summaries for the matrix.
- [x] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Use standard containers and stack objects for selection and shadow state.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Do not silently drop unsupported shapes from the proof; unsupported exclusions
  must be explicit in metadata.

## Deliverables

- [x] Task Card completion with deterministic fixture selection notes.
- [x] DGX proof manifest for the heterogeneous shadow matrix.
- [x] Roadmap and golden manifest index updates after proof.

## Completion Notes

- Added `tools/select_overlap_shadow_matrix.py` to scan replay fixtures,
  explicitly exclude unsupported shapes, require Python replay canonical match,
  and select a deterministic heterogeneous matrix by shape extremes, medians,
  and greedy normalized metric distance.
- DGX scan captured `227` toy-raw replay fixtures. The selector found `96`
  supported replay-match fixtures, excluded `120` unsupported shapes and `11`
  replay mismatches, and selected `12` fixtures.
- Selected query ids:
  `353,381,-362,-498,651,477,-503,551,789,351,788,-484`.
- Selected shape range:
  - candidate records: `327` to `8372`
  - target groups: `18` to `231`
  - overlap records: `4` to `60`
  - overlap density: `0.0026367831245880024` to `0.027848101265822784`
- Positive DGX proof validated and shadow-compared all `12` selected fixtures
  as `match`, wrote `shadow_consumption_eligible=true`, and kept
  `graph_mutation_consumed_worker_output=false`.
- Negative DGX proof corrupted both the worker TSV and disk oracle for
  `query_353`; file validation still passed, while shadow comparison caught
  `8` CPU records versus `7` worker records and failed closed before graph
  mutation.
- Positive worker timing reported `5.560035 ms` backend mean total before
  write with one CUDA launch per timed run.
- Proof manifest:
  `tests/golden/cuflye-m4n-heterogeneous-shadow-batch-matrix-dgx-aarch64.json`.

Implementation commit:

- `da6c25e13baf110d1d44b47168829fdda7ec44d2`
