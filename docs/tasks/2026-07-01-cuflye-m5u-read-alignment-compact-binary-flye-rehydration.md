# Task Card: cuFlye M5u Read Alignment Compact Binary Flye Rehydration

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M5t `compact-binary-v0` payload from standalone proof tooling into a
Flye-side dry-run validation and rehydration seam.

The core question for this card is:

```text
Can Flye request compact-binary-v0 pre-divergence read-alignment chains from
the CUDA session, validate and rehydrate them inside the Flye seam, apply the
existing CPU divergence filter, and still preserve exact artifacts while
failing closed on payload corruption?
```

## In Scope

- Add Flye-side or patch-level parsing for `compact-binary-v0` in the existing
  read-alignment pre-divergence dry-run path.
- Validate magic, version, record size, fixture count, output count, payload
  length, and checksum before rehydration.
- Rehydrate binary records into the same internal pre-divergence chain shape
  currently used by the JSON/TSV proof path.
- Compare GPU-derived `goodChains` against CPU `goodChains` before graph
  mutation.
- Preserve M5t's standalone validator as an external audit tool.

## Out of Scope

- No default GPU mode.
- No broad `_readAlignments` replacement beyond an allowlisted dry-run seam.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib/base-alignment replacement.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrow.
- Use RAII containers and checked bounds before allocation or indexing.
- Do not introduce direct owning `new`, `delete`, `malloc`, `free`, or direct
  CUDA resource ownership outside approved RAII wrappers.
- Unsupported payloads, checksum mismatches, count mismatches, and truncated
  files must fail closed.

## Deliverables

- Flye-side compact binary validation/rehydration implementation.
- ABI note update if Flye-side constraints differ from standalone M5t.
- Positive DGX proof preserving exact artifacts.
- Negative DGX proof for corrupted binary payload before graph mutation.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with Flye-side timing and benefit assessment.

## Acceptance Gates

- [x] Patch series applies and patched Flye builds on DGX.
- [x] CUDA worker builds on DGX.
- [x] Positive Flye dry-run validates and rehydrates `compact-binary-v0`.
- [x] GPU-derived `goodChains` match CPU `goodChains`.
- [x] Positive canonical Flye artifacts match CPU.
- [x] Negative schema/count/checksum/truncation case fails closed before graph
      mutation.
- [x] Local and DGX syntax/style gates pass.
- [x] Ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

Accepted on DGX:

```text
proof_root=/tmp/cuflye-m5u-proof-20260701T041315Z
golden=tests/golden/cuflye-m5u-read-alignment-compact-binary-flye-rehydration-dgx-aarch64.json
last_applied_patch=0035-cuflye-read-alignment-compact-binary-flye-rehydration.patch
selected_query_count=64
compact_binary_mode=rehydrate-v0
positive_status=passed
positive_canonical_diff=match
positive_fixture_count=64
positive_matched_fixture_count=64
positive_worker_actual_wall_ms=2.084782
positive_worker_request_total_ms=0.203472
positive_compact_binary_bytes=5952
positive_compact_binary_sha256=f6dc209fad4311c61396f93ad240f56928557dc0b70f6c947c6991d2f2047504
negative_truncate_status=failed
negative_truncate_error=compact binary payload size mismatch
negative_checksum_status=failed
negative_checksum_error=compact binary checksum mismatch
graph_mutation_consumed_worker_output=false
```

Allowed M5u claim:

```text
cuFlye can request compact-binary-v0 pre-divergence read-alignment chains from
a CUDA session inside Flye, validate and rehydrate that binary payload in the
Flye seam, apply Flye's existing divergence filter, match CPU goodChains for
the selected batch, preserve exact canonical Flye artifacts, and fail closed on
corrupted binary payloads before graph mutation.
```

Forbidden M5u claim:

```text
M5u does not prove default GPU mode, full Flye acceleration, broad
_readAlignments replacement, CUDA minimizer overlap discovery, or replacement
of Flye's CPU divergence/base-alignment stages.
```

Plain-language benefit:

```text
M5u moves the compact binary payload into Flye itself. The GPU worker no longer
needs to write per-read TSV files for this seam; Flye can ask for one binary
file, verify it, rebuild the same goodChains, and keep the assembly
byte-identical. On the same selected batch64 Flye session seam, wall time drops
from M5r's 4.139341 ms to 2.084782 ms, and the worker request_total drops from
2.75092 ms to 0.203472 ms. This is a real integration win, but still not a
whole-Flye speed claim.
```

Next highest-ROI task:

```text
M5v: after the compact-binary-v0 Flye seam validates and matches CPU
goodChains for an allowlisted batch, run a guarded vector-substitution smoke
that feeds the verified GPU-derived goodChains into the selected
_readAlignments slice while preserving exact artifacts and fail-closed
behavior.
```
