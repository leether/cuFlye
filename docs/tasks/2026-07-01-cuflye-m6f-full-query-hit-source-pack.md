# Task Card: cuFlye M6f Full Query-Hit Source Pack

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Close the main M6e replay gap by extending read-to-graph source capture from
query minimizer hits to the full `OverlapDetector::IterKmers` query-hit stream
that Flye's CPU `quickSeqOverlaps` path actually uses.

## In Scope

- Add an opt-in source-pack extension that captures every non-repetitive query
  k-mer with non-zero `VertexIndex` frequency for selected read-to-graph
  queries.
- Preserve the M6d minimizer-source files for backward compatibility.
- Emit a full query-hit TSV with query position, k-mer representation,
  target edge-sequence id, target position, repetitive flag, and source order.
- Update the M6e replay tool to consume full query hits when present and fall
  back to M6d minimizer bucket hits otherwise.
- Re-run replay against selected toy-hifi queries and target exact
  raw-overlap equality.
- Keep capture opt-in, deterministic, and restricted to `--threads 1`.

## Out of Scope

- No CUDA kernel in M6f.
- No Flye graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patching C++11-compatible and local to the read-to-graph capture
  boundary.
- Use standard containers and RAII file handles only.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or CUDA resource
  APIs.
- Keep generated full-hit source packs under `out/`; commit compact manifests
  only.

## Deliverables

- Source-pack ABI update for full query-hit rows.
- Flye patch extending source-pack capture.
- Replay-tool update preferring full query hits.
- DGX golden manifest under `tests/golden/`.
- Roadmap update naming the first CUDA consumer only if exact replay equality is
  reached or the remaining ledger is narrower than source completeness.

## Acceptance Gates

- [ ] Full query-hit source packs validate and deterministic A/B diff `match`.
- [ ] Replay consumes full query hits and reports exact raw-overlap equality or
      a narrower non-source-completeness ledger.
- [ ] Full Flye canonical artifacts remain unchanged with capture enabled.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
