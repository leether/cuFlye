# Task Card: cuFlye M6d Read-To-Graph Minimizer Source Pack

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Extend the M6 boundary from raw-overlap replay toward true
`quickSeqOverlaps`/candidate-minimizer generation by capturing the source data
that M6b intentionally omitted: query read sequence, graph edge sequences,
VertexIndex minimizer buckets, and k-mer/minimizer parameters.

## In Scope

- Define a minimizer-source pack ABI for selected read-to-graph queries.
- Capture query read sequence and relevant graph edge sequence slices.
- Capture enough VertexIndex bucket/minimizer data to replay candidate discovery
  outside Flye.
- Preserve the M6a `raw_overlap` and `chain_input` oracle rows for selected
  queries.
- Build a CPU replay checker that verifies the pack can reproduce the same
  raw-overlap candidate boundary or identifies exact missing semantics.
- Record unsupported shapes and missing semantic gaps explicitly.

## Out of Scope

- No CUDA kernel in M6d.
- No Flye graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patching minimal and C++11-compatible.
- Use explicit-width integer fields at ABI boundaries.
- Keep generated large sequence/index packs under `out/`; commit compact
  manifests only.
- Fail closed if a selected query cannot be replayed or if required source data
  is missing.

## Deliverables

- Minimizer-source pack ABI documentation under `docs/abi/`.
- Flye patch or external extractor for source pack capture.
- CPU replay/validation tool under `tools/`.
- DGX golden manifest under `tests/golden/`.
- Roadmap update naming the first CUDA minimizer-source consumer.

## Acceptance Gates

- [ ] Selected source packs include query sequence, edge sequence metadata,
      relevant minimizer/index buckets, M6a raw-overlap oracle, and M6a
      chain-input oracle.
- [ ] Two deterministic source-pack exports canonical-diff `match`.
- [ ] CPU replay either reproduces the selected raw-overlap boundary or records
      a precise missing-semantics ledger.
- [ ] Full Flye canonical artifacts remain unchanged with source-pack capture
      enabled.
- [ ] Local and DGX syntax/style gates pass.

## Completion Notes

Pending implementation.
