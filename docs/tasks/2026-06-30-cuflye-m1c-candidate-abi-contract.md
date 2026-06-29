# Task Card: cuFlye M1c Candidate ABI Contract

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Convert the M1a/M1b candidate dump into an explicit ABI and validation gate for
future CUDA candidate backends.

The core question this card must answer is:

```text
Can cuFlye define and machine-check the candidate records a CUDA backend must emit?
```

## Background

M1a captured Flye's CPU candidate list. M1b added a backend selector seam. M1c
defines the candidate record format, equality semantics, ordering constraints,
metadata expectations, and memory-budget reporting that a CUDA backend must
satisfy before it can be wired into Flye.

## In Scope

- Document candidate record ABI v1.
- Add a candidate dump validator.
- Define canonical equality and raw reproducibility hashes.
- Define the CUDA backend contract at the candidate-generation boundary.
- Validate existing DGX M1b candidate dumps against the ABI.
- Record compact proof.

## Out of Scope

- CUDA kernels.
- Device-memory implementation.
- Backend replacement.
- Flye graph or polishing changes.
- Large candidate dump commits.

## Deliverables

- `docs/abi/candidate-record-v1.md`
- `tools/validate_candidate_dump.py`
- README updates for M1c gate commands.
- DGX proof that M1b candidate dumps validate against ABI v1.

## Acceptance Gates

- Validator accepts the M1b default-backend candidate dump.
- Validator accepts the M1b explicit-CPU candidate dump.
- Validator verifies expected record count and raw SHA-256.
- Validator verifies canonical SHA-256 when requested.
- Existing candidate diff still returns `match`.
- Invalid candidate dumps fail validation.
- No large candidate dump file is committed.

## Execution Checklist

- [x] Add candidate ABI document.
- [x] Add candidate dump validator.
- [x] Add README gate commands.
- [x] Validate M1b default-backend dump on DGX.
- [x] Validate M1b explicit-CPU dump on DGX.
- [x] Validate canonical SHA-256 on DGX.
- [x] Verify invalid dump rejection locally.
- [x] Record compact proof and close this card.

## Merge Note

Completed on DGX host `edgexpert-45d2` using M1c validator source commit
`0f60b70` and the existing M1b candidate dumps.

ABI contract:

- Document: `docs/abi/candidate-record-v1.md`
- Validator: `tools/validate_candidate_dump.py`

Raw ABI validation:

- Default backend dump:
  `out/m1b/f311460/runs/toy-default/candidates.tsv`
- Explicit CPU backend dump:
  `out/m1b/f311460/runs/toy-cpu/candidates.tsv`
- Records per dump: `29035928`
- Size per dump: `946049505` bytes
- Raw SHA-256 per dump:
  `5e55b79e3cda21ce4d7e5e101a65f30b8fa9c3ba50b542faadbbb27d5c4bfebd`
- Raw files are not globally sorted by the canonical key. This is accepted by
  ABI v1 because equality is defined on the canonical multiset.

Canonical validation:

- Canonical SHA-256:
  `97ec5f51c034e5a8a8eaa70d4c3d4ced5513f7ee93ad367671b756814310086b`
- Candidate diff status: `match`

Negative validation:

- A local header-row TSV was rejected with:
  `query_id must be a decimal integer`

Tracked compact proof:

- `tests/golden/toy-hifi-candidate-abi-dgx-aarch64.json`
