# Task Card: cuFlye M5h Larger Read Alignment Fixture Harvest

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Increase the amount of real read-alignment replay work sent through the M5g
persistent CUDA arena before any graph-consumption integration.

The core question this card must answer is:

```text
Does a larger real read-alignment fixture harvest improve the persistent CUDA
arena result while preserving every per-read oracle diff?
```

## Background

M5g proved that reusable per-shape CUDA arenas reduce grouped CUDA overhead:
the persistent path was `2.310763x` faster than the cold grouped CUDA path on
the 68-read toy-hifi fixture set. That batch was still only `141` total input
records, so CPU remained much faster.

M5h expands the real fixture harvest and makes fixture selection
machine-checkable. The goal is not to change Flye semantics; it is to find out
whether more real read-alignment work makes the persistent CUDA path more
competitive.

## In Scope

- Add a deterministic read-alignment fixture selection/summarization tool.
- Harvest a wider real query-id range on DGX using the existing M5e replay dump
  protocol.
- Select all valid replay fixtures, grouped by the existing CUDA shape key.
- Run CPU, cold CUDA, and persistent CUDA batch benchmarks on the selected
  larger harvest.
- Validate every CPU, cold CUDA, and persistent CUDA per-fixture output as
  `read-alignment-v1`.
- Canonical-diff every selected output against the fixture oracle.
- Compare persistent CUDA against both cold CUDA and CPU.
- Record whether the larger batch changes the CUDA benefit conclusion.

## Out of Scope

- No Flye graph mutation consumption.
- No default GPU mode.
- No long-lived external read-alignment worker yet.
- No edlib/base realignment replay beyond recorded divergence acceptance flags.
- No end-to-end Flye acceleration claim.

## C++/CUDA/Python Style Constraints

- Do not change CUDA kernel semantics in this card unless the proof shows the
  larger harvest still cannot exercise enough work.
- Keep standalone CUDA code CUDA C++14 if touched.
- Keep Python tooling deterministic, typed where useful, and compatible with
  the existing `tools/` style.
- Do not introduce direct C++/CUDA resource ownership APIs outside RAII
  wrappers.
- Unsupported or malformed fixtures must fail closed with a clear reason.

## Deliverables

- `tools/select_read_alignment_fixture_batch.py`
- DGX proof manifest under `tests/golden/`
- Updated roadmap and golden index
- Plain-language CUDA benefit assessment

## Acceptance Gates

- [x] Deterministic fixture selector scans a replay fixture root and writes a
      fixture list plus shape summary.
- [x] Wider DGX harvest creates more selected total input records than M5g's
      `141`.
- [x] CUDA replay binary builds on DGX.
- [x] CPU, cold CUDA, and persistent CUDA batch runs complete on the selected
      larger fixture list.
- [x] Every selected output validates as `read-alignment-v1`.
- [x] CPU, cold CUDA, and persistent CUDA outputs canonical-diff `match`
      against every fixture oracle.
- [x] Persistent CUDA outputs canonical-diff `match` against cold CUDA outputs.
- [x] Persistent CUDA timing is compared against cold CUDA and CPU.
- [x] Local syntax/style gates pass.
- [x] CUDA ownership scan shows no new direct resource APIs outside RAII
      wrappers.

## Completion Notes

Accepted with DGX proof:

- Proof root:
  `/tmp/cuflye-m5h-proof-20260630T234728Z`
- Golden manifest:
  `tests/golden/cuflye-m5h-larger-read-alignment-fixture-harvest-dgx-aarch64.json`
- Host: `edgexpert-45d2`, `aarch64`, GPU `NVIDIA GB10`, compute capability
  `12.1`
- Wider harvest: toy-hifi query ids `1..6000`
- Discovered fixture directories: `3577`
- Valid selected fixtures: `3546`
- Invalid/excluded fixtures: `31`, all due to empty `read-alignment-v1` oracle
  dumps.
- Selected shape groups: `4`
- Selected total input records: `3781`
- Selected total oracle records: `3616`
- M5g baseline total input records: `141`

Selected shape distribution:

```text
input_records=1: fixture_count=3418, total_input_records=3418, total_oracle_records=3418
input_records=2: fixture_count=29,   total_input_records=58,   total_oracle_records=45
input_records=3: fixture_count=91,   total_input_records=273,  total_oracle_records=129
input_records=4: fixture_count=8,    total_input_records=32,   total_oracle_records=24
```

Warm benchmark timing with `5` warmups and `50` timed runs:

```text
cpu_mean_total_before_json_ms=0.332580
cpu_mean_core_ms=0.332580
cold_cuda_mean_total_before_json_ms=18.270376
cold_cuda_mean_kernel_ms=0.048954
persistent_cuda_mean_total_before_json_ms=18.301868
persistent_cuda_mean_kernel_ms=0.026174
persistent_cuda_speedup_vs_cold_cuda=0.998279x
persistent_cuda_speedup_vs_cpu=0.018172x
persistent_cuda_slowdown_vs_cpu=55.029972x
persistent_cuda_core_speedup_vs_cpu=12.706503x
persistent_cuda_core_speedup_vs_cold_cuda=1.870329x
persistent_cuda_device_to_host_ms=18.156663
```

Every CPU, cold CUDA, persistent CUDA, and oracle per-fixture
`read-alignment-v1` output validated and canonical-diffed as `match`.

Allowed M5h claim:

```text
cuFlye can expand read-alignment replay proof from 68 toy-hifi fixtures to a
wider 3546-fixture harvest and run the persistent CUDA arena while preserving
every per-read oracle diff.
```

Forbidden M5h claim:

```text
M5h does not prove default GPU mode, graph mutation consumption, edlib/base
realignment replay, end-to-end Flye acceleration, or CPU-beating
read-alignment speed.
```

Plain-language benefit assessment:

```text
This step gives us a much better diagnosis, not a user-visible speedup. The
CUDA kernel/core part is now faster than CPU core work, but total CUDA time is
still dominated by thousands of tiny device-to-host/output copies. The next
high-ROI CUDA change is bulk output transfer or device-side compaction, not
more small fixture harvesting.
```
