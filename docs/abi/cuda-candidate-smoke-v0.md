# cuFlye CUDA Candidate Smoke Prototype v0

Status: active

Introduced: M1f

Scope: standalone CUDA kernel that emits a small candidate-record-v1 compatible
TSV from a CPU oracle sample.

## Purpose

M1f proves the first CUDA candidate-output path. It does not implement Flye's
k-mer lookup yet. Instead, it reads a small CPU candidate oracle sample, copies
candidate records through a CUDA kernel, writes the GPU-produced records as
candidate-record-v1 TSV, and compares that TSV against the CPU sample.

This establishes the ABI handoff before moving real candidate generation logic
to the GPU.

## Binary

Source:

```text
cuda/cuflye_cuda_candidate_smoke.cu
```

Build:

```sh
scripts/build_cuda_candidate_smoke.sh --arch sm_121
```

Default output:

```text
out/m1f/bin/cuflye-cuda-candidate-smoke
```

## Runtime Contract

Required arguments:

- `--input-cpu-tsv PATH`: CPU oracle candidate dump;
- `--output-tsv PATH`: GPU-produced candidate-record-v1 TSV.

Optional arguments:

- `--cpu-sample-output PATH`: write the exact CPU sample used for diffing;
- `--records N`: number of records to sample, default `128`;
- `--device N`: CUDA device id, default from `CUFLYE_CUDA_DEVICE` or `0`;
- `--memory-budget-bytes N`: maximum allowed device allocation;
- `--json-output PATH`: compact runtime manifest.

The prototype must:

- parse CPU candidate-record-v1 rows into fixed-width structs;
- allocate device input and output buffers;
- launch a CUDA kernel that emits output structs;
- serialize the GPU output to candidate-record-v1 TSV;
- preserve duplicates and field values exactly;
- fail if requested device allocation exceeds the memory budget;
- report `memory_budget_satisfied`;
- pass `tools/validate_candidate_dump.py`;
- pass `tools/diff_candidate_dumps.py` against the CPU sample.

## Non-Goals

M1f does not:

- build Flye's vertex index on GPU;
- perform GPU k-mer lookup;
- change Flye backend behavior;
- claim performance improvement.

The only correctness claim is that a CUDA kernel can emit ABI-valid candidate
records that match a CPU oracle sample.
