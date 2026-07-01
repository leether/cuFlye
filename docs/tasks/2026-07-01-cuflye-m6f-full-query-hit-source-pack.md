# Task Card: cuFlye M6f Full Query-Hit Source Pack

Status: accepted

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

- [x] Full query-hit source packs validate and deterministic A/B diff `match`.
- [x] Replay consumes full query hits and reports exact raw-overlap equality or
      a narrower non-source-completeness ledger.
- [x] Full Flye canonical artifacts remain unchanged with capture enabled.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Accepted with DGX proof:

- Golden manifest:
  `tests/golden/cuflye-m6f-full-query-hit-source-pack-dgx-aarch64.json`
- Proof root: `/tmp/cuflye-m6f-proof-20260701T064116Z`
- Host: `edgexpert-45d2`, `aarch64`
- Fixture: `toy-hifi`
- Patch series: Flye 2.9.6 plus patches `0001..0041`
- Source-pack canonical SHA-256:
  `16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f`
- Full query-hit records: `7747`
- Replay source mode: `full-query-hits`
- Replay status: `gap-ledger`
- Replay SHA-256:
  `1be41bf42fecd4c1af40eb516ee7377afdcce20a2c7bfdd52fdaccb0cdeb3e6c`
- Replay determinism: source-pack A/B replay diff `match`
- Replay improvement over M6e: exact rows improved from `14/36` to `35/36`;
  geometry rows improved from `26/36` to `35/36`.
- Remaining mismatch: query `11`, edge sequence `-3587`; one oracle row is
  missing and three extra replay rows are emitted.
- Flye artifact diffs from baseline to both full-hit capture runs: `match`

Plain-language benefit:

M6f still does not accelerate Flye, but it proves the M6e diagnosis was right.
Once we capture the full query-hit stream Flye actually uses, replay jumps from
`14/36` exact rows to `35/36`. That is a large semantic closure step and a good
engineering payoff: the remaining issue is no longer missing source data, but a
very narrow C++ ordering/tie-breaking behavior around one query. CUDA work
should still wait until M6g closes or explicitly bounds that last mismatch.
