# Task Card: cuFlye M6b Read-To-Graph Input Boundary Replay Pack

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M6a read-to-graph input-boundary oracle into an external replay and
packing harness. The goal is to make the future CUDA candidate/minimizer
prototype reproduce Flye's `chain_input` records before any GPU output can be
fed back into Flye graph logic.

## In Scope

- Define a compact replay-pack schema for one or more M6a query ids.
- Build a tool that reads the M6a TSV, emits deterministic per-query packs, and
  writes a manifest with counts, hashes, and timing provenance.
- Build a CPU replay checker that reconstructs canonical `chain_input` rows
  from the pack and diffs them against the M6a oracle.
- Capture a bounded DGX toy-hifi pack set, including at least one query with
  multiple raw overlaps and one query with filtered-out raw overlaps.
- Record why the pack is sufficient for a CUDA candidate/minimizer prototype
  and what information is still missing.

## Out of Scope

- No CUDA kernel in M6b.
- No Flye graph mutation from replayed records.
- No default GPU mode.
- No whole-Flye speed claim.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep the M6b replay pack as a documented ABI, not an ad hoc dump.
- Use explicit integer widths in any binary or C++ ABI records.
- Keep generated large packs under `out/` and commit only compact manifests.
- Unsupported shapes must fail closed when later consumed by CUDA tooling.

## Deliverables

- Replay-pack ABI documentation under `docs/abi/`.
- Pack/export tool under `tools/`.
- CPU replay/diff tool under `tools/`.
- DGX golden manifest under `tests/golden/`.
- Roadmap update naming the first CUDA prototype boundary after M6b.

## Acceptance Gates

- [x] M6a input-boundary dump validates before packing.
- [x] Pack export is deterministic across two runs.
- [x] CPU replay from pack canonical-diffs `match` against M6a `chain_input`
      records for all selected queries.
- [x] Pack manifest records query ids, raw overlap counts, chain input counts,
      canonical hashes, and unsupported-shape exclusions.
- [x] Local and DGX syntax/style gates pass.

## Completion Notes

Implemented with:

- `docs/abi/read-to-graph-input-boundary-replay-pack-v0.md`
- `tools/export_read_to_graph_input_boundary_pack.py`
- `tools/replay_read_to_graph_input_boundary_pack.py`

DGX proof root:

```text
/tmp/cuflye-m6b-proof-20260701T055901Z
```

Proof summary:

- Source M6a input-boundary dump validated with canonical SHA-256
  `674a6bc7ffb42a058859254ac78aa83b374c578a18d17a339bd2e6a669d6d628`.
- Two independent pack exports produced directory diff `match`.
- Selected query ids: `5,6,7,8,9,10,11,12`.
- Selected pack records: 36 raw overlaps, 8 oracle `chain_input` rows, and 28
  filtered-out raw overlaps.
- CPU replay from both packs reproduced `oracle.chain-input.tsv` with SHA-256
  `5ab7b7fe51af9e90807e2d9be4824bd9216c732877cebc5eca58cb606b1c9f20`.
- Unsupported-shape exclusions were recorded for 60 queries:
  `duplicate_chain_input_read_begin=59`, `chain_input_count_zero=1`.
- The pack manifest explicitly records that it is sufficient for a CUDA
  raw-overlap filter/sort replay prototype, but still missing query sequences,
  graph edge sequences, VertexIndex minimizer buckets, k-mer parameters, and
  `quickSeqOverlaps` internals for full candidate/minimizer generation.

Plain-language benefit:

M6b still does not make Flye faster because it intentionally adds no CUDA
kernel. Its benefit is engineering leverage: the next CUDA prototype now has a
small deterministic pack, expected output, unsupported-shape ledger, and replay
gate. That means M6c can ask one clean question: can CUDA reproduce these
`chain_input` rows from the packed raw overlaps? A later step still needs a
richer pack before claiming true CUDA minimizer discovery.
