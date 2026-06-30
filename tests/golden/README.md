# Golden Manifests

This directory stores small, reviewable golden manifests for oracle fixtures.

Do not commit full Flye run directories, generated assemblies, BAM/SAM files, or
profiler dumps here. Store compact manifests, canonical hashes, and summary
proof only.

Accepted fixtures:

- `toy-hifi`: upstream Flye E. coli 500 kb HiFi toy fixture from
  `upstream-flye/flye/tests/data/ecoli_500kb_reads_hifi.fastq.gz`.
  - Manifest: `toy-hifi-dgx-aarch64.json`
  - Candidate oracle manifest: `toy-hifi-candidate-dgx-aarch64.json`
  - Candidate backend seam manifest: `toy-hifi-backend-dgx-aarch64.json`
  - Candidate ABI manifest: `toy-hifi-candidate-abi-dgx-aarch64.json`
  - CUDA backend stub manifest: `toy-hifi-cuda-stub-dgx-aarch64.json`

ABI proof manifests use the same fixture and must reference compact validator
summaries, not full candidate TSV files.

CUDA runtime proof:

- Runtime probe manifest: `cuda-runtime-probe-dgx-aarch64.json`

CUDA candidate smoke proof:

- Candidate smoke manifest: `cuda-candidate-smoke-dgx-aarch64.json`

CUDA k-mer join smoke proof:

- K-mer join smoke manifest: `cuda-kmer-join-smoke-dgx-aarch64.json`

CUDA k-mer encode smoke proof:

- K-mer encode smoke manifest: `cuda-kmer-encode-smoke-dgx-aarch64.json`

CUDA read-window smoke proof:

- Read-window smoke manifest: `cuda-read-window-smoke-dgx-aarch64.json`

CUDA candidate-core benchmark proof:

- Candidate-core benchmark manifest: `cuda-candidate-core-bench-dgx-aarch64.json`

CUDA RAII resource-layer proof:

- CUDA RAII resource-layer manifest: `cuda-raii-resource-layer-dgx-aarch64.json`

M2 real-pack CUDA consumer proof:

- Real-pack CUDA consumer manifest:
  `cuflye-m2c-real-pack-cuda-consumer-dgx-aarch64.json`

M3 long-lived CUDA worker proof:

- Long-lived worker manifest:
  `cuflye-m3b-long-lived-cuda-worker-dgx-aarch64.json`
- Device prefix compaction manifest:
  `cuflye-m3c-device-prefix-compaction-dgx-aarch64.json`
- Worker device-buffer arena manifest:
  `cuflye-m3d-worker-device-buffer-arena-dgx-aarch64.json`
- Sampled pack batch planner manifest:
  `cuflye-m3e-sampled-pack-batch-planner-dgx-aarch64.json`

M4 overlap-range oracle proof:

- Overlap-range CPU oracle manifest:
  `cuflye-m4a-overlap-range-oracle-dgx-aarch64.json`
- Overlap-chain replay manifest:
  `cuflye-m4b-overlap-chain-replay-dgx-aarch64.json`
- CUDA overlap-chain DP prototype manifest:
  `cuflye-m4c-cuda-overlap-chain-dp-dgx-aarch64.json`
- Overlap-chain hotpath benchmark manifest:
  `cuflye-m4d-overlap-chain-hotpath-benchmark-dgx-aarch64.json`
- Overlap-chain parallel-reduction manifest:
  `cuflye-m4e-overlap-chain-parallel-reduction-dgx-aarch64.json`
- Overlap-chain batched-fixtures manifest:
  `cuflye-m4f-overlap-chain-batched-fixtures-dgx-aarch64.json`
- Batched overlap worker manifest:
  `cuflye-m4g-batched-overlap-worker-dgx-aarch64.json`
- Packed multi-query overlap kernel manifest:
  `cuflye-m4h-packed-multi-query-overlap-kernel-dgx-aarch64.json`
- Packed overlap worker protocol manifest:
  `cuflye-m4i-packed-overlap-worker-protocol-dgx-aarch64.json`
