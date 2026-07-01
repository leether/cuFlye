# Task Card: cuFlye M5r Read Alignment Pre-Divergence Persistent Session

Status: planned

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M5q hot-path result into a Flye-facing integration improvement by
removing repeated CUDA context/process setup from selected read-alignment
pre-divergence batches.

The core question this card must answer is:

```text
Can Flye submit selected pre-divergence read-alignment batches to a long-lived
CUDA worker/session and preserve exact artifacts while reducing selected-batch
worker wall time versus M5q's fresh-process batch worker?
```

## In Scope

- Reuse the M5p/M5q `batch-dry-run-v0` correctness contract.
- Define a minimal read-alignment pre-divergence session protocol, preferably
  file-backed JSONL or another repo-native external-worker boundary.
- Keep CUDA context and persistent arena alive across more than one selected
  batch request inside the proof.
- Compare session request timing against M5q fresh worker timing for the same
  selected query set or a deterministic larger set.
- Preserve exact canonical Flye artifacts against CPU baseline.
- Fail closed on worker mismatch, missing response, unsupported shape, timeout,
  or session lifecycle failure.

## Out of Scope

- No default GPU mode.
- No `_readAlignments` replacement from pre-divergence output.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib replacement.
- No production speedup claim unless the measured Flye-side session run proves
  it against a CPU baseline with unchanged artifacts.

## C++/CUDA Style Constraints

- Keep Flye patches C++11-compatible and narrow.
- Follow `docs/CODING_STYLE.md` ownership rules.
- Do not introduce direct owning `new` or `delete`, `malloc`/`free`, or direct
  CUDA resource ownership.
- Reuse existing CUDA RAII wrappers for any reusable CUDA resource.
- Session output ordering must remain deterministic and machine-diffable.
- Unsupported shapes must fail closed; silent CPU fallback is not allowed.

## Deliverables

- Session protocol documentation or ABI note.
- Worker/session implementation or proof shell that keeps CUDA setup warm across
  selected pre-divergence batch requests.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with measured session timing versus M5q fresh worker timing.
- Plain-language CUDA benefit assessment.

## Acceptance Gates

- [ ] Patch series applies and patched Flye builds on DGX.
- [ ] CUDA read-alignment session worker builds on DGX.
- [ ] Positive Flye session run passes M5p per-query goodChain checks.
- [ ] Positive Flye session run preserves exact canonical artifacts versus CPU.
- [ ] Session request timing is measured separately from one-time session setup.
- [ ] Selected-batch worker/request timing improves versus M5q fresh-process
      batch worker for a comparable selected query set.
- [ ] Negative mismatch or lifecycle fault fails closed before graph mutation.
- [ ] Local and DGX syntax/style gates pass.
- [ ] C++/CUDA ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

Pending implementation and DGX proof.

Allowed M5r claim:

```text
Pending proof.
```

Forbidden M5r claim:

```text
M5r must not claim default GPU mode or full Flye acceleration unless the
measured Flye-side session run demonstrates it against a CPU baseline with
unchanged artifacts.
```
