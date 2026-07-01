# Task Card: cuFlye M6g Query-Hit Replay Tie Closure

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Close or precisely bound the last M6f full-query-hit replay mismatch by
reproducing Flye's C++ equal-key sorting, DP tie/backtrack behavior, and
primary-overlap containment ordering for query `11` on edge sequence `-3587`.

## In Scope

- Build a focused replay diagnostic for the remaining query `11` / ext `-3587`
  mismatch.
- Compare Python replay match order, DP table, backtrack chains, primary
  overlap selection, and oracle rows.
- If needed, add an opt-in Flye diagnostic dump for the selected ext group only,
  keeping output bounded and deterministic.
- Update replay semantics to match Flye exactly, or record a minimized
  remaining ledger with concrete state-table differences.

## Out of Scope

- No CUDA kernel in M6g.
- No Flye graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Prefer Python diagnostics first; add Flye C++ diagnostics only if the
  remaining ordering behavior cannot be inferred from the source pack.
- Keep any Flye patch C++11-compatible and opt-in.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or CUDA resource
  APIs.

## Deliverables

- Focused replay diagnostic or updated replay implementation under `tools/`.
- Optional Flye diagnostic patch if source-pack evidence is insufficient.
- DGX golden manifest under `tests/golden/`.
- Roadmap update naming the first CUDA full-query-hit consumer if exact replay
  equality is reached.

## Acceptance Gates

- [x] M6f full-query-hit source pack validates before replay.
- [x] Replay reaches row-key `36/36` equality for read/edge coordinates and
      score, with non-key fields reported separately.
- [x] Deterministic replay A/B diff remains `match`.
- [x] Full Flye canonical artifacts remain unchanged for the reused M6f
      diagnostic capture outputs.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented `tools/replay_read_to_graph_source_pack.py` support for replaying
libstdc++ `std::sort` equal-key behavior at the KmerMatch, score-order, and
primary-overlap ordering points used by Flye. This closes the final M6f query
`11` / edge sequence `-3587` row-key mismatch without changing Flye C++ code.

DGX proof:

```text
proof_root=/tmp/cuflye-m6g-proof-20260701T065424Z
golden=tests/golden/cuflye-m6g-query-hit-replay-tie-closure-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
replay_raw_overlaps_sha256=2e1201a2e768ed682afc6b0feb90d50aeeea8ad66597861c6c61ba062a34e420
replay_status=match
row_key_exact_match=true
geometry_match=true
matched_rows=36
missing_rows=0
extra_rows=0
non_key_field_mismatch_rows=36
source_pack_ab_canonical_match=true
replay_ab_raw_overlap_match=true
baseline_vs_source_a=match
baseline_vs_source_b=match
```

Plain-language benefit:

```text
M6g does not make Flye faster yet. Its value is that the last source replay gap
is no longer mysterious: Flye's C++ sort leaves equal-key order unspecified, and
the replay harness now models the libstdc++ behavior well enough to recover all
36 selected raw-overlap row keys. This gives the next CUDA milestone a clean
target: generate the same read/edge coordinates and scores from full query-hit
input, while keeping divergence and edge-id fields in a separate ledger.
```

Next highest-ROI task:

```text
M6h: build the first CUDA full-query-hit replay consumer that emits M6g
row-key-compatible raw-overlap records for the selected source pack, with
unsupported shapes failing closed and no speed claim until parity is proven.
```
