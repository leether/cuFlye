# Task Card: cuFlye M4b Overlap Chain Replay Harness

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build a bounded CPU replay harness for Flye overlap chaining so cuFlye can
reproduce the M4a `overlap-range-v1` oracle outside a full Flye run before
introducing CUDA chain DP.

The core question this card must answer is:

```text
Can cuFlye isolate Flye's candidate-to-overlap chaining contract and replay it
against a small fixture with machine-checkable overlap-range parity?
```

## Background

M4a established a deterministic CPU oracle dump after
`OverlapDetector::getSeqOverlaps`. The next risk is semantic: candidate records
are not yet enough to reconstruct final overlap ranges because Flye's chaining
path also depends on ordered candidate hits, gap scoring, jump pruning,
overhang checks, minimum overlap, primary-overlap filtering, and divergence
filtering.

M4b must isolate that contract before CUDA work starts. A replay harness gives
the future CUDA implementation a narrow target: the same inputs must produce
the same `overlap-range-v1` output.

## In Scope

- Identify the minimal Flye inputs needed to replay candidate-to-overlap
  chaining for a bounded toy query.
- Add a compact replay fixture derived from the DGX M4a run.
- Add a CPU replay tool or Flye-side patch mode that emits
  `overlap-range-v1`.
- Reuse `tools/validate_overlap_dump.py` and `tools/diff_overlap_dumps.py`.
- Record a compact DGX proof under `tests/golden/`.

## Out of Scope

- No CUDA overlap chaining implementation.
- No graph construction or graph equivalence claim.
- No full Flye assembly speedup claim.
- No broad fixture matrix; M4b is allowed to start with one bounded toy query.
- No large candidate or overlap TSV committed.

## C++/CUDA Style Constraints

- Keep any Flye integration patch C++11-compatible and minimal.
- Keep standalone replay code in original cuFlye style and aligned with
  `docs/CODING_STYLE.md`.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Prefer `std::vector`, `std::string`, stack objects, and existing RAII helpers
  for local ownership.
- Use explicit-width integer types at file-format and ABI boundaries.
- Keep CUDA out of this card unless it is only a build-system no-op; M4b is a
  CPU semantic isolation step.

## Deliverables

- A replay fixture manifest or generator that points to compact inputs.
- A CPU overlap-chain replay tool or patch mode.
- A DGX proof manifest under `tests/golden/`.
- Documentation of unsupported shapes and required future CUDA inputs.

## Acceptance Gates

- The replay fixture is small enough for git, or only a compact manifest/hash is
  committed.
- The CPU replay output validates as `overlap-range-v1`.
- The CPU replay output canonical-diffs `match` against the M4a oracle for the
  selected bounded query or fixture.
- Unsupported shapes fail closed with an explicit reason.
- Local syntax/style gates pass.
- Patch overlay, if any, applies cleanly after patches through `0007`.
- DGX proof is compact and does not include large TSV outputs.

## Execution Checklist

- [ ] Inspect Flye chaining inputs around `OverlapDetector::getSeqOverlaps`.
- [ ] Choose the smallest replayable fixture boundary.
- [ ] Add fixture manifest or generator.
- [ ] Add CPU replay tool or patch mode.
- [ ] Validate replay output as `overlap-range-v1`.
- [ ] Diff replay output against the M4a oracle.
- [ ] Run local syntax/style gates.
- [ ] Run DGX proof and record compact manifest.
