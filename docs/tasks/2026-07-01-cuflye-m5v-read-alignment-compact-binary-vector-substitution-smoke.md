# Task Card: cuFlye M5v Read Alignment Compact Binary Vector Substitution Smoke

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build on M5u by moving from "Flye can validate and rehydrate compact binary
CUDA pre-divergence chains" to a tightly guarded substitution smoke for the
selected read-alignment slice.

The core question for this card is:

```text
After Flye validates compact-binary-v0, applies the existing divergence filter,
and proves GPU-derived goodChains match CPU goodChains for every selected query,
can Flye substitute those verified GPU-derived goodChains into the selected
_readAlignments slice while preserving exact artifacts and failing closed?
```

## In Scope

- Add an explicit opt-in mode for compact-binary pre-divergence vector
  substitution.
- Reuse the M5u parser, checksum/count gates, and CPU goodChains diff.
- Substitute only allowlisted selected-query chains after all selected fixtures
  pass validation.
- Preserve exact canonical Flye artifacts versus CPU on the toy-hifi selected
  batch.
- Add a negative proof that blocks substitution before graph mutation when any
  selected fixture mismatches or the compact binary is corrupt.

## Out of Scope

- No default GPU mode.
- No unbounded `_readAlignments` replacement.
- No CUDA minimizer overlap discovery.
- No replacement of Flye's CPU divergence/base-alignment stages.
- No performance claim outside the selected read-alignment slice.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrow.
- Keep the new substitution switch fail-closed and disabled by default.
- Use existing RAII containers and checked bounds; do not add direct owning
  `new`, `delete`, `malloc`, `free`, or CUDA resource ownership.
- Record audit fields that distinguish validation, comparison, and actual
  vector substitution.

## Deliverables

- Flye patch extending M5u compact-binary rehydration into guarded selected
  vector substitution.
- Positive DGX proof preserving exact artifacts.
- Negative DGX proof that blocks substitution before graph mutation.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a scoped benefit assessment.

## Acceptance Gates

- [x] Patch series applies and patched Flye builds on DGX.
- [x] CUDA worker builds on DGX.
- [x] Positive compact-binary vector substitution reports all selected fixtures
      validated and substituted.
- [x] Canonical Flye artifacts match CPU.
- [x] Negative mismatch/corruption case fails closed before graph mutation.
- [x] Audit JSON records `graph_mutation_consumed_worker_output=true` only for
      the positive, validated substitution path.
- [x] Local and DGX syntax/style gates pass.
- [x] Ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

Accepted on DGX:

```text
proof_root=/tmp/cuflye-m5v-proof-20260701T042828Z
golden=tests/golden/cuflye-m5v-read-alignment-compact-binary-vector-substitution-smoke-dgx-aarch64.json
last_applied_patch=0036-cuflye-read-alignment-compact-binary-vector-substitution-smoke.patch
selected_query_count=64
compact_binary_mode=rehydrate-v0
compact_binary_vector_substitution_mode=verified-goodchains-v0
positive_status=passed
positive_canonical_diff=match
positive_matched_fixture_count=64
positive_total_substituted_chains=64
positive_graph_mutation_consumed_worker_output=true
positive_worker_actual_wall_ms=2.080723
positive_worker_request_total_ms=1.511474
positive_compact_binary_sha256=f6dc209fad4311c61396f93ad240f56928557dc0b70f6c947c6991d2f2047504
negative_mismatch_status=failed
negative_mismatch_graph_mutation_consumed_worker_output=false
negative_truncate_status=failed
negative_truncate_graph_mutation_consumed_worker_output=false
```

Allowed M5v claim:

```text
cuFlye can substitute verified compact-binary-v0 CUDA-derived read-alignment
goodChains into the selected _readAlignments slice inside Flye, preserve exact
canonical artifacts, and fail closed before graph mutation on mismatch or
corrupted compact binary payloads.
```

Forbidden M5v claim:

```text
M5v does not prove default GPU mode, full Flye acceleration, unbounded
_readAlignments replacement, CUDA minimizer overlap discovery, or a new speedup
over M5u.
```

Plain-language benefit:

```text
M5v is the first time this compact-binary path actually feeds verified
GPU-derived goodChains back into Flye's selected _readAlignments slice. It keeps
the assembly byte-identical and proves mismatch or corrupted binary payloads do
not get consumed. It does not add a meaningful speedup over M5u by itself; the
benefit is safety-gated consumption, which is the prerequisite for scaling the
GPU path beyond a dry-run.
```

Next highest-ROI task:

```text
M5w: scale the compact-binary vector-substitution seam from the selected
batch64 proof to the full3546 selected read-alignment fixture set, preserve
exact artifacts, and measure whether the broader Flye-side substitution path
keeps the CUDA integration advantage.
```
