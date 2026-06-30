# Task Card: cuFlye M4s Substitution Supported-Shape Expansion

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Expand M4r from one selected graph-facing substitution smoke to a deterministic
supported-shape substitution session, while preserving exact CPU equivalence,
explicit unsupported-shape boundaries, and fail-closed behavior.

## Background

M4r proves one selected supported query can return a CUDA-worker-derived
`std::vector<OverlapRange>` and still produce identical Flye graph artifacts.
The next risk is breadth: Flye calls the overlap path from multiple subprocesses
and with multiple parameter shapes. M4s should make that boundary explicit by
tracking which query/shape pairs are eligible for substitution and which are
intentionally skipped or rejected.

M4s is still not a production GPU mode and not an end-to-end speed claim.

## In Scope

- Define a per-query substitution ledger for supported and skipped shapes.
- Replace the single durable sentinel with a session-level ledger that records
  every substitution decision.
- Support a deterministic allowlist of graph-facing queries whose replay shape
  is inside the M4c/M4r CUDA overlap-chain contract.
- Keep unsupported shapes explicit: either skipped after prior accepted proof,
  or failed closed when an unsupported shape is selected for substitution.
- Preserve exact CPU comparison before each accepted substitution.
- Compare canonical Flye artifacts against a CPU baseline.
- Include negative proofs for mismatch and unsupported selected shape.

## Out of Scope

- No broad Flye graph rewrite.
- No default GPU mode.
- No unsupported-shape CUDA substitution.
- No silent acceptance without a ledger entry.
- No large production dataset claim.
- No end-to-end speed claim.

## Acceptance Gates

- [x] Substitution ledger ABI is documented.
- [x] Every graph-facing substitution decision records query id, shape,
  decision, and reason.
- [x] Supported allowlisted queries can be substituted only after validation,
  shadow comparison, graph guard, typed rehydration, object rehydration, and
  exact CPU comparison pass.
- [x] Unsupported selected shapes fail closed when requested for substitution.
- [x] Unsupported non-selected shapes do not overwrite accepted proof files.
- [x] Canonical Flye artifacts match CPU for the positive session.
- [x] Negative mismatch and unsupported-shape proofs fail closed before graph
  mutation.
- [x] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- No raw owning pointers in cuFlye seam code.
- Keep ownership in `std::vector`, `std::map`, stack values, and RAII standard
  library objects.
- Keep ledger writes explicit and small; do not introduce global mutable state
  without a documented run-level file contract.
- Keep all GPU-derived graph-facing returns behind exact CPU comparison.

## Deliverables

- [x] Substitution ledger ABI/design documentation.
- [x] Flye seam patch that records supported, skipped, and rejected substitution
  decisions.
- [x] DGX proof manifest for positive, mismatch-negative, and unsupported-negative
  sessions.
- [x] Roadmap, Task Card, golden index, and plain-language benefit assessment.

## Completion Notes

Implementation commit: `8252761144f5216e6754930c52f5f9c1568e7382`

DGX proof:
`tests/golden/cuflye-m4s-substitution-session-ledger-dgx-aarch64.json`

Positive session:

- selected toy-raw query ids: `353,381`
- substituted query ids: `353,381`
- ledger decision counts:
  - `substituted`: `2`
  - `skipped-already-substituted`: `5`
  - `skipped-not-selected`: `1892`
  - `skipped-unsupported-non-selected-shape`: `987`
- per-query sentinels were written for accepted substitutions.
- canonical Flye graph/output artifacts matched the CPU toy-raw baseline.

Mismatch negative proof:

- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-overlap`
- substitution recorded `status=failed`, `state=failed-closed`, and
  `graph_facing_returned_worker_output=false`.
- ledger recorded a `failed-closed` decision.

Unsupported-shape negative proof:

- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=force-unsupported-selected-shape`
- selected query failed closed before worker invocation.
- ledger recorded `failed-closed-unsupported-selected-shape`.

Plain-language CUDA benefit: M4s still does not prove Flye is faster. It proves
controlled breadth and auditability: two selected supported queries can return
verified GPU-worker overlap vectors, while skipped and rejected query/shape
decisions are written to a session ledger instead of being hidden behind one
global sentinel.
