# Task Card: cuFlye M5q Read Alignment Pre-Divergence Batch Crossover

Status: planned

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Use the M5p batch dry-run seam to find the selected-read batch size and shape
mix where CUDA pre-divergence chain generation is meaningfully better than the
CPU replay baseline after accounting for worker setup, output copy, and Flye
integration overhead.

The core question this card must answer is:

```text
How large must the selected read-alignment batch be before the CUDA path's core
speed can overcome process/CUDA setup overhead, and what is the next engineering
target if it cannot?
```

## In Scope

- Reuse the M5p `batch-dry-run-v0` Flye seam.
- Build larger deterministic selected-read allowlists from existing toy-hifi or
  harvested M5h fixtures.
- Compare CUDA batch timing against CPU pre-divergence replay timing for the
  same fixture set.
- Preserve exact canonical Flye artifacts against CPU baseline for any Flye-side
  positive run.
- Record whether `setup`, `kernel`, `device_to_host`, `write_output`, or Flye
  integration wall time dominates.

## Out of Scope

- No default GPU mode.
- No `_readAlignments` replacement from pre-divergence output.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib replacement.
- No production speedup claim unless measured proof demonstrates it.

## C++/CUDA Style Constraints

- Prefer scripts/proof harness changes before new C++ code.
- If C++ changes are needed, keep Flye patches C++11-compatible.
- Follow `docs/CODING_STYLE.md` ownership rules.
- Do not introduce direct owning `new` or `delete`, `malloc`/`free`, or direct
  CUDA resource ownership.
- CUDA paths must fail closed on unsupported shapes.

## Deliverables

- Deterministic selected-read batch/crossover proof script or documented command
  sequence.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with measured crossover or blocker.
- Plain-language CUDA benefit assessment.

## Acceptance Gates

- [ ] Patch series applies and patched Flye builds on DGX.
- [ ] CUDA read-alignment replay binary builds on DGX.
- [ ] At least one larger selected-read batch positive run passes M5p per-query
      goodChain checks.
- [ ] Positive run preserves exact canonical Flye artifacts versus CPU.
- [ ] CPU and CUDA pre-divergence replay timing are measured on the same fixture
      list.
- [ ] Timing report separates setup, CUDA core, output copy, write output, and
      Flye integration wall time.
- [ ] Local syntax/style gates pass.
- [ ] C++/CUDA ownership scan shows no new direct owning heap APIs.

## Completion Notes

Pending implementation and DGX proof.

Allowed M5q claim:

```text
Pending proof.
```

Forbidden M5q claim:

```text
M5q must not claim full Flye acceleration unless the measured Flye-side run
demonstrates it against a CPU baseline with unchanged artifacts.
```
