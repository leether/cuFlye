# Task Card: cuFlye M6g Query-Hit Replay Tie Closure

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Close or precisely bound the last M6f full-query-hit replay mismatch by
reproducing Flye's C++ equal-key sorting, DP tie/backtrack behavior, and
primary-overlap containment ordering for query `11` on edge sequence `-3587`.

## In Scope

- Build a focused replay diagnostic for the remaining query `11` / ext `-3587`
  mismatch.
- Compare Python replay match order, DP table, backtrack chains, primary
  overlap selection, and oracle rows.
- If needed, add an opt-in Flye diagnostic dump for the selected ext group only,
  keeping output bounded and deterministic.
- Update replay semantics to match Flye exactly, or record a minimized
  remaining ledger with concrete state-table differences.

## Out of Scope

- No CUDA kernel in M6g.
- No Flye graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Prefer Python diagnostics first; add Flye C++ diagnostics only if the
  remaining ordering behavior cannot be inferred from the source pack.
- Keep any Flye patch C++11-compatible and opt-in.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or CUDA resource
  APIs.

## Deliverables

- Focused replay diagnostic or updated replay implementation under `tools/`.
- Optional Flye diagnostic patch if source-pack evidence is insufficient.
- DGX golden manifest under `tests/golden/`.
- Roadmap update naming the first CUDA full-query-hit consumer if exact replay
  equality is reached.

## Acceptance Gates

- [ ] M6f full-query-hit source pack validates before replay.
- [ ] Replay either reaches exact `36/36` raw-overlap equality or records a
      minimized non-source-completeness ledger for query `11` / ext `-3587`.
- [ ] Deterministic replay A/B diff remains `match`.
- [ ] Full Flye canonical artifacts remain unchanged if any diagnostic capture
      option is enabled.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
