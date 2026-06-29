# Task Card: cuFlye M0 CPU Oracle and Profiling Harness

Status: active

Created: 2026-06-29

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build the first machine-checkable proof loop for cuFlye before writing CUDA
kernels.

The core question this card must answer is:

```text
Can we prove that a candidate cuFlye backend did not change Flye semantics?
```

This card implements the M0 foundation from `CUDA_FLYE_DESIGN.md`: pinned CPU
Flye build, fixture execution, canonical artifact normalization, run-to-run
diffing, and CPU profiling.

## Background

cuFlye is targeting a Flye-compatible CUDA backend, not a replacement assembler
pipeline. GPU work must preserve Flye's CLI behavior, stage boundaries,
intermediate artifact schemas, and CPU implementation as the oracle.

The highest-ROI next step is therefore not CUDA code. It is a reproducible CPU
oracle harness that later GPU backends must pass.

Relevant local evidence:

- `CUDA_FLYE_DESIGN.md`: M0 requires unmodified Flye 2.9.6 build, fixtures,
  canonical diff tools, and profiler capture.
- `GENOMEWORKS_NOTES.md`: GenomeWorks is a design reference, not a drop-in Flye
  replacement.
- `upstream-flye`: local ignored checkout at Flye `2.9.6`, commit `886b8c1`.
- `upstream-flye/flye/tests/data/`: contains toy E. coli FASTA/FASTQ fixtures.
- `upstream-flye/flye/main.py`: defines stage artifact paths such as
  `draft_assembly.fasta`, `repeat_graph_dump`, `read_alignment_dump`, and
  `graph_final.gfa`.

## In Scope

- Add scripts to build pinned upstream Flye 2.9.6 from the ignored local
  `upstream-flye/` checkout.
- Add scripts to run a small fixture through the CPU Flye path.
- Add Python tooling to canonicalize Flye artifacts for deterministic diffing.
- Add Python tooling to compare two Flye run directories.
- Add a profiling wrapper for CPU baseline runs.
- Add small golden manifests and hashes; avoid committing large generated
  assemblies or BAM/SAM outputs.
- Document required local prerequisites and expected commands.

## Out of Scope

- CUDA kernels.
- GPU CLI flags.
- Any Flye algorithm change.
- Changing scientific assembly parameters to make tests easier.
- Vendoring `upstream-flye/` or `GenomeWorks/` into this root repo.
- Tracking large run outputs, sequencing datasets, BAM/SAM files, or profiler
  dumps in Git.

## Deliverables

- `scripts/build_flye_cpu.sh`
  - Builds the pinned CPU Flye checkout.
  - Fails if `upstream-flye` is not at the expected Flye version unless an
    explicit override is provided.

- `scripts/run_flye_fixture.sh`
  - Runs a named fixture with fixed, documented parameters.
  - Writes to a caller-provided output directory.
  - Captures command, environment, git refs, and elapsed time metadata.

- `tools/canonicalize_flye_artifacts.py`
  - Canonicalizes supported artifact types for stable comparison.
  - Handles at minimum FASTA, GFA, `repeat_graph_dump`, and
    `read_alignment_dump`.

- `tools/diff_flye_runs.py`
  - Compares canonical artifacts from two run directories.
  - Exits nonzero on semantic mismatch.
  - Emits a compact machine-readable summary plus a readable report.

- `bench/profile_flye_cpu.sh`
  - Runs CPU baseline profiling for toy and optional external sample inputs.
  - Captures wall time, peak RSS where available, command metadata, Flye log,
    and artifact hashes.

- `tests/golden/`
  - Stores manifests and hashes for small fixtures.
  - Does not store large generated output directories.

## Acceptance Gates

- `scripts/build_flye_cpu.sh` builds the local Flye 2.9.6 CPU path without
  modifying Flye source.
- `scripts/run_flye_fixture.sh` can run the upstream toy fixture end to end.
- Two CPU fixture runs can be compared by `tools/diff_flye_runs.py`.
- Canonical diff either passes cleanly or records a specific, reproducible
  nondeterminism that must be controlled before GPU work.
- `bench/profile_flye_cpu.sh` produces a baseline report with wall time and
  memory evidence.
- `git status --short --ignored` shows only intended tracked changes and ignored
  local reference checkouts.
- No generated large data is committed.

## Risks And Mitigations

Risk: Flye may have thread-order-sensitive behavior.

Mitigation: Start oracle fixtures with fixed parameters and conservative thread
counts. If nondeterminism appears, record it explicitly and narrow the
comparison contract before M1.

Risk: local build dependencies differ by host.

Mitigation: scripts must fail with clear prerequisite messages and record host
metadata in run manifests.

Risk: canonicalization can hide real semantic differences.

Mitigation: only canonicalize representation noise such as ordering and FASTA
line wrapping. Preserve identifiers, coordinates, sequence content, edge
records, scores, and divergence fields.

Risk: profiling without DGX data may optimize the wrong target.

Mitigation: make DGX/sample input optional but first-class in
`bench/profile_flye_cpu.sh`; do not make performance claims from toy data alone.

## Execution Checklist

- [ ] Create `scripts/`, `tools/`, `bench/`, and `tests/golden/` structure.
- [ ] Implement `scripts/build_flye_cpu.sh`.
- [ ] Implement `scripts/run_flye_fixture.sh`.
- [ ] Implement artifact canonicalization.
- [ ] Implement run diff.
- [ ] Implement CPU profiling wrapper.
- [ ] Add fixture manifest and golden hash documentation.
- [ ] Run build script.
- [ ] Run two independent CPU fixture runs.
- [ ] Diff the two fixture runs.
- [ ] Run CPU profiling wrapper on the toy fixture.
- [ ] Commit and push the M0 harness.

## Implementation Constraints

- Use POSIX shell for small wrappers where possible.
- Use Python standard library for canonicalization and diff tooling unless a
  dependency is clearly justified.
- Keep all paths relative to the repository root unless the caller supplies an
  absolute input/output path.
- Keep the ignored `upstream-flye/` and `GenomeWorks/` directories out of Git.
- Prefer manifests and hashes over committed generated outputs.

## Done Definition

This card is done when a future developer can clone `leether/cuFlye`, place or
fetch the expected Flye 2.9.6 reference checkout, run the documented M0 commands,
and get a reproducible CPU baseline plus canonical diff report that can later be
used as the first gate for CUDA backend work.

## Merge Note

Pending implementation.
