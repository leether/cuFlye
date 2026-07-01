# Task Card: cuFlye M6b Read-To-Graph Input Boundary Replay Pack

Status: proposed

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

- [ ] M6a input-boundary dump validates before packing.
- [ ] Pack export is deterministic across two runs.
- [ ] CPU replay from pack canonical-diffs `match` against M6a `chain_input`
      records for all selected queries.
- [ ] Pack manifest records query ids, raw overlap counts, chain input counts,
      canonical hashes, and unsupported-shape exclusions.
- [ ] Local and DGX syntax/style gates pass.

## Completion Notes

Pending implementation.
