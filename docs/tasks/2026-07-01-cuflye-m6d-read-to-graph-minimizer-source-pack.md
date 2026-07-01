# Task Card: cuFlye M6d Read-To-Graph Minimizer Source Pack

Status: accepted

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
- Build a CPU validation checker that verifies the source pack is complete
  enough for the next replay milestone or identifies exact missing semantics.
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

- [x] Selected source packs include query sequence, edge sequence metadata,
      relevant minimizer/index buckets, M6a raw-overlap oracle, and M6a
      chain-input oracle.
- [x] Two deterministic source-pack exports canonical-diff `match`.
- [x] CPU replay either reproduces the selected raw-overlap boundary or records
      a precise missing-semantics ledger.
- [x] Full Flye canonical artifacts remain unchanged with source-pack capture
      enabled.
- [x] Local and DGX syntax/style gates pass.

## Completion Notes

Accepted with DGX proof:

- Golden manifest:
  `tests/golden/cuflye-m6d-read-to-graph-minimizer-source-pack-dgx-aarch64.json`
- Proof root: `/tmp/cuflye-m6d-proof-20260701T062142Z`
- Host: `edgexpert-45d2`, `aarch64`
- Fixture: `toy-hifi`
- Patch series: Flye 2.9.6 plus patches `0001..0040`
- Source-pack query ids: `5,6,7,8,9,10,11,12`
- Source-pack canonical SHA-256:
  `4b38ac5dfc40e6e4ac7308b24c1286494241954a872eac8de33a25f5ccff5e87`
- Source-pack totals: `7725` query minimizers, `7640` index bucket records,
  `33` edge sequence records, `36` raw-overlap records, and `8`
  `chain_input` oracle rows.
- Deterministic source-pack diff: `match`
- Baseline versus source-pack Flye canonical artifact diffs: `match` for both
  capture runs.
- Replay status: `missing-semantics-ledger`

Plain-language benefit:

M6d does not make Flye faster yet. It gives the CUDA effort the right raw
materials for the next step: instead of replaying already-discovered overlaps,
we can now inspect the query sequence, Flye minimizers, VertexIndex bucket
hits, graph edge sequences, and downstream oracle rows in one deterministic
pack. That makes the remaining `quickSeqOverlaps` semantics explicit before a
GPU implementation tries to replace them.
