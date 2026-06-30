# Task Card: cuFlye M4b Overlap Chain Replay Harness

Status: completed

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

- [x] Inspect Flye chaining inputs around `OverlapDetector::getSeqOverlaps`.
- [x] Choose the smallest replayable fixture boundary.
- [x] Add fixture manifest or generator.
- [x] Add CPU replay tool or patch mode.
- [x] Validate replay output as `overlap-range-v1`.
- [x] Diff replay output against the M4a oracle.
- [x] Run local syntax/style gates.
- [x] Run DGX proof and record compact manifest.

## Merge Note

Implementation commit: `84d1355c10512d98d224245e295d6046aae7d77c`

DGX proof manifest:
`tests/golden/cuflye-m4b-overlap-chain-replay-dgx-aarch64.json`

Proof summary:

- Host: `edgexpert-45d2` (`aarch64`)
- Flye: `2.9.6-b1802`, patched through
  `0008-cuflye-overlap-replay-fixture-dump.patch`
- Fixture: `toy-raw`, selected query id `-71`
- Candidate records: `7,859`
- Target records: `120`
- Oracle overlap records: `51`
- Replayed overlap records: `51`
- Candidate canonical SHA-256:
  `c3c0a64b60173b91f890b4f38e6a025e36521326213311757fb4d3f41c272dd5`
- Overlap canonical SHA-256:
  `1a3347f96c74e0297a80871b32fa6cce2bccbf2731a7facb95e9333185c23e73`
- Canonical diff: `match`
- Unsupported shape negative gate: base-alignment/trim fixture rejected as
  expected

This card does not implement CUDA overlap chaining. It isolates the first
supported CPU chain replay shape for M4c.
