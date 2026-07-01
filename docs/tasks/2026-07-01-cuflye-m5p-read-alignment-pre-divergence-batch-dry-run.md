# Task Card: cuFlye M5p Read Alignment Pre-Divergence Batch Dry Run

Status: planned

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Reduce the M5o per-selected-read worker process overhead by moving CUDA
pre-divergence read-alignment chain output to a batch or persistent dry-run
seam. The milestone should keep Flye artifacts unchanged while proving that a
supported selected-read batch can produce the same post-divergence `goodChains`
as CPU after Flye applies its existing divergence filter.

The core question this card must answer is:

```text
Can the M5o pre-divergence Flye dry-run boundary be batched or kept warm so the
integration path becomes cheaper than per-read process startup?
```

## In Scope

- Add an opt-in batch or persistent mode for pre-divergence chain output.
- Keep unsupported shapes fail-closed.
- Reuse the M5o selected-read audit JSON fields where possible.
- Compare GPU-produced, Flye-filtered goodChains against CPU goodChains for
  every selected read.
- Preserve exact canonical Flye artifacts against a CPU baseline.
- Record timing that separates worker process/session overhead from CUDA core
  and output materialization.

## Out of Scope

- No default GPU mode.
- No broad `_readAlignments` replacement unless a separate verified gate is
  defined in a later card.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib replacement.
- No end-to-end acceleration claim unless measured proof shows it.

## C++/CUDA Style Constraints

- Keep Flye patch C++11-compatible.
- Follow `docs/CODING_STYLE.md` ownership rules.
- Do not introduce direct owning `new` or `delete`, `malloc`/`free`, or direct
  CUDA resource ownership in Flye code.
- Keep worker resource ownership inside existing RAII wrappers.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- Task-specific ABI note if the batch/persistent contract differs from M5o.
- CUDA worker support for the selected batch/persistent pre-divergence mode.
- Flye-side guarded dry-run seam or worker adapter changes.
- Runner flags and metadata for the new mode.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with scoped benefit and next step.
- Plain-language CUDA benefit assessment.

## Acceptance Gates

- [ ] Patch series applies and patched Flye builds on DGX.
- [ ] CUDA read-alignment replay binary builds on DGX.
- [ ] Positive selected-read batch invokes CUDA pre-divergence chain output.
- [ ] Positive run records per-query post-divergence goodChain matches.
- [ ] Positive run preserves exact canonical Flye artifacts versus CPU.
- [ ] Timing separates process/session overhead, CUDA core, and output copy.
- [ ] Negative mismatch or unsupported-shape proof fails closed.
- [ ] Local syntax/style gates pass.
- [ ] C++/CUDA ownership scan shows no new direct owning heap APIs.

## Completion Notes

Pending implementation and DGX proof.

Allowed M5p claim:

```text
Pending proof.
```

Forbidden M5p claim:

```text
M5p does not prove default GPU mode, broad _readAlignments replacement, CUDA
minimizer overlap discovery, CPU divergence replacement, or end-to-end Flye
acceleration unless the measured proof explicitly demonstrates it.
```
