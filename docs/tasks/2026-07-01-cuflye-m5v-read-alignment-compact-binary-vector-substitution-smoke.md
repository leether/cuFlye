# Task Card: cuFlye M5v Read Alignment Compact Binary Vector Substitution Smoke

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build on M5u by moving from "Flye can validate and rehydrate compact binary
CUDA pre-divergence chains" to a tightly guarded substitution smoke for the
selected read-alignment slice.

The core question for this card is:

```text
After Flye validates compact-binary-v0, applies the existing divergence filter,
and proves GPU-derived goodChains match CPU goodChains for every selected query,
can Flye substitute those verified GPU-derived goodChains into the selected
_readAlignments slice while preserving exact artifacts and failing closed?
```

## In Scope

- Add an explicit opt-in mode for compact-binary pre-divergence vector
  substitution.
- Reuse the M5u parser, checksum/count gates, and CPU goodChains diff.
- Substitute only allowlisted selected-query chains after all selected fixtures
  pass validation.
- Preserve exact canonical Flye artifacts versus CPU on the toy-hifi selected
  batch.
- Add a negative proof that blocks substitution before graph mutation when any
  selected fixture mismatches or the compact binary is corrupt.

## Out of Scope

- No default GPU mode.
- No unbounded `_readAlignments` replacement.
- No CUDA minimizer overlap discovery.
- No replacement of Flye's CPU divergence/base-alignment stages.
- No performance claim outside the selected read-alignment slice.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrow.
- Keep the new substitution switch fail-closed and disabled by default.
- Use existing RAII containers and checked bounds; do not add direct owning
  `new`, `delete`, `malloc`, `free`, or CUDA resource ownership.
- Record audit fields that distinguish validation, comparison, and actual
  vector substitution.

## Deliverables

- Flye patch extending M5u compact-binary rehydration into guarded selected
  vector substitution.
- Positive DGX proof preserving exact artifacts.
- Negative DGX proof that blocks substitution before graph mutation.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a scoped benefit assessment.

## Acceptance Gates

- [ ] Patch series applies and patched Flye builds on DGX.
- [ ] CUDA worker builds on DGX.
- [ ] Positive compact-binary vector substitution reports all selected fixtures
      validated and substituted.
- [ ] Canonical Flye artifacts match CPU.
- [ ] Negative mismatch/corruption case fails closed before graph mutation.
- [ ] Audit JSON records `graph_mutation_consumed_worker_output=true` only for
      the positive, validated substitution path.
- [ ] Local and DGX syntax/style gates pass.
- [ ] Ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

Pending implementation.
