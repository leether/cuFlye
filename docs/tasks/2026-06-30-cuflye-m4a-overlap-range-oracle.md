# Task Card: cuFlye M4a Overlap Range Oracle

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Define an overlap-range ABI and add a CPU oracle dump after Flye's
`OverlapDetector::getSeqOverlaps` chaining/filtering path.

The core question this card must answer is:

```text
Can cuFlye capture Flye CPU overlap ranges in a machine-checkable format before
attempting CUDA overlap chaining?
```

## Background

M1-M3 proved CUDA candidate-list parity and speed at the raw candidate boundary.
M4 moves one semantic step downstream: candidate hits must be chained into
`OverlapRange` records while preserving Flye's gap penalties, jump thresholds,
minimum overlap, overhang checks, primary-overlap selection, and divergence
filters.

Before implementing any GPU chain DP, the CPU overlap-range result must become a
stable oracle with validator and canonical diff tooling.

## In Scope

- Define `overlap-range-v1` TSV ABI.
- Add a Flye patch that appends CPU `OverlapRange` records when
  `CUFLYE_OVERLAP_DUMP` is set.
- Add validator and canonical diff tools for overlap-range dumps.
- Add `scripts/run_flye_fixture.sh --overlap-dump PATH`.
- Build patched Flye and run a deterministic toy fixture on DGX.
- Record compact proof under `tests/golden/`.

## Out of Scope

- No CUDA overlap chaining implementation.
- No change to Flye overlap semantics.
- No downstream graph equivalence claim.
- No full Flye assembly speedup claim.
- No large overlap TSV committed.

## C++ Style Constraints

- Keep the Flye patch small and local to `src/sequence/overlap.cpp`.
- Do not change `OverlapRange` fields or algorithms.
- Use `std::ofstream` append under an existing-style mutex only when the dump
  environment variable is set.
- Dump after `detectedOverlaps` is finalized and before it is returned.
- Preserve default Flye behavior when `CUFLYE_OVERLAP_DUMP` is unset.

## Deliverables

- `docs/abi/overlap-range-v1.md`
- `tools/validate_overlap_dump.py`
- `tools/diff_overlap_dumps.py`
- `patches/flye/2.9.6/0007-cuflye-overlap-range-dump.patch`
- `scripts/run_flye_fixture.sh --overlap-dump`
- DGX proof under `tests/golden/`

## Acceptance Gates

- ABI document defines all fields and ordering rules.
- Validator accepts a real DGX overlap dump and rejects malformed rows.
- Diff tool reports `match` for two deterministic CPU overlap runs.
- Patched Flye builds on DGX with patches through `0007`.
- Default toy Flye run without `CUFLYE_OVERLAP_DUMP` still completes.
- Two deterministic toy runs with `CUFLYE_OVERLAP_DUMP` complete.
- Overlap dumps are non-empty and validate as `overlap-range-v1`.
- Canonical SHA-256 values match across deterministic runs.
- No large overlap TSV is committed.

## Execution Checklist

- [x] Define overlap-range ABI.
- [x] Add overlap validator and diff tools.
- [x] Add Flye overlap dump patch.
- [x] Add run script overlap dump option.
- [x] Run local syntax/style gates.
- [x] Build and run patched Flye on DGX.
- [x] Validate and diff overlap dumps.
- [x] Record compact proof and close this card.

## Merge Note

Implementation commit: `2d1b50da40eb3006d9fa3cbf025f328eb97330ac`

DGX proof manifest:
`tests/golden/cuflye-m4a-overlap-range-oracle-dgx-aarch64.json`

Proof summary:

- Host: `edgexpert-45d2` (`aarch64`)
- Flye: `2.9.6-b1802`, patched through
  `0007-cuflye-overlap-range-dump.patch`
- Default toy run without `CUFLYE_OVERLAP_DUMP`: completed
- Overlap dump runs: two deterministic toy runs completed
- Records per run: `53,728`
- Raw SHA-256 for both dumps:
  `c9eb5a013a6380714f0c2bb592ac692f49ab030fb658bdf4ede4a9e10d8489e3`
- Canonical SHA-256 for both dumps:
  `71477479f412c90463aa60d8565b52da10f9dfec98d96387525ed50ae937c22b`
- Canonical diff: `match`
- Malformed overlap row validation: rejected as expected

This card does not claim CUDA overlap chaining or Flye end-to-end speedup. It
only establishes the CPU overlap-range oracle boundary needed for M4b.
