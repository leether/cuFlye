# Task Card: cuFlye M1c Candidate ABI Contract

Status: active

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

- [ ] Add candidate ABI document.
- [ ] Add candidate dump validator.
- [ ] Add README gate commands.
- [ ] Validate M1b default-backend dump on DGX.
- [ ] Validate M1b explicit-CPU dump on DGX.
- [ ] Validate canonical SHA-256 on DGX.
- [ ] Verify invalid dump rejection locally.
- [ ] Record compact proof and close this card.

## Merge Note

Pending implementation.
