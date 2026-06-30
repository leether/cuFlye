# cuFlye Governance: Coding Style v0

Status: completed

Date: 2026-06-30

## Goal

Turn the coding-style decision into a repository-visible contract before more
CUDA backend code is added.

## Context

cuFlye has two different engineering surfaces:

- Flye integration patches, where minimal C++11-compatible diffs matter most;
- standalone CUDA prototypes, where explicit ABI records, deterministic output,
  and CUDA diagnostics matter most.

Adopting Google C++ Style or LLVM Style wholesale would create avoidable churn
and could make future Flye patch review harder.

## Allowed Scope

- Add a local coding-style document.
- Add a low-intrusion C++/CUDA formatter configuration.
- Exclude upstream clones and patch queues from accidental formatting.
- Link the style contract from project navigation docs.

## Excluded Scope

- Reformat existing Flye, GenomeWorks, patch, or CUDA files.
- Change CUDA kernels, Flye integration behavior, or ABI files.
- Adopt Google C++ Style, LLVM Style, or another external guide wholesale.

## Deliverables

- `docs/CODING_STYLE.md`
- `.clang-format`
- `.clang-format-ignore`
- README and Task Card index references

## Acceptance Gates

- The coding-style document distinguishes Flye patch code from standalone CUDA
  code.
- The document states language levels for Flye patches and CUDA prototypes.
- Formatter ignore rules exclude `upstream-flye/`, `GenomeWorks/`, and
  `patches/`.
- No algorithm or runtime behavior changes are included.

## Proof

This is a governance-only change. No runtime test is required.
