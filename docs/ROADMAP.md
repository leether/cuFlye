# cuFlye CUDA-enabled Flye Roadmap

Status: active

Last updated: 2026-07-01

## North Star

cuFlye is a Flye-compatible CUDA acceleration project, not a replacement
assembler. The goal is:

```text
Keep Flye's CLI, stage contracts, intermediate artifacts, and CPU behavior as
the oracle while moving selected hotspot kernels to CUDA.
```

CPU Flye remains the default until the CUDA path passes deterministic parity
gates. `--gpu` must be opt-in, auditable, and able to fail closed or fall back
to CPU on unsupported shapes.

## Non-Negotiable Rules

- Do not claim "GPU Flye is faster" until an integrated Flye stage passes both
  parity and wall-time gates.
- Do not feed GPU output into downstream Flye graph logic until candidate-list
  equivalence against the CPU oracle is machine-checked.
- Do not silently fall back from CUDA to CPU; fallback must be explicit in
  metadata.
- Do not optimize by changing scientific semantics: k-mer encoding, standard
  form, repetitive filters, trivial-hit filters, ordering contracts, chaining
  penalties, and graph artifacts must remain compatible.
- Do not commit large generated outputs. Commit compact manifests, hashes, and
  proof summaries.

## Evidence Ladder

Each rung must be complete before the next one is allowed to make a stronger
claim.

| Rung | Claim allowed | Required proof |
| --- | --- | --- |
| Correctness fixture | Kernel emits ABI-valid records on a bounded fixture. | `validate_candidate_dump.py` and candidate diff pass. |
| Semantic fixture | Kernel implements one more Flye semantic unit. | CPU oracle, expected fixture, and GPU output match. |
| Core benchmark | CUDA is faster for a bounded subproblem. | CPU/GPU counts match and total CUDA time beats CPU. |
| Backend parity | CUDA backend can replace a CPU kernel boundary. | Candidate or overlap dumps match CPU oracle on fixtures. |
| Stage parity | A Flye stage is GPU-accelerated. | Canonical intermediate artifacts match CPU deterministic mode. |
| Product claim | `flye --gpu` is useful. | End-to-end wall time improves on target datasets with compatibility matrix. |

## Current State

Completed:

- M0: CPU oracle, canonical diff, and profiling harness.
- M1a-M1c: candidate dump oracle, backend seam, and candidate-record ABI.
- M1d-M1e: CUDA backend stub and CUDA runtime probe.
- M1f: CUDA can emit candidate-record-v1 output from a CPU sample.
- M1g: CUDA can generate candidates from query/index lookup-key fixtures.
- M1h: CUDA can compute Flye-style 2-bit k-mers, reverse complements, and
  standard-form lookup keys from DNA k-mer strings.
- M1i: CUDA can slide bounded read windows and generate query k-mers before
  candidate equality join.
- M1j: CUDA candidate equality-scan core is faster than CPU on DGX:
  268,435,456 pair comparisons, matched count 65,536, CUDA total best
  1.272772 ms vs CPU best 68.864532 ms, 54.105945x total speedup.
- M2a: Flye's CUDA candidate backend selector now reaches a real external
  packed adapter shell, invokes CUDA on a bounded fixture, validates
  candidate-record-v1 output, and fails closed for unsupported real Flye
  shapes.
- M2b: Flye can extract a real query and relevant `VertexIndex` buckets into a
  replayable packed candidate-backend bundle with per-query CPU candidate
  oracle output, then fail closed before downstream graph logic.
- M2c: CUDA read-window backend can consume the M2b real pack with dynamic
  read-base storage and reproduce the Flye CPU candidate list: 15,571 records,
  canonical SHA-256
  `5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`.
- M2d-M2f: Flye can invoke the external packed CUDA backend at one real query
  boundary, stop before downstream graph mutation, and record sparse-output
  timing against the CPU oracle.
- M3a: the integration path is the long-lived external CUDA worker, not
  in-process CUDA inside Flye.
- M3b: the long-lived worker keeps CUDA context warm across repeated requests:
  warm backend total before JSON `132.110 ms`.
- M3c: device-side prefix compaction removes full host prefix/offset
  materialization: warm backend total before JSON `28.330 ms`, candidate diff
  `match`.
- M3d: worker-side reusable device buffers remove stable-shape allocation
  churn: warm backend total before JSON `18.643 ms`, warm device allocation
  `0.001 ms`, arena allocations `0`, arena reuses `7`, candidate diff `match`.
- M3e: sampled real-pack batch planning derives four heterogeneous request
  shapes from the M2b `query_neg253` pack, orders them by estimated pair count,
  runs them in one CUDA worker process, and preserves candidate-list
  equivalence for every sample. Warm sampled requests reuse the worker arena
  with zero new allocations, and the best warm worker request is `41.08x`
  faster than its sampled CPU oracle.
- M4a: `overlap-range-v1` defines Flye CPU overlap-range records after
  `OverlapDetector::getSeqOverlaps`, and DGX toy runs produce deterministic
  oracle dumps: `53,728` records per run, canonical SHA-256
  `71477479f412c90463aa60d8565b52da10f9dfec98d96387525ed50ae937c22b`,
  canonical diff `match`.
- M4b: `overlap-replay-fixture-v0` captures a bounded raw-read candidate chain
  fixture and the CPU replay tool reproduces Flye's overlap oracle for query
  `-71`: `7,859` candidate records, `51` overlap records, canonical
  overlap SHA-256
  `1a3347f96c74e0297a80871b32fa6cce2bccbf2731a7facb95e9333185c23e73`,
  canonical diff `match`.
- M4c: a standalone CUDA overlap-chain DP prototype consumes the M4b
  supported fixture and reproduces the CPU replay oracle at `overlap-range-v1`:
  `7,859` candidate records, `120` target groups, `51` overlap records,
  canonical overlap SHA-256
  `1a3347f96c74e0297a80871b32fa6cce2bccbf2731a7facb95e9333185c23e73`,
  canonical diff `match`. The single-fixture CUDA kernel time was
  `4.80657 ms` on DGX `NVIDIA GB10`.
- M4d: a fair C++ CPU baseline and warm CUDA benchmark reproduce the same
  M4b oracle, but the current CUDA hotpath is slower for this small single-query
  fixture: CPU mean hotpath `2.330413 ms`, CUDA mean hotpath `4.721515 ms`,
  CUDA speedup vs CPU `0.493573x`, CUDA slowdown vs CPU `2.026042x`.
- M4e: an explicit `parallel-reduce` CUDA kernel mode preserves exact
  `overlap-range-v1` output but is still slower on the single supported
  fixture: CPU mean hotpath `1.317636 ms`, serial CUDA `4.742383 ms`,
  parallel-reduce CUDA `5.794421 ms`; parallel-reduce speedup vs CPU
  `0.227397x`.
- M4f: multi-fixture replay capture is available through
  `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES`; a toy-raw run captured `100` fixture
  directories, including `50` supported-shape fixtures. Python replay matched
  `46` and mismatched `4`. A clean top-9 real replay-match batch diff-matched
  for CPU, serial CUDA, and parallel CUDA, but per-fixture CUDA invocation was
  still slower: CPU `12.300116 ms`, serial CUDA `38.801200 ms`, parallel CUDA
  `47.293990 ms`.
- M4g: a single-process batched overlap worker validates the same top-9
  replay-match fixtures while reusing CUDA context and device buffers. All CPU,
  serial CUDA, and parallel CUDA fixture outputs validate as `overlap-range-v1`
  and canonical-diff `match`. Arena reuse was recorded with `9` allocations,
  `369` reuses, and `492552` bytes of final capacity. The worker slightly
  improves CUDA overhead compared with M4f external invocation, but it is still
  slower than CPU: CPU `9.217960 ms`, serial CUDA `36.781822 ms`, parallel CUDA
  `45.264240 ms`.
- M4h: packed multi-query overlap-chain replay validates the same top-9
  replay-match fixtures while reducing CUDA launches from `9` per timed run to
  `1`. Packed serial CUDA preserves every `overlap-range-v1` oracle hash and is
  faster than the CPU replay batch on DGX: CPU `14.977639 ms`, packed serial
  CUDA `6.906646 ms`, speedup vs current CPU `2.168584x`, and speedup vs the
  M4g CPU baseline `1.334651x`.
- M4i: packed overlap-chain replay now has an overlap-specific file-backed
  worker protocol. Two supported packed serial worker requests round-tripped in
  one process, the second request reported warm context, reused the CUDA arena
  with `0` allocations and `161` reuses, and every output preserved the M4h
  oracle hashes. An unsupported request wrote `status=error` and exited with
  code `1`.
- M4j: Flye can explicitly generate a packed overlap worker request at a
  bounded replay fixture boundary, invoke the CUDA overlap worker, record the
  response, and stop before graph mutation. The DGX proof captured raw-read
  query `-71`, produced `51` worker overlap records, validated
  `overlap-range-v1`, canonical-diffed `match` against the Flye CPU oracle, and
  preserved default `toy-hifi` CPU artifact hashes against the M0 golden set.
- M4k: Flye can collect an explicit replay-match query-id allowlist, generate
  one packed CUDA overlap worker request for the captured batch, and still stop
  before graph mutation. The DGX proof captured 9 allowlisted raw-read queries,
  produced `382` total worker overlap records, validated every worker output as
  `overlap-range-v1`, canonical-diffed every output `match` against the Flye CPU
  oracle, and preserved default `toy-hifi` CPU artifact hashes against the M0
  golden set. The Flye-generated packed worker request reported
  `6.84245 ms` backend mean total before write versus the M4h CPU replay batch
  baseline `14.977639 ms`, a bounded replay speedup of `2.188929x`.
- M4l: Flye can validate packed CUDA overlap worker output before marking it
  consumption-eligible. The DGX positive proof validated all 9 worker TSVs as
  `overlap-range-v1`, canonical-diffed every output `match` against its CPU
  oracle, wrote `worker_output_consumption_eligible=true`, and still recorded
  `graph_mutation_consumed_worker_output=false`. The DGX negative proof ran the
  real worker through a wrapper that removed one overlap record from `query_381`;
  Flye validation caught the mismatch, wrote
  `status=validation-failed-before-graph-mutation`, marked
  `worker_output_consumption_eligible=false`, and exited non-zero before graph
  mutation.
- M4m: Flye can parse validated packed CUDA overlap worker output back into a
  Flye-side canonical shadow overlap representation and compare it against CPU
  overlap ranges captured in memory. The DGX positive proof shadow-compared all
  9 top-batch worker outputs `match`, wrote `shadow_consumption_eligible=true`,
  and still recorded `graph_mutation_consumed_worker_output=false`. The DGX
  negative proof corrupted both the first worker output TSV and its disk oracle,
  so file validation still passed; shadow comparison caught `query_neg71` as
  `51` CPU records versus `50` worker records, wrote
  `status=shadow-failed-before-graph-mutation`, and exited non-zero before graph
  mutation.
- M4n: the validation and shadow-consumption proof now covers a deterministic
  heterogeneous supported-shape matrix instead of only the fixed top-9 batch.
  A DGX toy-raw scan captured `227` replay fixtures; the selector found `96`
  supported replay-match fixtures, explicitly excluded `120` unsupported shapes
  and `11` replay mismatches, then selected `12` fixtures spanning candidate
  records `327` to `8372`, target groups `18` to `231`, overlap records `4` to
  `60`, and overlap density `0.0026367831245880024` to
  `0.027848101265822784`. The positive proof validated and shadow-compared all
  `12` selected worker outputs `match`, wrote
  `shadow_consumption_eligible=true`, and kept
  `graph_mutation_consumed_worker_output=false`. The negative proof corrupted
  both worker TSV and disk oracle for `query_353`; validation still passed, but
  shadow comparison caught `8` CPU records versus `7` worker records and failed
  closed before graph mutation.
- M4o: Flye now has an explicit graph-consumption guard dry-run for packed CUDA
  overlap worker output. The guard is disabled by default and enabled only with
  `CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE=dry-run-v0`. The positive DGX proof
  used the M4n 12-fixture heterogeneous matrix with validation and shadow
  enabled; it wrote `graph_guard_status=passed`,
  `graph_guard_eligibility=eligible`, `graph_consumption_state=not-consumed`,
  and `graph_mutation_consumed_worker_output=false`. The negative proof enabled
  the guard without shadow mode; validation still passed, but guard checks
  `shadow_mode_selected` and `shadow_passed` failed, producing
  `status=guard-failed-before-graph-mutation` before graph mutation.
- M4p: Flye can rehydrate validated packed CUDA overlap worker output into a
  Flye-side typed overlap vector after validation, shadow comparison, and the
  M4o guard pass. The positive DGX proof used the M4n 12-fixture heterogeneous
  matrix and wrote `overlap_rehydration_status=passed`,
  `overlap_rehydration_state=not-consumed`, and
  `graph_mutation_consumed_worker_output=false`. The negative proof used the
  same matrix with `CUFLYE_OVERLAP_REHYDRATION_PROOF_FAULT=drop-first-worker-record`;
  validation, shadow comparison, and guard still passed, but typed-vector
  comparison produced `12` mismatching fixtures and failed closed with
  `status=rehydration-failed-before-graph-mutation` before graph mutation.
- M4v: Flye can invoke the packed overlap worker through a two-request
  persistent JSONL lifecycle in opt-in session-batch mode. The positive DGX
  proof wrote a cold warmup response with `request_ordinal=1` and
  `worker_cuda_context_warm=false`, then an actual warm response with
  `request_ordinal=2`, `worker_cuda_context_warm=true`, and
  `timing_ms.request_total=8.223469 ms`. Exact toy-raw Flye artifacts matched
  the CPU baseline. This reduced measured per-request lifecycle cost by
  `98.134393%` versus the M4u cold batch-run worker process, but the full
  toy-raw run was still slower than CPU (`88s` vs `82s`) because the proof still
  pays for one synthetic warmup request inside the same Flye run.
- M5a-M5x: cuFlye now has a deterministic read-to-graph alignment oracle,
  bounded replay fixtures, a CUDA chain replay prototype, real multi-read
  batching, heterogeneous shape grouping, and a persistent per-shape CUDA arena.
  The M5h proof expands the toy-hifi replay harvest to `3546` valid fixtures
  and `3781` total input records while preserving every per-read
  `read-alignment-v1` oracle diff. M5i then replaces thousands of tiny
  per-fixture output copies with one bulk output copy per shape group. On the
  same M5h harvest, explicit persistent bulk-output CUDA averages
  `0.302834 ms` versus CPU `0.333798 ms` before TSV/JSON emission, a bounded
  replay hot-path speedup of `1.102247x`, while preserving every oracle diff.
  M5j-M5m move that worker into a Flye-side seam: Flye can invoke the CUDA
  read-alignment backend, validate output against CPU oracle rows, rehydrate
  typed rows into a `std::vector<GraphAlignment>` object-vector, substitute a
  verified selected slice, preserve exact artifacts, and fail closed on
  mismatch. M5n-M5o then move earlier in the read-alignment pipeline: the CUDA
  worker can emit pre-divergence chain DP output without CPU divergence rows,
  and Flye can run its own divergence filter on those GPU-produced chains in a
  selected-read dry run while recovering the same CPU `goodChains`. M5p-M5r
  then batch those pre-divergence chains behind a Flye-side session seam and
  keep CUDA context/device arena state warm across requests. M5s removes the
  remaining per-fixture TSV output bottleneck from the full3546 session path by
  writing one deterministic compact JSONL artifact that byte-matches the CPU
  compact oracle, reducing full3546 request time from `91.698238 ms` to
  `4.450572 ms`. M5t replaces that JSONL proof payload with a fixed-width
  little-endian `compact-binary-v0` payload, reducing payload size from
  `1126769` bytes to `332736` bytes and full3546 compact request time to
  `2.273654 ms` while preserving byte-level CPU/CUDA equivalence. M5u moves
  that binary payload into Flye's pre-divergence dry-run seam: Flye can request
  one compact binary file from the CUDA session, validate and rehydrate it,
  apply Flye's existing divergence filter, match CPU `goodChains`, preserve
  exact canonical artifacts, and fail closed on checksum/truncation corruption
  before graph mutation. M5v then consumes that verified output for the selected
  `_readAlignments` slice, preserving exact artifacts while proving mismatch
  and corrupted payloads remain fail-closed. M5w scales that guarded
  substitution from batch64 to the full3546 selected fixture set: all selected
  chains are replaced by verified CUDA-derived `goodChains`, canonical Flye
  artifacts still match CPU, and corrupted compact binary payloads still stop
  before graph mutation. M5x turns that into the first audited selected CPU
  bypass: selected reads skip CPU pre-divergence chain DP, GPU-derived
  `goodChains` are inserted back through audited placeholders, and canonical
  artifacts still match CPU. On toy-hifi this avoids `3546` selected CPU
  pre-divergence chains, but whole-Flye wall time improves by only about
  `0.024` seconds. M5y then attributes the post-bypass run: the selected CPU
  chain DP work is about `1.034468 ms`, selected CPU divergence filtering is
  about `174.507361 ms`, GPU divergence filtering still costs about
  `167.315051 ms`, and the attribution rerun remains noise-scale at the
  whole-Flye level (`20.81s` M5w vs `20.88s` M5x with `/usr/bin/time` log
  precision). This points the next boundary upstream to read-to-graph
  overlap/minimizer candidate generation, not more micro-optimization of the
  selected chain-DP slice.
- M6a: Flye now has an opt-in read-to-graph input-boundary oracle immediately
  after `quickSeqOverlaps(seqId)` and before `chainReadAlignments`. Two DGX
  toy-hifi oracle runs produced `12,483` records each (`3,577` query summaries,
  `5,092` raw overlap records, `3,814` chain-input records), canonical SHA-256
  `674a6bc7ffb42a058859254ac78aa83b374c578a18d17a339bd2e6a669d6d628`, and
  canonical diff `match` with timing excluded from the equality hash. Baseline
  versus oracle full Flye canonical artifact diffs both returned `match`. The
  timing attribution shows quick read-to-graph overlap discovery costs about
  `1.55-1.59s` on toy-hifi, while chain DP is under `1ms`, so the next CUDA
  target should move toward this upstream input boundary instead of the tiny
  selected chain-DP slice.
- M6b: the M6a input-boundary oracle can now be exported into a deterministic
  replay pack and replayed outside Flye. The DGX proof selected queries
  `5..12`, wrote `36` raw-overlap records and `8` oracle `chain_input` rows,
  recorded `28` filtered-out raw overlaps, and preserved
  `oracle.chain-input.tsv` SHA-256
  `5ab7b7fe51af9e90807e2d9be4824bd9216c732877cebc5eca58cb606b1c9f20`
  across CPU replay. Two pack exports diffed `match`. The pack is sufficient
  for a CUDA raw-overlap filter/sort replay prototype, but it intentionally
  does not yet contain query sequences, graph edge sequences, VertexIndex
  minimizer buckets, k-mer parameters, or enough internals to claim full
  `quickSeqOverlaps`/minimizer generation.
- M6c: a standalone CUDA raw-overlap filter/sort replay prototype now consumes
  the M6b pack and emits `chain_input` rows that canonical-diff `match` against
  both `oracle.chain-input.tsv` and CPU replay. The DGX proof used `36`
  raw-overlap records and produced `8` output rows with shared SHA-256
  `5ab7b7fe51af9e90807e2d9be4824bd9216c732877cebc5eca58cb606b1c9f20`.
  CUDA kernel time was `0.107616 ms`, but total process time was
  `300.936895 ms`, so this is a correctness/integration claim, not a speed
  claim. The next useful step is a richer minimizer-source pack, not optimizing
  this tiny replay kernel.
- M6d: Flye now has an opt-in read-to-graph minimizer source-pack capture for
  selected queries. The DGX toy-hifi proof selected queries `5..12`, captured
  `7725` query minimizers, `7640` VertexIndex bucket records, `33` edge
  sequences, `36` raw-overlap oracle rows, and `8` chain-input oracle rows.
  Two source-pack exports canonical-diffed `match` with SHA-256
  `4b38ac5dfc40e6e4ac7308b24c1286494241954a872eac8de33a25f5ccff5e87`.
  Baseline versus capture full Flye canonical artifact diffs both returned
  `match`. M6d still records `missing-semantics-ledger`, so it is not a CUDA or
  speed claim; it moves the next work from raw-overlap replay toward external
  reconstruction of Flye `quickSeqOverlaps` semantics.
- M6e: the M6d source pack now has an external CPU replay harness for selected
  read-to-graph queries. The DGX proof replayed source-pack A/B
  deterministically with SHA-256
  `d6bcac19ab5fdd3ba2cd37f2c677a744104c093ae6e508c0225ebf9eec5d626b` and
  status `gap-ledger`. The replay reconstructed KmerMatch-like records,
  Flye-style chain DP, `overlapTest`, primary-overlap filtering, and the
  read-to-graph divergence gate. It exactly matched `14/36` raw-overlap rows
  and geometrically matched `26/36`, proving the next blocker is not CUDA
  mechanics but source completeness: M6d captures query minimizer hits while
  Flye's CPU path iterates all query k-mers through `IterKmers`.
- M6f: the source pack now includes `full-query-hits.tsv`, the full
  `OverlapDetector::IterKmers` query-hit stream for selected read-to-graph
  queries. The DGX proof captured `7747` full query-hit records, deterministic
  source-pack SHA-256
  `16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f`, and
  deterministic replay SHA-256
  `1be41bf42fecd4c1af40eb516ee7377afdcce20a2c7bfdd52fdaccb0cdeb3e6c`.
  Replay improved from M6e's `14/36` exact raw-overlap rows to `35/36`, and
  from `26/36` geometry rows to `35/36`. Baseline versus capture full Flye
  artifact diffs still returned `match`. The remaining gap is a single query
  `11` / edge sequence `-3587` ordering/tie/primary-selection mismatch, not
  source completeness.
- M6g: the external full-query-hit replay now models libstdc++
  `std::sort` equal-key behavior at the KmerMatch, score-order, and
  primary-overlap ordering points used by Flye. The DGX proof reused the M6f
  source pack, validated deterministic source-pack A/B SHA-256
  `16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f`,
  replayed A/B to deterministic raw-overlap SHA-256
  `2e1201a2e768ed682afc6b0feb90d50aeeea8ad66597861c6c61ba062a34e420`, and
  reached row-key `36/36` equality for read/edge coordinates and score.
  Geometry also matched `36/36`, while all `36` rows still report non-key field
  differences for fields such as `seq_divergence` and `edge_id`. Baseline
  versus capture full Flye artifact diffs remained `match`. M6g is not a CUDA
  or speed claim; it removes the last ordering blocker before a CUDA
  full-query-hit replay consumer.
- M6h: a standalone CUDA full-query-hit replay consumer now reads the selected
  M6f/M6g source pack and emits raw-overlap records that canonical row-key diff
  `match` against the M6g CPU replay. The DGX proof used source-pack SHA-256
  `16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f`,
  replayed `7747` full query-hit records across `33` ext groups, ran CUDA work
  for `22` active groups, and emitted `36` CUDA raw-overlap records. CPU versus
  CUDA canonical row-key diff matched all `36` rows, CUDA A/B row-key diff also
  matched, and an intentionally too-small memory budget failed closed with JSON
  `status=error`. Direct CPU-vs-CUDA row order still differs for one
  equal-score pair, so M6h uses the explicit canonical row-key diff gate. This
  is not a speed claim: CPU replay wall time was about `0.11s`, while the cold
  CUDA process was about `0.48s` and CUDA kernel time was `53.170850 ms`.
- M6i: the standalone CUDA full-query-hit replay consumer now supports
  `--kernel-mode serial|parallel-score`. The new `parallel-score` mode uses
  `128` threads per active ext group to parallelize predecessor scoring while
  preserving the M6h canonical row-key output. DGX proof showed CPU vs
  parallel row-key diff `match`, serial vs parallel row-key diff `match`,
  deterministic parallel A/B output, and fail-closed memory-budget rejection.
  On the selected tiny pack, kernel time improved only slightly
  (`53.287348 ms` serial to `52.542531 ms` parallel-score) and cold CUDA wall
  time improved from `0.48s` to `0.43s`, but CPU replay remained faster at
  about `0.11s`. This is a bounded kernel-parallelism proof, not a whole-Flye
  speed claim.
- M6j: the full-query-hit replay consumer now supports `--repeat-count` as a
  warm-session benchmark harness. It keeps one process, CUDA context, and
  device-buffer set alive across repeated `parallel-score` requests while
  preserving CPU-vs-session row-key `match`, cold-vs-session row-key `match`,
  session A/B row-key `match`, and fail-closed memory-budget rejection. On the
  selected source pack, the best warm request total was `52.199131 ms` versus
  CPU replay wall time `90.0 ms`, a bounded hot-request speedup of
  `1.7241666341150392x`. The cold CUDA process was still slower at about
  `470 ms`, so this is a scoped session hot-path claim, not a whole-Flye
  speedup claim.
- M6k: the full-query-hit replay consumer now has a file-backed worker
  request/response boundary with `--worker-request-json` and
  `--worker-requests-jsonl`. Two compatible requests in one worker process
  preserve CUDA context and device buffers; the second request reports
  `worker_cuda_context_warm=true`, `parse=0`, `device_allocation=0`, and
  `host_to_device=0`. DGX proof preserved CPU-vs-worker row-key `match`,
  cold-vs-worker row-key `match`, worker A/B row-key `match`, and fail-closed
  memory-budget rejection. On the selected source pack, warm worker actual
  request time was `52.243993 ms` versus CPU replay wall time `110.0 ms`, a
  bounded warm-worker speedup of `2.105505220475778x`. This is a worker-boundary
  hot-request claim, not a Flye graph-consumption or whole-Flye speed claim.

Current allowed performance claim:

```text
cuFlye's CUDA candidate-generation worker is faster than the CPU oracle for the
measured real-pack and sampled real-read candidate fixtures while preserving
candidate-list equivalence.

cuFlye also has a deterministic CPU overlap-range oracle for the upstream toy
fixture; this is a correctness boundary for future CUDA overlap chaining, not a
GPU speed claim.

cuFlye has isolated one non-base-alignment CPU overlap-chain replay shape from
candidate records to `overlap-range-v1`; this is a semantic replay claim, not a
CUDA or end-to-end performance claim.

cuFlye has also reproduced that same bounded overlap-chain replay shape with a
standalone CUDA prototype; this is a CUDA correctness claim for one supported
fixture, not a Flye graph-integration or workload-level speed claim.

The current CUDA overlap-chain hotpath is not faster than the C++ CPU baseline
for the only supported M4b fixture; this is a measured optimization blocker,
not a speedup claim.

The current parallel-reduce CUDA overlap-chain kernel preserves correctness but
does not improve the single-query benchmark. Further overlap-chain performance
work must increase real batched work before claiming speed.

cuFlye now has a bounded overlap-chain CUDA speedup on the M4f/M4g top-9 real
replay-match fixture batch: packed serial CUDA is faster than the CPU replay
batch while preserving exact `overlap-range-v1` oracle hashes. This is an
overlap-chain replay claim only, not a Flye stage or end-to-end GPU mode claim.

cuFlye also has a governed file-backed overlap worker boundary for that packed
replay path. This is a worker round-trip and fail-closed protocol claim, not a
claim that Flye graph logic consumes GPU overlap output.

cuFlye now has a Flye-side proof seam that can request CUDA overlap worker
output and stop before graph mutation. This is an integration-boundary claim,
not an end-to-end GPU Flye or graph-consumption claim.

cuFlye can now request a packed multi-query CUDA overlap worker batch from the
Flye seam using an explicit query-id allowlist. This preserves the M4h bounded
overlap-chain replay speedup at the Flye request boundary, while still refusing
to feed GPU overlap output into Flye graph logic.

cuFlye now has a Flye-side validation gate for packed CUDA overlap worker
output. Passing output can be marked consumption-eligible, and mismatching
output fails closed before graph mutation. This is still not a graph-consumption
claim.

cuFlye now has a Flye-side shadow consumption proof for packed CUDA overlap
worker output. Validated worker output can be parsed into canonical overlap
records and compared against CPU overlap ranges captured in memory. This is one
more integration boundary, but it still does not feed GPU output into graph
mutation.

cuFlye now has a broader heterogeneous shadow matrix proof for that boundary.
The proof documents selected supported shapes and unsupported exclusions, and it
shows validation and shadow success across `12` replay-match fixtures before
graph mutation. This still does not feed GPU output into graph mutation.

cuFlye now has a guarded graph-consumption dry-run contract for that same
boundary. This is a safety and auditability claim: the code can prove the
preconditions for future graph consumption and still records that worker output
was not consumed by graph mutation.

cuFlye can now rehydrate validated CUDA overlap worker records into a
Flye-side typed overlap vector and prove that vector matches CPU overlap
records captured in memory. This is a representation-boundary claim; it still
does not feed GPU output into graph mutation.

cuFlye can now keep the actual overlap-worker request warm inside a two-request
persistent JSONL lifecycle and preserve exact toy-raw Flye artifacts. This is a
worker-lifecycle seam claim: the warm request is much cheaper than the M4u cold
batch worker process, but the proof is not yet a whole-Flye speedup.

cuFlye can also reuse per-shape CUDA read-alignment arenas across benchmark
iterations while preserving every per-read oracle diff. This is a CUDA overhead
reduction claim for a bounded replay benchmark, not a CPU-beating or end-to-end
Flye speed claim.

cuFlye can now expand that proof to a much larger toy-hifi read-alignment
fixture harvest. This improves diagnosis: kernel work is no longer the main
problem, while thousands of tiny output copies dominate total CUDA time.

cuFlye can now run that bounded M5h read-alignment chain replay harvest through
an explicit persistent CUDA bulk-output mode faster than the CPU replay
baseline before TSV/JSON emission while preserving every per-read oracle diff.
This is a bounded read-alignment replay hot-path claim, not a full Flye GPU-mode
claim.

cuFlye can now invoke that M5i read-alignment CUDA backend from inside a real
Flye run behind a graph-facing dry-run seam. The seam validates worker TSVs
against CPU oracle TSVs, writes graph guard metadata, records
`graph_mutation_consumed_worker_output=false`, and stops before graph mutation.
This is an integration-safety claim, not a graph-consumption or speed claim.

cuFlye can now invoke CUDA pre-divergence read-alignment chain output from
inside Flye for a selected read, run Flye's existing divergence filter on those
GPU-produced chains, recover the same `goodChains` as CPU, preserve exact Flye
artifacts, and fail closed on mismatch. This is still an integration-boundary
claim, not a default GPU mode or full-Flye speed claim.

cuFlye can now bypass per-fixture TSV emission for the read-alignment CUDA
session proof by writing one compact JSONL artifact that byte-matches the CPU
compact oracle. This is a host-output overhead reduction claim for the scoped
full3546 replay request, not a full Flye GPU-mode claim.

cuFlye can now write that scoped read-alignment session payload as
`compact-binary-v0`, validate schema/count/checksum/length gates, and
byte-match the CPU binary oracle. This is a payload and proof-harness
optimization claim, not yet a Flye-side binary consumption claim.

cuFlye can now consume `compact-binary-v0` inside Flye's guarded
pre-divergence read-alignment seam: Flye validates the binary payload,
rehydrates CUDA-produced chains, applies its existing divergence filter, and
matches CPU `goodChains` for the selected batch while preserving exact
artifacts. This is a Flye-side binary consumption and integration-overhead
claim, not a default GPU mode or whole-Flye speed claim.

cuFlye can now substitute verified compact-binary CUDA-derived `goodChains` into
Flye's selected `_readAlignments` slice while preserving exact artifacts and
failing closed on mismatch or corrupted payloads. This is a selected-slice
graph-facing consumption claim, not an unbounded replacement or whole-Flye
speed claim.

cuFlye can now scale that guarded compact-binary substitution path to the
full3546 selected read-alignment fixture set inside Flye. This proves the
payload, validation, and selected-slice consumption path holds at the full
selected toy-hifi scale, but it is still not a whole-Flye speed claim because
the seam intentionally keeps CPU `goodChains` as the live verifier.

cuFlye can now run an opt-in selected-read CPU-bypass mode for that same
full3546 set. This is the first read-alignment proof where selected CPU
pre-divergence chain DP is not computed before GPU consumption. It is a local
GPU-mode advantage, not a meaningful whole-Flye speedup: the toy-hifi full run
only improves from `20.765673444s` to `20.741208213s`.

cuFlye can now attribute that selected CPU-bypass effect: selected reads skip
CPU pre-divergence chain DP and CPU divergence filtering, consume verified
compact-binary CUDA-derived `goodChains`, and preserve exact canonical Flye
artifacts for the full3546 toy-hifi set. M5y does not prove whole-Flye
acceleration; it proves the next high-ROI CUDA boundary should move earlier to
read-to-graph overlap/minimizer candidate generation.

cuFlye can now replay the selected read-to-graph full-query-hit source pack to
row-key equality after modeling Flye's libstdc++ equal-key sort behavior. This
is a CPU replay correctness claim for raw-overlap coordinates and scores, not a
CUDA speed claim and not full non-key field reproduction.

cuFlye now has a standalone CUDA consumer for that selected full-query-hit
source pack. It produces the same canonical raw-overlap row-key set as the M6g
CPU replay for all selected rows and fails closed on unsupported memory budget,
but it is slower than CPU on the tiny pack because the M6h path pays cold CUDA
process and context overhead.

cuFlye now has a `parallel-score` full-query-hit replay mode that preserves the
same canonical row-key set as the M6h serial CUDA path. It gives a small
bounded CUDA improvement on the selected pack, but CPU replay is still faster,
so the next performance claim must come from warm session overhead reduction or
larger supported work.

cuFlye now has that first warm-session full-query-hit replay proof: with CUDA
context and device buffers kept warm, the bounded `parallel-score` request beats
the matched CPU replay wall time for the selected source pack while preserving
canonical row-key parity. This is a hot-request claim, not a cold-process,
Flye-stage, or whole-Flye claim.

cuFlye now preserves that hot-request advantage through a file-backed
full-query-hit worker boundary. The second compatible worker request reuses the
warm CUDA session and beats matched CPU replay wall time while preserving
canonical row-key parity. This is still not Flye graph consumption or a
whole-Flye speed claim.
```

Current forbidden claim:

```text
Flye as a whole is faster in GPU mode.
```

## Roadmap

### M2: Real Candidate Backend Integration

Purpose: replace the current CUDA stub at the candidate-generation boundary
without changing downstream chaining or graph logic.

Work items:

- Add a C++ candidate backend interface with CPU and CUDA implementations.
- Move standalone M1i/M1j logic behind the backend seam.
- Upload read windows and flattened index buckets from real Flye data
  structures, not hand-written fixtures.
- Return candidate-record-v1 compatible records to the existing CPU path.
- Canonically sort GPU records before comparison.

Gate:

- CPU backend and CUDA backend candidate dumps match after canonical sorting on
  toy fixture.
- Default CPU Flye output remains unchanged.
- `CUFLYE_CANDIDATE_BACKEND=cuda` no longer fails as a stub for supported toy
  data, and it never silently falls back.

Stop if:

- GPU candidate dump differs from CPU and the mismatch cannot be explained by
  ordering alone.
- GPU path needs downstream graph changes to pass.

### M3: Candidate Backend Scale-Up

Purpose: prove candidate parity and speed on larger sampled data.

Work items:

- Add sampled real-read fixtures from DGX runs.
- Add bounded memory budget and batch planner.
- Measure candidate generation wall time, CPU fallback rate, peak CPU RSS, peak
  GPU allocation, and output record counts.

Gate:

- Candidate dumps match CPU oracle on toy plus sampled real reads.
- CUDA candidate generation is faster than CPU for at least one realistic
  sampled fixture.

Allowed claim after gate:

```text
cuFlye's candidate-generation backend is faster on CUDA for specific sampled
fixtures while preserving candidate-list equivalence.
```

### M4: Overlap Chaining Parity

Purpose: move from raw candidate hits to overlap ranges while preserving Flye
chaining semantics.

Work items:

- Define an overlap-range ABI. Completed in M4a.
- Isolate a bounded CPU overlap-chain replay fixture. Completed in M4b.
- Port or batch the chain DP used by `OverlapDetector::getSeqOverlaps`.
- Preserve gap penalties, jump thresholds, minimum overlap, overhang filters,
  and divergence thresholds.

Gate:

- GPU and CPU overlap dumps match in deterministic mode on regression fixtures.
- Candidate backend speedup is not erased by chaining overhead.

### M5: Read-to-Graph Alignment

Purpose: accelerate read-to-graph alignment using the same sequence/index
primitives.

Work items:

- Identify `ReadAligner::alignReads` data contracts.
- Build read-to-graph candidate and chain oracles.
- Add parity gates for `read_alignment_dump`.

Gate:

- `read_alignment_dump` matches CPU on toy and sampled fixtures.

### M6: Polishing Kernels

Purpose: evaluate GPU acceleration for polishing only after overlap/read-graph
contracts are stable.

Work items:

- Define bubble-level CPU oracle.
- Evaluate custom CUDA kernels or a Flye-compatible `cudapoa` wrapper.
- Preserve Flye scoring and output ordering.

Gate:

- Polishing consensus output matches CPU on fixtures.

### M7: Experimental `flye --gpu`

Purpose: expose opt-in GPU mode.

Work items:

- Add CLI flags: `--gpu`, `--gpu-devices`, `--gpu-batch-mb`,
  `--verify-cpu-kernels`.
- Emit metadata for backend selection, CUDA device, memory budgets, fallback
  events, and verification mode.
- Build an end-to-end benchmark matrix.

Gate:

- End-to-end Flye outputs pass deterministic or scientific-equivalence gates.
- Wall time improves on target workloads.
- CPU fallback paths are auditable.

## Regression Matrix

Minimum fixtures:

- upstream toy HiFi;
- small PacBio CLR;
- small ONT raw;
- uneven-coverage or metagenome fixture;
- DGX sampled subset from the target exact rerun workload.

Each fixture should run:

- CPU default;
- CPU deterministic;
- CUDA deterministic with CPU verification;
- CUDA throughput mode.

Required reports:

- candidate counts and hashes;
- overlap counts and hashes once M4 exists;
- canonical artifact diff;
- wall time by stage;
- peak RAM;
- peak GPU memory allocation;
- CPU fallback count and reasons.

## Naming And Claim Discipline

Use precise milestone labels:

- `CUDA candidate smoke`: ABI output only.
- `CUDA k-mer join smoke`: bounded equality join fixture.
- `CUDA k-mer encode smoke`: device-side k-mer encoding fixture.
- `CUDA read-window smoke`: bounded read-window fixture.
- `CUDA candidate-core benchmark`: bounded performance subproblem.
- `CUDA candidate backend`: integrated Flye candidate-generation boundary.
- `GPU Flye mode`: only after end-to-end `flye --gpu` exists and passes gates.

## Immediate Next Step

Next highest-ROI task:

```text
M4o: define a guarded overlap graph-consumption contract and dry-run proof
before allowing CUDA overlap output to affect Flye graph mutation. Completed.
```

Next highest-ROI task:

```text
M4p: rehydrate validated CUDA overlap worker output into a Flye-side typed
overlap vector in a no-mutation dry-run, then prove it matches the CPU vector
before any graph-consumption path is enabled. Completed.
```

Next highest-ROI task:

```text
M4q: convert the validated typed overlap vector into actual Flye `OverlapRange`
objects in a no-mutation dry-run, then prove the object vector canonicalizes
back to the CPU overlap vector before graph consumption is enabled.
Completed.
```

M4q proof on DGX used the M4n 12-fixture heterogeneous matrix. The positive
run passed validation, shadow comparison, graph guard, M4p typed rehydration,
and M4q `OverlapRange` object rehydration with
`graph_mutation_consumed_worker_output=false`. The negative proof injected
`drop-first-overlap-range`; validation, shadow comparison, graph guard, and
typed rehydration still passed, while object-vector comparison found 12
mismatching fixtures and failed closed before graph mutation.

Allowed M4q claim:

```text
cuFlye can construct actual Flye `OverlapRange` object vectors from validated
CUDA overlap worker output and prove they canonicalize to CPU overlap records
before graph mutation.
```

Next highest-ROI task:

```text
M4r: use the verified `OverlapRange` object vector as an opt-in graph-facing
substitution smoke for selected fixtures, still guarded by exact CPU comparison
and fail-closed behavior, then prove graph artifacts stay unchanged or the run
stops before mutation.
Completed.
```

M4r proof on DGX selected toy-raw query `353` as the first graph-facing
substitution smoke. The positive run passed validation, shadow comparison,
graph guard, typed rehydration, object rehydration, and exact CPU comparison,
then returned the worker-derived `OverlapRange` vector to Flye. Canonical graph
and assembly artifacts matched the CPU toy-raw run. A durable
`worker-vector-substitution.consumed` sentinel kept later Flye subprocesses
from re-invoking the worker and overwriting the accepted proof.

The negative proof injected `drop-first-substitution-overlap`; all upstream
checks still passed, but substitution detected the object-vector mismatch and
failed closed before returning worker output.

Allowed M4r claim:

```text
cuFlye can return a verified CUDA-worker-derived Flye `OverlapRange` vector for
one selected supported overlap query, preserve canonical Flye graph artifacts,
and fail closed on a forced substitution mismatch.
```

Forbidden M4r claim:

```text
M4r does not prove default GPU mode, unsupported-shape substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4s: expand verified graph-facing substitution from one selected query to a
deterministic supported-shape session ledger. Every query/shape decision should
be recorded as substituted, skipped, or failed-closed, and positive artifacts
must still match CPU.
Completed.
```

M4s proof on DGX selected toy-raw query ids `353,381`. The positive session
substituted both selected supported queries, wrote per-query sentinels, and
preserved canonical Flye graph/output artifacts against the CPU toy-raw
baseline. The session ledger recorded:

```text
substituted: 2
skipped-already-substituted: 5
skipped-not-selected: 1892
skipped-unsupported-non-selected-shape: 987
```

The mismatch negative proof injected `drop-first-substitution-overlap` and
failed closed before returning worker output. The unsupported-shape negative
proof injected `force-unsupported-selected-shape` and failed closed before
worker invocation.

Allowed M4s claim:

```text
cuFlye can substitute multiple selected supported Flye overlap queries with
verified CUDA-worker-derived `OverlapRange` vectors, preserve canonical Flye
artifacts, and record substituted, skipped, and failed-closed query/shape
decisions in a session ledger.
```

Forbidden M4s claim:

```text
M4s does not prove default GPU mode, unsupported-shape CUDA substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4t: add timing attribution to substitution sessions so cuFlye can separate CPU
overlap time, CUDA worker time, process/IO overhead, validation overhead, and
ledger overhead before choosing the next performance optimization.
Completed.
```

M4t proof on DGX preserved the M4s safety gates and added per-decision timing
attribution to the substitution ledger. The positive toy-raw session selected
query ids `353,381`, substituted both, and preserved canonical Flye artifacts
against the CPU baseline. Ledger decision counts were unchanged from M4s:

```text
substituted: 2
skipped-already-substituted: 5
skipped-not-selected: 1892
skipped-unsupported-non-selected-shape: 987
```

The timing result was not a speedup. CPU toy-raw baseline elapsed `87s`; the
substitution/timing run elapsed `99s` (`1.137931x` CPU wall time). Selected
query timing showed the current seam is dominated by external worker/process
overhead:

```text
query 353: cpu_overlap_ms=1.307334, worker_process_ms=452.297705, seam_total_ms=469.227281
query 381: cpu_overlap_ms=18.568655, worker_process_ms=376.389273, seam_total_ms=395.499113
```

The mismatch negative proof injected `drop-first-substitution-overlap` and
failed closed with timing attribution. The unsupported-shape negative proof
injected `force-unsupported-selected-shape`, failed closed before worker
invocation, and recorded `worker_process_ms=0`.

Allowed M4t claim:

```text
cuFlye can attach non-negative timing attribution to graph-facing substitution
decisions, preserve exact Flye artifacts for two selected supported toy-raw
queries, and keep mismatch and unsupported-shape negative paths fail-closed.
```

Forbidden M4t claim:

```text
M4t does not prove default GPU mode, unsupported-shape CUDA substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4u: reduce selected-query substitution seam overhead, especially external
worker process startup and request/response file IO, before expanding
graph-facing substitution scope.
Completed.
```

M4u added an opt-in session batch/cache substitution mode:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-session-batch-v0
```

The positive DGX proof preserved exact canonical Flye artifacts. It recorded one
selected query deferred while waiting for the allowlist-sized batch, one selected
query substituted from the batch worker run, and one later selected query
substituted from the verified batch cache:

```text
deferred-session-batch-waiting: 1
substituted-from-session-batch-run: 1
substituted-from-session-batch-cache: 1
skipped-already-substituted: 4
skipped-not-selected: 1892
skipped-unsupported-non-selected-shape: 987
```

The timing result showed integration progress but not end-to-end Flye speedup.
CPU toy-raw baseline elapsed `84s`; batch/cache substitution elapsed `91s`
(`1.083333x` CPU wall time). Selected substitution timing improved versus M4t:

```text
M4t selected worker_process_ms avg: 414.343489
M4u selected worker_process_ms avg: 220.396566
worker_process avg reduction: 46.808247%
M4t selected seam_total_ms avg: 432.363197
M4u selected seam_total_ms avg: 228.892051
seam_total avg reduction: 47.060237%
```

The mismatch negative proof injected `drop-first-substitution-overlap`; query
`353` deferred and query `381` failed closed at exact substitution comparison.
The unsupported-shape negative proof injected `force-unsupported-selected-shape`
and failed closed before worker invocation with `worker_process_ms=0`.

Allowed M4u claim:

```text
cuFlye can amortize one verified session batch worker run across a later cached
selected substitution, preserve exact Flye artifacts, and reduce selected
substitution seam overhead versus M4t.
```

Forbidden M4u claim:

```text
M4u does not prove default GPU mode, unsupported-shape CUDA substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4v: introduce an explicit persistent overlap-worker lifecycle so warm
sequential batch requests avoid paying external worker process startup cost each
time.
Completed.
```

M4v proof on DGX used toy-raw query ids `353,381` in
`verified-overlap-range-session-batch-v0` with
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=jsonl-persistent-v0`. The positive run
preserved exact canonical Flye artifacts against the CPU toy-raw baseline. The
worker processed two requests from `worker-requests.jsonl`: a cold warmup
request, then an actual warm request. The actual response reported:

```text
request_ordinal: 2
worker_cuda_context_warm: true
timing_ms.request_total: 8.223469 ms
timing_ms.backend_mean_total_before_write: 5.530894 ms
timing_ms.worker_overhead: 2.692575 ms
```

Compared with M4u's cold batch-run worker process time of `440.793131 ms`, the
M4v actual warm request total is `53.601847x` faster, a `98.134393%` reduction
in measured request-lifecycle cost.

M4v is still not an end-to-end Flye speedup. CPU toy-raw elapsed `82s`; the
persistent lifecycle run elapsed `88s` (`1.073171x` CPU wall time), because this
proof still pays for one synthetic warmup batch inside the same Flye run. The
mismatch negative proof failed closed at exact substitution comparison, and the
unsupported-shape negative proof failed closed before worker invocation with
`worker_process_ms=0`.

Allowed M4v claim:

```text
cuFlye can invoke the overlap worker through a two-request persistent JSONL
lifecycle, keep the actual request warm, preserve exact toy-raw Flye artifacts,
and fail closed on mismatch or unsupported selected shapes.
```

Forbidden M4v claim:

```text
M4v does not prove default GPU mode, broad unsupported-shape substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4w: turn the M4v warm-request lifecycle proof into a Flye-visible persistent
worker session that avoids a duplicate warmup batch in the same proof path.
Completed.
```

M4w proof on DGX used toy-raw query ids `353,381` in
`verified-overlap-range-session-batch-v0` with
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`. An external
file-backed worker session initialized CUDA context before writing
`session-ready.json`; Flye then submitted only the actual `worker-request.json`
through the session inbox. The positive run generated no
`worker-request-warmup.json`, no `worker-response-warmup.json`, and no
`worker-requests.jsonl`.

The actual response reported:

```text
request_ordinal: 1
worker_cuda_context_warm: true
worker_context_setup_ms: 304.411037 ms
timing_ms.request_total: 9.025404 ms
timing_ms.backend_mean_total_before_write: 6.148255 ms
timing_ms.worker_overhead: 2.877149 ms
```

Flye-visible selected `worker_process_ms` fell to `14.157398 ms`, versus M4u's
cold batch-run `440.793131 ms` and M4v's warmup-plus-actual process segment
`463.398560 ms`. That is a `96.788199%` reduction versus M4u and a
`96.944877%` reduction versus M4v for the selected worker/process segment.

M4w is still not an end-to-end Flye speedup. CPU toy-raw elapsed `73s`; the
M4w positive run elapsed `83s` (`1.136986x` CPU wall time), because the proof
still computes CPU overlaps first as the live oracle and only then substitutes
the verified GPU-derived overlap vector. The mismatch negative proof failed
closed at exact substitution comparison, and the unsupported-shape negative
proof failed closed before any worker/session submission with
`worker_process_ms=0`.

Allowed M4w claim:

```text
cuFlye can submit a verified Flye overlap worker request to a true file-backed
persistent CUDA session without a duplicate warmup request, preserve exact
toy-raw Flye artifacts, and fail closed on mismatch or unsupported selected
shapes.
```

Forbidden M4w claim:

```text
M4w does not prove default GPU mode, broad unsupported-shape substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4x: split the proof-only live CPU oracle from a bounded GPU-first supported
overlap substitution path, so performance runs can avoid computing the selected
CPU overlap before invoking CUDA while still retaining an audit gate.
```

Completed.

M4x proof on DGX used toy-raw query ids `353,381` in
`gpu-first-supported-v0` with `CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`.
Flye first built the same verified session batch cache as M4w. A later
allowlisted supported call for query `353` then returned the cached
CUDA-worker `OverlapRange` vector before live CPU overlap.

The positive selected ledger evidence was:

```text
353 deferred-session-batch-waiting cpu_overlap_ms=0.939491 worker_process_ms=0.0
381 substituted-from-session-batch-run cpu_overlap_ms=9.166123 worker_process_ms=12.997414
353 gpu-first-from-session-batch-cache cpu_overlap_ms=0.0 worker_process_ms=0.0
```

The positive DGX proof preserved exact toy-raw artifacts against CPU:

```text
Flye run diff: match
```

The audit negative enabled `CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE=oracle-file-v0`
and `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-gpu-first-overlap`.
It failed closed before graph mutation:

```text
status: gpu-first-substitution-failed-before-live-cpu-overlap
error: gpu-first audit object vector differs from captured CPU oracle
graph_mutation_consumed_worker_output: false
```

M4x is a real seam-level benefit, but it is still not an end-to-end Flye
speedup. CPU toy-raw elapsed `72s`; the M4x positive run elapsed `84s`
(`1.166667x` CPU wall time), because the proof bypasses one selected cached
overlap while the rest of Flye remains CPU-bound and instrumentation still
records ledger decisions.

Allowed M4x claim:

```text
cuFlye can reuse a verified file-backed CUDA session batch cache for a later
allowlisted supported overlap query before live CPU overlap, preserve exact
toy-raw artifacts, and fail closed on GPU-first audit mismatch.
```

Forbidden M4x claim:

```text
M4x does not prove default GPU mode, broad unsupported-shape substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4y: reduce proof overhead and broaden GPU-first selection to a bounded set of
high-cost supported overlap calls, while keeping the sparse ledger and audit
sampling explicit.
```

Completed.

M4y proof on DGX used toy-raw with
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=gpu-first-supported-v0`,
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`, and
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_LEDGER_MODE=selected-only-v0`.

An initial 8-query set included `798`, but the worker validation gate rejected
it fail-closed because the canonical worker output did not match the CPU oracle:

```text
query_798 oracle_records=49 worker_records=48 canonical_diff_status=mismatch
```

The accepted positive proof used the bounded 7-query allowlist
`161,554,89,112,896,110,752`. It preserved exact toy-raw artifacts:

```text
Flye run diff: match
```

The sparse positive ledger evidence was:

```text
entries=35
non_selected_entries=0
deferred-session-batch-waiting=7
substituted-from-session-batch-run=1
gpu-first-from-session-batch-cache=6
skipped-already-substituted=21
```

The sampled audit negative used
`CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE=oracle-file-v0`,
`CUFLYE_OVERLAP_GPU_FIRST_AUDIT_QUERY_IDS=161`, and
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-gpu-first-overlap`.
Non-audited GPU-first cache hits were accepted first; the audited `161` reuse
then failed closed before graph mutation:

```text
status: gpu-first-substitution-failed-before-live-cpu-overlap
error: gpu-first audit object vector differs from captured CPU oracle
proof_fault_applied: true
graph_mutation_consumed_worker_output: false
```

M4y reduces proof overhead and broadens the GPU-first surface, but still does
not prove end-to-end Flye speedup. CPU toy-raw elapsed `72s`; the M4y positive
run elapsed `74s` (`1.027778x` CPU wall time). The benefit is seam-level:
6 later selected calls returned cached worker `OverlapRange` vectors with
`cpu_overlap_ms=0` and `worker_process_ms=0`, and positive ledger volume fell
from M4x's 2886-row full-ledger pattern to 35 selected rows.

Allowed M4y claim:

```text
cuFlye can run a bounded multi-query GPU-first supported overlap substitution
proof with sparse selected-only ledger output, preserve exact toy-raw artifacts,
and fail closed on sampled GPU-first audit mismatch.
```

Forbidden M4y claim:

```text
M4y does not prove default GPU mode, broad unsupported-shape substitution,
unsupported candidate acceptance, or end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4z: turn the bounded manual selection proof into an automated validation-safe
GPU-first selection planner and compare serial versus parallel-reduce worker
kernels, so the next proof can increase accepted cache hits without hand-picking
unsafe query ids like 798.
```

Completed.

M4z adds a deterministic planner for GPU-first overlap query selection. It reads
substitution ledger JSONL plus worker-validation JSON, ranks repeated supported
query ids by later CPU-overlap cost, and treats validation failures as hard
rejections.

The DGX planner proof combined M4y's failed 8-query evidence with the successful
7-query positive proof. It rejected query `798` because validation had already
shown a canonical mismatch:

```text
query_798 oracle_records=49 worker_records=48 canonical_diff_status=mismatch
```

It emitted this validation-safe allowlist:

```text
161,89,554,752,112,896,110
```

The accepted 7-query batch was then replayed directly through the overlap
worker with `warmup_runs=1` and `benchmark_runs=10`. Both CUDA worker kernel
modes produced `237` total overlap records and canonical-diffed `match` against
all 7 fixture CPU oracles.

The worker timing comparison was:

```text
serial kernel_ms=6.735444 backend_mean_ms=6.788436 request_total_ms=89.063285
parallel-reduce kernel_ms=7.150598 backend_mean_ms=7.207953 request_total_ms=90.571207
parallel/serial kernel ratio=1.061637
```

M4z improves selection governance, not whole-Flye speed. It prevents unsafe
manual allowlists from admitting known mismatches, and it shows that
`parallel-reduce` is not the better kernel for the current small M4y fixture
batch. The serial packed worker remains the preferred mode for the next
GPU-first proof.

Allowed M4z claim:

```text
cuFlye can derive a validation-safe GPU-first overlap query allowlist from
ledger and validation evidence, reject known mismatches such as query 798, and
verify both serial and parallel-reduce worker modes before choosing the faster
safe mode for the next proof.
```

Forbidden M4z claim:

```text
M4z does not prove default GPU mode, broad unsupported-shape substitution,
parallel-reduce superiority, or end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M5a: start the read-to-graph alignment oracle by locating Flye's
ReadAligner::alignReads contract, defining a compact alignment-record ABI, and
dumping CPU oracle records before any CUDA read-to-graph acceleration.
```

Completed.

M5a defines `read-alignment-v1`, a flat TSV CPU oracle for Flye
`GraphAlignment` records after `ReadAligner::alignReads` accepts and
divergence-filters read-to-repeat-graph chains. The opt-in dump is controlled by
`CUFLYE_READ_ALIGNMENT_DUMP` and fails closed unless Flye runs with
`--threads 1`, because raw chain append order is not deterministic in the
parallel aligner.

The DGX toy-hifi proof applied and built the patch series through
`0025-cuflye-read-alignment-dump.patch`. Two deterministic runs produced the
same `read-alignment-v1` oracle:

```text
records=7232
chains=7092
reads=7092
edges=14
canonical_sha256=f4815278bffdb993fd815a8a0ead2db44263aefe2fc38d65836bc48186dc904e
canonical diff=match
```

The negative DGX run enabled the dump with `--threads 2`; Flye exited with
status `1`, recorded expected failure metadata, found the fail-closed message
`cuFlye read alignment dump requires --threads 1`, and produced no dump file.

Allowed M5a claim:

```text
cuFlye can produce and validate a deterministic CPU read-to-graph alignment
oracle after ReadAligner::alignReads, and it fails closed when the proof is not
single-thread deterministic.
```

Forbidden M5a claim:

```text
M5a does not prove CUDA read-to-graph acceleration, default GPU mode, graph
mutation consumption, or end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M5b: isolate a bounded read-to-graph replay fixture that captures the graph-edge
sequences, read sequence, and per-read edge-overlap inputs needed to reproduce
one read alignment chain outside a full Flye run.
```

Completed.

M5b adds `read-alignment-replay-fixture-v0`, an opt-in fixture dump for one
selected `ReadAligner::chainReadAlignments` input/output contract. The patch is
controlled by `CUFLYE_READ_ALIGNMENT_REPLAY_DUMP_DIR` and
`CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_ID`, requires `--threads 1`, and dumps the
selected read, graph edge sequences, graph edge adjacency, edge-overlap inputs,
chain divergence decisions, and accepted oracle `read-alignment-v1` records.

The DGX toy-hifi proof applied and built the patch series through
`0026-cuflye-read-alignment-replay-fixture-dump.patch`. The selected read was
query `200`:

```text
alignment_input_records=4
candidate_chains=1
oracle_chains=1
replayed_records=3
canonical_sha256=c8aa478626cad18a598140a00a39effba464c187109a2b71a2509806ff7aa802
canonical diff=match
```

The negative DGX run enabled replay fixture dumping with `--threads 2`; Flye
exited with status `1`, recorded expected failure metadata, found the
fail-closed message
`cuFlye read alignment replay fixture dump requires --threads 1`, and produced
no replay fixture manifest.

Allowed M5b claim:

```text
cuFlye can capture one deterministic read-to-graph replay fixture and reproduce
its accepted read-alignment-v1 oracle outside a full Flye run.
```

Forbidden M5b claim:

```text
M5b does not prove CUDA read-alignment acceleration, multi-read batching, graph
mutation consumption, default GPU mode, or end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M5c: implement the first CUDA/CPU benchmark prototype for the bounded
read-alignment chain replay fixture, preserving the replay oracle output while
measuring whether the chain DP hot path has a real GPU advantage.
```

Completed.

M5c adds a standalone CUDA/C++ binary,
`cuflye-cuda-read-alignment-chain-replay`, for
`read-alignment-replay-fixture-v0`. It supports explicit `cpu` and `cuda`
backends, emits `read-alignment-v1`, consumes M5b's recorded
`chain-divergence.tsv` acceptance decisions, and records warm benchmark timing.

The DGX proof built the prototype with `/usr/local/cuda/bin/nvcc` for
`sm_121` and ran the M5b toy-hifi read `200` fixture:

```text
input_records=4
output_records=3
canonical_sha256=c8aa478626cad18a598140a00a39effba464c187109a2b71a2509806ff7aa802
cpu vs oracle diff=match
cuda vs oracle diff=match
cpu vs cuda diff=match
```

Warm benchmark timing with `5` warmups and `200` timed runs:

```text
cpu_mean_total_before_json_ms=0.000482
cpu_mean_core_ms=0.000482
cuda_mean_total_before_json_ms=0.137072
cuda_mean_kernel_ms=0.012329
cuda_total_speedup_vs_cpu=0.003516x
cuda_core_speedup_vs_cpu=0.039095x
```

The bad-schema negative gate and CUDA memory-budget negative gate both failed
closed before writing success JSON/TSV.

Allowed M5c claim:

```text
cuFlye can replay one M5b read-to-graph chain DP fixture through a standalone
CUDA backend and reproduce the read-alignment-v1 oracle exactly.
```

Forbidden M5c claim:

```text
M5c does not prove CUDA is faster for this shape, multi-read batching, graph
mutation consumption, default GPU mode, edlib/base realignment replay, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M5d: collect and benchmark a deterministic multi-read read-alignment replay
fixture batch, then add packed CUDA execution so the chain DP proof has enough
parallel work to test whether GPU occupancy can beat the CPU baseline.
```

Completed as a controlled replicated-batch proof.

M5d adds `--replicate-fixture N` to
`cuflye-cuda-read-alignment-chain-replay`. The CPU backend repeats the same
fixture work `N` times. The CUDA backend packs `N` independent copies and
launches one block per logical fixture. The TSV output remains the first
representative `read-alignment-v1` result so the existing oracle diff gate stays
small and exact.

The DGX scan showed the crossover point for the M5b read `200` fixture:

```text
batch_size=1     total_speedup=0.003843x  core_speedup=0.044659x
batch_size=64    total_speedup=0.114514x  core_speedup=1.314436x
batch_size=1024  total_speedup=1.090091x  core_speedup=14.275613x
batch_size=4096  total_speedup=4.791615x  core_speedup=47.841914x
batch_size=16384 total_speedup=2.978410x  core_speedup=44.619671x
```

The selected stable proof used `batch_size=4096`, `5` warmups, and `200` timed
runs:

```text
total_input_records=16384
representative_output_records=3
canonical_sha256=c8aa478626cad18a598140a00a39effba464c187109a2b71a2509806ff7aa802
cpu_mean_total_before_json_ms=1.031995
cuda_mean_total_before_json_ms=0.323783
cuda_total_speedup_vs_cpu=3.187304x
cpu_mean_core_ms=1.031995
cuda_mean_kernel_ms=0.030339
cuda_core_speedup_vs_cpu=34.015459x
```

Representative CPU, CUDA, and oracle `read-alignment-v1` outputs canonical-diff
`match`. The replicated memory-budget negative gate used `budget=1` and failed
closed before writing success JSON/TSV.

Allowed M5d claim:

```text
cuFlye CUDA read-alignment chain replay is faster than the C++ CPU baseline for
the controlled replicated-batch M5b fixture at batch_size=4096 while preserving
the representative read-alignment-v1 oracle.
```

Forbidden M5d claim:

```text
M5d does not prove real multi-read Flye speedup, default GPU mode, graph
mutation consumption, or end-to-end Flye acceleration.
```

Next highest-ROI task:

```text
M5e: replace replicated-batch evidence with real multi-read replay fixture
harvest and packed CUDA execution, preserving per-read oracle diffs before any
Flye graph-consumption integration.
```

Completed.

M5e adds multi-query read-alignment replay fixture harvest with
`CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS`. In multi-query mode, Flye writes one
`read-alignment-replay-fixture-v0` directory per selected read under
`query_<id>/`, while the older single-query flat layout remains compatible with
M5b-M5d.

M5e also adds real multi-fixture batch mode to
`cuflye-cuda-read-alignment-chain-replay`:

```text
--batch-fixtures-file FILE
--batch-output-dir DIR
--batch-json-output PATH
```

The first packed CUDA contract requires same-shape fixtures: identical
`alignment_input_records`, identical chain-divergence row counts, and identical
replay parameters. Unsupported mixed-shape batches fail closed instead of
falling back.

The DGX proof applied and built Flye 2.9.6 plus patches through
`0027-cuflye-read-alignment-multi-replay-fixture-dump.patch`. A toy-hifi
multi-query harvest dumped `68` real read fixtures from one Flye run. The
largest useful same-shape group selected for packed replay contained `19` real
reads:

```text
query_ids=1069,1100,1229,1252,1279,1480,1500,1584,1716,1820,1909,1930,1989,2080,2214,2332,2345,2390,667
alignment_input_records_per_fixture=3
total_input_records=57
output_records=38
```

Every selected CPU batch output and CUDA batch output validated as
`read-alignment-v1`. CPU vs oracle, CUDA vs oracle, and CPU vs CUDA
canonical diffs were `match` for all `19` reads.

Warm benchmark timing with `5` warmups and `200` timed runs:

```text
cpu_mean_total_before_json_ms=0.003566
cpu_mean_core_ms=0.003566
cuda_mean_total_before_json_ms=0.233540
cuda_mean_kernel_ms=0.011199
cuda_total_speedup_vs_cpu=0.015269x
cuda_total_slowdown_vs_cpu=65.490746x
cuda_core_speedup_vs_cpu=0.318421x
cuda_required_bytes=9595
```

The negative gates passed:

```text
mixed_shape: unsupported read-alignment batch: alignment_input_records differ
memory_budget: CUDA memory budget exceeded for read-alignment batch
```

Allowed M5e claim:

```text
cuFlye can harvest multiple real Flye read-alignment replay fixtures, execute a
same-shape 19-read packed CPU/CUDA batch, and preserve every per-read
read-alignment-v1 oracle diff.
```

Forbidden M5e claim:

```text
M5e does not prove real-batch CUDA speedup, default GPU mode, graph mutation
consumption, heterogeneous-shape batching, edlib/base realignment replay, or
end-to-end Flye acceleration.
```

Next highest-ROI task:

```text
M5f: increase useful real read-alignment work per CUDA launch, either by
harvesting larger same-shape batches from non-toy data, adding heterogeneous
packing, or moving read-alignment replay into a persistent worker before any
graph-consumption integration.
```

Completed as explicit heterogeneous shape-group execution.

M5f adds `--allow-heterogeneous-batch` to
`cuflye-cuda-read-alignment-chain-replay`. Default mixed-shape batch input
still fails closed. With the explicit flag, the runner groups fixtures by the
CUDA-supported shape key:

```text
alignment_input_records
chain_divergence_rows
maximum_jump
max_read_overlap
minimum_overlap
max_separation
```

Each group runs through the existing packed CPU/CUDA batch path, and output is
written back as one `read-alignment-v1` TSV per original fixture. Batch JSON now
records `heterogeneous_batch`, `shape_group_count`, min/max input records, and
one `shape_groups` entry per grouped launch.

The DGX proof reused the M5e toy-hifi multi-query harvest and ran all `68` real
fixtures:

```text
shape_group_count=4
input_records=1: fixture_count=30, total_input_records=30
input_records=2: fixture_count=11, total_input_records=22
input_records=3: fixture_count=19, total_input_records=57
input_records=4: fixture_count=8,  total_input_records=32
total_input_records=141
output_records=114
```

Every CPU heterogeneous output and CUDA heterogeneous output validated as
`read-alignment-v1`. CPU vs oracle, CUDA vs oracle, and CPU vs CUDA canonical
diffs were `match` for all `68` reads.

Warm benchmark timing with `5` warmups and `200` timed runs:

```text
cpu_mean_total_before_json_ms=0.021866
cpu_mean_core_ms=0.021866
cuda_mean_total_before_json_ms=0.899946
cuda_mean_kernel_ms=0.044258
cuda_total_speedup_vs_cpu=0.024297x
cuda_total_slowdown_vs_cpu=41.157322x
cuda_core_speedup_vs_cpu=0.494058x
cuda_required_bytes=9595
```

The default mixed-shape negative gate failed closed without
`--allow-heterogeneous-batch`, and the CUDA memory-budget negative gate failed
closed before writing success JSON/TSV.

Allowed M5f claim:

```text
cuFlye can explicitly group a heterogeneous 68-read real replay fixture list
into 4 supported CUDA shape groups, run packed CPU/CUDA batches per group, and
preserve every per-read read-alignment-v1 oracle diff.
```

Forbidden M5f claim:

```text
M5f does not prove heterogeneous-batch CUDA speedup, default GPU mode, graph
mutation consumption, edlib/base realignment replay, or end-to-end Flye
acceleration.
```

Next highest-ROI task:

```text
M5g: remove grouped-launch overhead or increase batch scale. Prefer a
persistent grouped read-alignment worker with reusable device buffers, then
test on larger non-toy fixture harvests before graph-consumption integration.
```

Completed as a persistent per-shape CUDA arena.

M5g adds `--cuda-persistent-arena` to
`cuflye-cuda-read-alignment-chain-replay`. The mode is explicit, batch-only,
and CUDA-only. It keeps the existing default behavior: mixed-shape batches still
fail closed unless `--allow-heterogeneous-batch` is set.

Persistent arena mode groups the fixture list by the same M5f shape key, then
allocates one reusable device-buffer set per shape group. Static
overlap/divergence fixture inputs are copied once before warmup/timed runs.
The benchmark timing records steady-state kernel/device-to-host/finalize cost,
while `timing_ms.one_time_*` records arena setup/allocation/H2D separately.

The DGX proof reused the same M5e toy-hifi multi-query harvest and ran all
`68` real fixtures:

```text
shape_group_count=4
input_records=1: fixture_count=30, total_input_records=30, output_records=30
input_records=2: fixture_count=11, total_input_records=22, output_records=22
input_records=3: fixture_count=19, total_input_records=57, output_records=38
input_records=4: fixture_count=8,  total_input_records=32, output_records=24
total_input_records=141
output_records=114
```

Every CPU, cold CUDA, persistent CUDA, and oracle per-fixture
`read-alignment-v1` output validated and canonical-diffed as `match`.

Warm benchmark timing with `5` warmups and `200` timed runs:

```text
cpu_mean_total_before_json_ms=0.010628
cpu_mean_core_ms=0.010628
cold_cuda_mean_total_before_json_ms=0.871576
cold_cuda_mean_kernel_ms=0.043325
persistent_cuda_mean_total_before_json_ms=0.377181
persistent_cuda_mean_kernel_ms=0.020074
persistent_cuda_speedup_vs_cold_cuda=2.310763x
persistent_cuda_core_speedup_vs_cold_cuda=2.158264x
persistent_cuda_speedup_vs_cpu=0.028177x
persistent_cuda_slowdown_vs_cpu=35.489368x
persistent_cuda_core_speedup_vs_cpu=0.529441x
one_time_arena_setup_allocation_h2d_ms=243.870057
```

The negative gates passed:

```text
cpu_backend: --cuda-persistent-arena requires --backend cuda
memory_budget: CUDA memory budget exceeded for persistent read-alignment arena
mixed_shape_default: unsupported read-alignment batch: alignment_input_records differ
```

Allowed M5g claim:

```text
cuFlye can explicitly reuse per-shape CUDA read-alignment arenas across
benchmark iterations for the 68-read heterogeneous M5e replay fixture set while
preserving every per-read oracle diff.
```

Forbidden M5g claim:

```text
M5g does not prove end-to-end Flye acceleration, default GPU mode, graph
mutation consumption, edlib/base realignment replay, or CUDA read-alignment
speedup over CPU for this small fixture set.
```

Next highest-ROI task:

```text
M5h: increase real read-alignment work per persistent CUDA invocation. Prefer
larger non-toy fixture harvests or a long-lived persistent read-alignment
worker before any graph-consumption integration.
```

Completed as a larger read-alignment fixture harvest and persistent-arena
diagnostic proof.

M5h adds `tools/select_read_alignment_fixture_batch.py`, a deterministic scanner
for `cuflye-read-alignment-replay-fixture-v0` directories. It validates fixture
shape, validates `oracle.read-alignment.tsv`, writes a selected fixture list,
and records shape distribution plus invalid fixture exclusions.

The DGX proof requested toy-hifi query ids `1..6000` through the existing M5e
multi-query replay dump protocol. The harvest produced:

```text
discovered_fixture_count=3577
valid_selected_fixture_count=3546
invalid_fixture_count=31
invalid_reason=read alignment dump is empty
shape_group_count=4
selected_total_input_records=3781
selected_total_oracle_records=3616
```

Selected shape distribution:

```text
input_records=1: fixture_count=3418, total_input_records=3418, total_oracle_records=3418
input_records=2: fixture_count=29,   total_input_records=58,   total_oracle_records=45
input_records=3: fixture_count=91,   total_input_records=273,  total_oracle_records=129
input_records=4: fixture_count=8,    total_input_records=32,   total_oracle_records=24
```

Every CPU, cold CUDA, persistent CUDA, and oracle per-fixture
`read-alignment-v1` output validated and canonical-diffed as `match` across all
`3546` selected fixtures.

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

M5i adds `--cuda-persistent-bulk-output`, an explicit CUDA batch mode layered on
top of `--cuda-persistent-arena`. It keeps the same kernel and per-fixture
`DeviceSummary` contract, but copies one output buffer per shape group and
slices that host buffer into the existing per-fixture `read-alignment-v1`
outputs.

The DGX proof reused the M5h larger selected fixture list:

```text
selected_fixture_count=3546
selected_total_input_records=3781
selected_total_output_records=3616
shape_group_count=4
```

Every oracle, CPU, current persistent CUDA, and bulk persistent CUDA
per-fixture `read-alignment-v1` output validated and canonical-diffed as
`match` across all `3546` selected fixtures.

Warm benchmark timing with `5` warmups and `50` timed runs:

```text
cpu_mean_total_before_json_ms=0.333798
cpu_mean_core_ms=0.333798
current_persistent_cuda_mean_total_before_json_ms=17.862780
current_persistent_cuda_mean_kernel_ms=0.025782
current_persistent_cuda_device_to_host_ms=17.680561
bulk_persistent_cuda_mean_total_before_json_ms=0.302834
bulk_persistent_cuda_mean_kernel_ms=0.025953
bulk_persistent_cuda_device_to_host_ms=0.223648
bulk_total_speedup_vs_cpu=1.102247x
bulk_total_speedup_vs_current_persistent=58.985385x
bulk_d2h_speedup_vs_current_persistent_d2h=79.055306x
bulk_core_speedup_vs_cpu_core=12.861634x
```

Allowed M5i claim:

```text
cuFlye can run the bounded M5h read-alignment chain replay harvest through an
explicit persistent CUDA bulk-output mode faster than the CPU replay baseline
before TSV/JSON emission while preserving every per-read oracle diff.
```

Forbidden M5i claim:

```text
M5i does not prove default GPU mode, Flye graph mutation consumption,
edlib/base realignment replay, or end-to-end Flye acceleration.
```

M5j adds `0028-cuflye-read-alignment-graph-dry-run-seam.patch`, an explicit
Flye-side read-alignment worker dry-run seam selected by:

```text
CUFLYE_READ_ALIGNMENT_WORKER_MODE=cuda-bulk-persistent-v0
CUFLYE_READ_ALIGNMENT_GRAPH_CONSUMPTION_MODE=dry-run-v0
```

The seam reuses the M5b/M5e replay fixture dump boundary, invokes
`cuflye-cuda-read-alignment-chain-replay` with
`--cuda-persistent-arena --cuda-persistent-bulk-output`, validates every worker
output against the fixture oracle, writes graph guard metadata, and then stops
before graph mutation.

The DGX positive proof used toy-hifi query ids `5,47,200,204`:

```text
worker_mode=cuda-bulk-persistent-v0
cuda_execution_mode=persistent-arena-bulk-output
worker_validation_status=passed
fixture_count=4
validated_fixture_count=4
independent_python_oracle_diffs=4/4 match
graph_guard_status=passed
graph_consumption_state=not-consumed
graph_mutation_consumed_worker_output=false
run_status=stopped-before-graph-mutation
```

The DGX negative proof enabled the same seam for query ids `5,47` without
`CUFLYE_READ_ALIGNMENT_WORKER_BIN`. It failed closed with:

```text
worker_validation_status=worker-failed
graph_guard_status=failed
graph_consumption_state=failed-closed
graph_mutation_consumed_worker_output=false
```

Allowed M5j claim:

```text
cuFlye can invoke the M5i CUDA read-alignment replay backend from inside a real
Flye run, validate CUDA output against CPU oracle output, and write graph guard
metadata while still stopping before graph mutation.
```

Forbidden M5j claim:

```text
M5j does not prove default GPU mode, replacement of Flye _readAlignments, graph
mutation consumption, or end-to-end Flye acceleration.
```

M5k accepted result:

```text
cuFlye can convert validated CUDA read-alignment worker TSV rows into
Flye-side GraphAlignment-shaped typed records, confirm current repeat-graph
edge identity, validate chain segment continuity, canonicalize the typed
records back to read-alignment fields, and match the CPU oracle while still
stopping before graph mutation.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5k-proof-20260701T005103Z
positive_query_ids=5,47,200,204
worker_validation_status=passed
graph_guard_status=passed
read_alignment_rehydration_status=passed
read_alignment_rehydration_state=not-consumed
read_alignment_rehydration_total_records=7
read_alignment_rehydration_total_chains=4
graph_mutation_consumed_worker_output=false
```

The DGX negative proof enabled
`CUFLYE_READ_ALIGNMENT_REHYDRATION_PROOF_FAULT=drop-first-worker-record` for
query ids `5,47`. Worker validation and graph guard both passed first, then
typed rehydration failed closed with:

```text
read_alignment_rehydration_status=failed
read_alignment_rehydration_state=failed-closed
read_alignment_rehydration_decision=failed-closed-before-graph-mutation
graph_mutation_consumed_worker_output=false
```

Allowed M5k claim:

```text
cuFlye can convert validated CUDA read-alignment output into Flye-side
GraphAlignment-shaped typed records, prove that the typed records still match
the CPU oracle, and still stop before graph mutation.
```

Forbidden M5k claim:

```text
M5k does not prove default GPU mode, replacement of Flye _readAlignments, graph
mutation consumption, or end-to-end Flye acceleration.
```

M5l accepted result:

```text
cuFlye can group validated CUDA read-alignment typed segments into a shadow
std::vector<GraphAlignment> object-vector, compare the object vector against
the CPU _readAlignments slice for selected reads, and still stop before graph
mutation.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5l-proof-20260701T010956Z
positive_query_ids=5,47,200,204
worker_validation_status=passed
graph_guard_status=passed
read_alignment_rehydration_status=passed
read_alignment_object_rehydration_status=passed
read_alignment_object_rehydration_state=not-consumed
object_representation=graph-alignment-object-vector-v0
total_object_records=7
total_object_chains=4
graph_mutation_consumed_worker_output=false
```

The DGX negative proof enabled
`CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_PROOF_FAULT=drop-first-graph-alignment-chain`
for query ids `5,47`. Worker validation, graph guard, and M5k typed
rehydration passed first. Object-vector comparison then failed closed with:

```text
read_alignment_object_rehydration_status=failed
read_alignment_object_rehydration_state=failed-closed
read_alignment_object_rehydration_decision=failed-closed-before-graph-mutation
graph_mutation_consumed_worker_output=false
```

Allowed M5l claim:

```text
cuFlye can convert validated CUDA read-alignment output into a shadow
std::vector<GraphAlignment>, prove that it matches the CPU _readAlignments
slice, and still stop before graph mutation.
```

Forbidden M5l claim:

```text
M5l does not prove default GPU mode, replacement of Flye _readAlignments, graph
mutation consumption, or end-to-end Flye acceleration.
```

M5m accepted result:

```text
cuFlye can substitute a verified CUDA-derived GraphAlignment object vector for a
small selected _readAlignments slice, preserve exact Flye artifacts, and fail
closed on mismatch before graph mutation.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5m-proof-20260701T013646Z
positive_query_ids=5,47,200,204
worker_validation_status=passed
graph_guard_status=passed
read_alignment_rehydration_status=passed
read_alignment_object_rehydration_status=passed
read_alignment_vector_substitution_status=passed
read_alignment_vector_substitution_state=consumed
total_cpu_records=7
total_object_records=7
total_substituted_chains=4
graph_facing_returned_worker_output=true
graph_mutation_consumed_worker_output=true
positive_vs_cpu_canonical_diff=match
```

The DGX negative proof enabled
`CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-chain`
for query ids `5,47`. Worker validation, graph guard, typed rehydration, and
object-vector rehydration passed first. Vector substitution then failed closed
with:

```text
read_alignment_vector_substitution_status=failed
read_alignment_vector_substitution_state=failed-closed
read_alignment_vector_substitution_decision=failed-closed-before-graph-mutation
graph_facing_returned_worker_output=false
graph_mutation_consumed_worker_output=false
```

Allowed M5m claim:

```text
cuFlye can let verified CUDA-derived read-alignment output cross the first real
Flye _readAlignments consumption boundary for a selected tiny slice, while
preserving exact canonical Flye artifacts and fail-closing before graph mutation
on mismatch.
```

Forbidden M5m claim:

```text
M5m does not prove default GPU mode, broad _readAlignments replacement, removal
of CPU read alignment, or end-to-end Flye acceleration.
```

M5n accepted result:

```text
cuFlye can emit read-alignment pre-divergence chain DP output from the CUDA
worker without reading CPU-generated chain-divergence acceptance rows, and the
CPU/CUDA pre-divergence outputs match on a real fixture.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5n-proof-20260701T015602Z
fixture=query_3512_no_divergence
chain_divergence_present=false
oracle_read_alignment_present=false
alignment_input_records=4
cpu_output_mode=pre-divergence-chains
cuda_output_mode=pre-divergence-chains
uses_fixture_divergence_acceptance=false
cpu_output_records=3
cuda_output_records=3
cpu_vs_cuda_pre_divergence_diff=match
canonical_sha256=c817d867dfa173d28f76ebe9b19274e2d54db650ed87fa5bc3811a17a1e3e67f
```

The negative DGX gate enabled `--emit-pre-divergence-chains` in batch mode.
The worker rejected it fail-closed with:

```text
error: --emit-pre-divergence-chains is only supported in single-fixture mode
```

Allowed M5n claim:

```text
cuFlye can run the read-alignment chain DP replay on CUDA without depending on
CPU-generated divergence acceptance rows, producing the same pre-divergence
chain output as the CPU replay for a real fixture.
```

Forbidden M5n claim:

```text
M5n does not prove Flye graph-facing consumption of pre-divergence CUDA output,
default GPU mode, CUDA minimizer overlap discovery, CPU divergence replacement,
or end-to-end Flye acceleration.
```

Plain-language benefit:

```text
M5n is not a full-Flye speed win. On the tiny single fixture, CUDA total time is
slower than CPU. The gain is architectural: the CUDA chain worker no longer
needs CPU divergence rows, so a later Flye-side selected-read mode can skip CPU
chainReadAlignments and run divergence filtering on GPU-produced chains.
```

M5o accepted result:

```text
cuFlye can invoke CUDA pre-divergence read-alignment chain output from inside
Flye, run Flye's existing divergence filter on the GPU-produced chains, and
prove the resulting goodChains match the CPU selected-read goodChains.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5o-proof-20260701T021134Z
query_id=3512
positive_status=passed
positive_cpu_predivergence_chains=1
positive_gpu_predivergence_chains=1
positive_cpu_good_records=3
positive_gpu_good_records=3
positive_canonical_diff=match
negative_fault=drop-first-gpu-good-chain
negative_exit_status=1
negative_failed_closed=true
negative_worker_exit_status=0
negative_worker_tsv_readable=true
graph_mutation_consumed_worker_output=false
```

Allowed M5o claim:

```text
cuFlye can request CUDA pre-divergence read-alignment chains from inside Flye
for an allowlisted read, run CPU divergence filtering on those GPU-produced
chains, recover the same goodChains as CPU, preserve exact artifacts, and fail
closed on mismatch.
```

Forbidden M5o claim:

```text
M5o does not prove default GPU mode, broad _readAlignments replacement from
pre-divergence output, CUDA minimizer overlap discovery, CPU divergence
replacement, or end-to-end Flye acceleration.
```

Plain-language benefit:

```text
M5o is not a full-Flye speed win. The gain is integration safety: CUDA
pre-divergence chain output can now enter Flye's read-alignment loop and pass
Flye's own divergence/filtering semantics without changing final artifacts.
```

Next highest-ROI task:

```text
M5p: remove selected-read per-read process overhead by moving pre-divergence
chain output into a batched or persistent Flye-side dry-run seam, then measure
whether the integration path can become cheaper than CPU chainReadAlignments on
a supported batch.
```

M5p accepted result:

```text
cuFlye can batch selected Flye read-alignment pre-divergence CUDA chain output
into one worker invocation, let Flye apply its existing divergence filtering per
query, and prove all selected GPU-filtered goodChains match CPU goodChains.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5p-proof-20260701T023808Z
query_ids=5,47,200,204,3512
positive_status=passed
positive_fixture_count=5
positive_matched_fixture_count=5
positive_total_cpu_good_records=10
positive_total_gpu_good_records=10
positive_canonical_diff=match
positive_worker_wall_ms=446.799500
worker_setup_ms=313.588244
worker_kernel_ms=0.148640
worker_device_to_host_ms=0.074208
worker_write_output_ms=0.298688
negative_fault=drop-first-gpu-good-chain
negative_exit_status=1
negative_worker_exit_status=0
negative_matched_fixture_count=4
negative_mismatched_fixture_count=1
negative_failed_closed=true
graph_mutation_consumed_worker_output=false
```

Allowed M5p claim:

```text
cuFlye can run one CUDA pre-divergence read-alignment batch worker for multiple
selected Flye reads, rehydrate the GPU chains, apply Flye's existing divergence
filter per query, preserve exact artifacts, and fail closed on mismatch.
```

Forbidden M5p claim:

```text
M5p does not prove default GPU mode, broad _readAlignments replacement, CUDA
minimizer overlap discovery, CPU divergence replacement, or end-to-end Flye
acceleration.
```

Plain-language benefit:

```text
M5p is not a full-Flye speed win. It removes M5o's per-selected-read worker
process overhead: five selected reads now share one CUDA worker process and one
batch audit. The measurement also shows the next blocker clearly: CUDA setup
dominates this tiny batch, while kernel/output-copy time is already small.
```

Next highest-ROI task:

```text
M5q: use the M5p batch seam on larger selected-read batches and compare CPU
versus CUDA pre-divergence replay timing to find the crossover point or prove
that setup/process overhead remains the dominant blocker.
```

M5q accepted result:

```text
cuFlye can benchmark larger selected read-alignment pre-divergence replay
batches, prove CUDA outputs match CPU across the same fixture list, and show
that a warmed persistent-bulk CUDA path has crossed the CPU hot-path boundary
for the full M5h 3546-fixture batch.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5q-proof-20260701T025345Z
fixture_list=/tmp/cuflye-m5h-proof-20260630T234728Z/out/m5h/larger-batch/selected-fixtures.list
cold_batch_sizes=16,64,256,1024,3546
cold_outputs_match_cpu=true
full_batch_cold_cpu_ms=0.402465
full_batch_cold_cuda_persistent_bulk_single_invocation_ms=247.104709
full_batch_warm_cpu_ms=0.324878
full_batch_warm_cuda_persistent_bulk_ms=0.300236
full_batch_warm_cuda_hot_path_speedup_vs_cpu=1.082075
full_batch_warm_cuda_single_invocation_ms=249.070891
single_invocation_crossover_batch_size=null
flye_positive_selected_query_count=64
flye_positive_status=passed
flye_positive_matched_fixture_count=64
flye_positive_canonical_diff=match
flye_positive_worker_wall_ms=435.505899
worker_setup_ms=301.297979
worker_kernel_ms=0.096576
worker_device_to_host_ms=2.980852
worker_write_output_ms=1.569866
graph_mutation_consumed_worker_output=false
```

Allowed M5q claim:

```text
On the M5h 3546-fixture selected read-alignment replay set, a warmed
persistent-bulk CUDA pre-divergence hot path is slightly faster than CPU before
JSON/TSV emission, while all CUDA outputs match CPU and a Flye-side 64-read
batch dry-run preserves exact artifacts.
```

Forbidden M5q claim:

```text
M5q does not prove end-to-end Flye acceleration or a default GPU mode. A single
Flye worker invocation still loses badly after CUDA setup/context cost is
counted.
```

Plain-language benefit:

```text
M5q found the boundary clearly. CUDA is better only after the context and
persistent arena are warm: full-batch warm persistent-bulk CUDA ran in
0.300236 ms versus CPU at 0.324878 ms, a 1.082x hot-path speedup. But Flye
currently launches a fresh worker, so the single-invocation path is still about
249.07 ms, dominated by CUDA setup. The useful win is real, but it is trapped
behind process/context setup.
```

Next highest-ROI task:

```text
M5r: replace the Flye-side pre-divergence batch worker process with a
long-lived session/persistent worker proof so selected batches can reuse CUDA
context and arena across Flye calls, then re-measure batch64 and larger
selected-read integration timing.
```

M5r accepted result:

```text
cuFlye can run the selected Flye read-alignment pre-divergence batch through a
long-lived file-backed CUDA session. The actual Flye-side batch64 request is
the second session request, hits the cached CUDA arena, preserves exact
canonical Flye artifacts, and fails closed on an injected mismatch.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5r-proof-20260701T032358Z
golden=tests/golden/cuflye-m5r-read-alignment-pre-divergence-persistent-session-dgx-aarch64.json
positive_selected_query_count=64
positive_status=passed
positive_matched_fixture_count=64
positive_canonical_diff=match
positive_worker_lifecycle_mode=session-file-v0
positive_worker_warmup_wall_ms=6.173764
positive_worker_actual_wall_ms=4.139341
positive_actual_response_request_ordinal=2
positive_actual_response_arena_cache_hit=true
positive_actual_response_request_total_ms=2.750920
m5q_fresh_worker_wall_ms=435.505899
selected_batch64_worker_wall_improvement_vs_m5q=105.211409x
selected_batch64_request_total_improvement_vs_m5q=158.312819x
negative_fault=drop-first-gpu-good-chain
negative_status=failed
negative_failed_closed=true
negative_matched_fixture_count=63
negative_mismatched_fixture_count=1
negative_graph_mutation_consumed_worker_output=false
full3546_cpu_backend_mean_total_before_json_ms=0.408065
full3546_cuda_session_backend_mean_total_before_json_ms=0.298561
full3546_cuda_backend_speedup_vs_cpu=1.366773x
full3546_cuda_session_request_total_ms=91.698238
```

Allowed M5r claim:

```text
M5r proves that a long-lived CUDA session removes the fresh-process/context
setup blocker for the selected pre-divergence read-alignment batch seam, and
that the full3546 scoped backend hot path is faster on CUDA than CPU.
```

Forbidden M5r claim:

```text
M5r still does not prove full Flye acceleration, default GPU mode, broad
_readAlignments replacement, CUDA minimizer overlap discovery, or replacement
of Flye's CPU divergence/base-alignment stages. Full request time for full3546
is still dominated by per-fixture TSV/JSON output.
```

Plain-language benefit:

```text
M5r finally separates the real GPU win from the integration tax. For the
Flye-selected 64-read proof, session mode cuts the worker wall segment from
435.505899 ms to 4.139341 ms while keeping exact artifacts. For the larger
3546-fixture backend hot path, CUDA beats CPU by 1.366773x. The remaining
problem is no longer CUDA setup; it is host-side output materialization.
```

Next highest-ROI task:

```text
M5s: reduce or bypass per-fixture TSV/JSON emission for the session path by
returning a compact verified object-vector or shared artifact payload, then
measure whether the graph-facing read-alignment path keeps the full3546 CUDA
backend advantage after host output overhead is removed.
```

M5s accepted result:

```text
cuFlye can run the full3546 read-alignment pre-divergence CUDA session request
in compact-output mode, produce a single deterministic compact JSONL artifact
that byte-matches the CPU compact oracle, skip all per-fixture TSV files, and
reduce full3546 session request time by removing host-side small-file output.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5s-proof-20260701T033744Z
golden=tests/golden/cuflye-m5s-read-alignment-session-output-overhead-reduction-dgx-aarch64.json
fixture_count=3546
compact_cmp=match
compact_jsonl_bytes=1126769
compact_sha256=2b0371e45c7b6c100c169ffed3829738db93b308f4d5aa55690ddc286f19f2bd
cpu_compact_backend_mean_total_before_json_ms=0.422561
cpu_compact_write_output_ms=3.221193
cpu_compact_per_fixture_files=0
cuda_actual_request_ordinal=2
cuda_actual_arena_cache_hit=true
cuda_actual_backend_mean_total_before_json_ms=0.442834
cuda_actual_write_output_ms=3.975386
cuda_actual_request_total_ms=4.450572
cuda_actual_per_fixture_files=0
m5r_full3546_cuda_session_request_total_ms=91.698238
cuda_compact_request_total_speedup_vs_m5r=20.603697x
negative_fault=compact_output_only_without_compact_output_jsonl
negative_status=error
negative_worker_exit_code=1
```

Allowed M5s claim:

```text
cuFlye can run the full3546 read-alignment pre-divergence CUDA session request
in compact-output mode, produce a single deterministic compact JSONL artifact
that byte-matches the CPU compact oracle, and reduce full3546 session request
time from M5r's 91.698238 ms to 4.450572 ms.
```

Forbidden M5s claim:

```text
M5s still does not prove full Flye acceleration, default GPU mode, broad
_readAlignments replacement, CUDA minimizer overlap discovery, or replacement
of Flye's CPU divergence/base-alignment stages. The remaining compact JSONL
write still dominates request time.
```

Plain-language benefit:

```text
M5s removes the thousands-of-small-files tax. It turns the full3546 session
output into one compact, deterministic file and keeps CPU/CUDA artifacts
byte-identical. That is why request time falls by about 20.6x versus M5r. It is
not yet the final graph-facing payload: 1.1 MB of JSONL still costs about 4 ms
to write.
```

Next highest-ROI task:

```text
M5t: replace the compact JSONL proof payload with a smaller graph-facing binary
or object-vector payload, then validate and rehydrate it before graph mutation
while measuring whether payload write/read cost falls below M5s.
```

M5t accepted result:

```text
cuFlye can write the full3546 read-alignment pre-divergence session output as
compact-binary-v0, validate the payload with schema/count/checksum/length
gates, byte-match the CPU compact binary oracle, and reduce M5s compact-output
request time.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5t-proof-20260701T035137Z
golden=tests/golden/cuflye-m5t-read-alignment-compact-binary-payload-dgx-aarch64.json
fixture_count=3546
binary_cmp=match
binary_payload_bytes=332736
m5s_jsonl_payload_bytes=1126769
payload_size_reduction_ratio_vs_m5s_jsonl=3.386375x
cpu_binary_sha256=daaaf20276447d1e3656b36beb9f8ca21b9673cb99372b66521e7ccf2af8d4df
cuda_actual_binary_sha256=daaaf20276447d1e3656b36beb9f8ca21b9673cb99372b66521e7ccf2af8d4df
cpu_binary_write_output_ms=1.030275
cuda_actual_request_ordinal=2
cuda_actual_arena_cache_hit=true
cuda_actual_backend_mean_total_before_json_ms=0.417153
cuda_actual_write_output_ms=1.811909
cuda_actual_request_total_ms=2.273654
m5s_cuda_actual_request_total_ms=4.450572
cuda_actual_request_speedup_vs_m5s=1.957454x
negative_bad_magic_status=error
negative_bad_count_status=error
negative_bad_checksum_status=error
negative_truncated_status=error
```

Allowed M5t claim:

```text
cuFlye can write the full3546 read-alignment pre-divergence session output as
compact-binary-v0, validate the payload with schema/count/checksum/length
gates, byte-match the CPU compact binary oracle, and reduce M5s compact-output
request time from 4.450572 ms to 2.273654 ms.
```

Forbidden M5t claim:

```text
M5t does not prove default GPU mode, full Flye acceleration, broad
_readAlignments replacement, CUDA minimizer overlap discovery, replacement of
Flye's CPU divergence/base-alignment stages, or Flye-side binary consumption.
```

Plain-language benefit:

```text
M5t turns the compact proof file from text into a machine-facing binary. That
cuts payload size to about 29.5% of M5s JSONL, halves the CUDA request time for
the same full3546 session proof, and keeps CPU/CUDA output byte-identical. The
remaining work is to prove Flye itself can safely validate and rehydrate this
binary payload.
```

Next highest-ROI task:

```text
M5u: move compact-binary-v0 into the Flye-side pre-divergence dry-run seam,
validate and rehydrate it inside Flye, apply Flye's existing divergence filter,
and fail closed on corrupted payloads before graph mutation.
```

M5u accepted result:

```text
cuFlye can request compact-binary-v0 pre-divergence read-alignment chains from
a CUDA session inside Flye, validate and rehydrate that binary payload in the
Flye seam, apply Flye's existing divergence filter, match CPU goodChains for
the selected batch, preserve exact canonical Flye artifacts, and fail closed on
corrupted binary payloads before graph mutation.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5u-proof-20260701T041315Z
golden=tests/golden/cuflye-m5u-read-alignment-compact-binary-flye-rehydration-dgx-aarch64.json
fixture_count=64
compact_binary_mode=rehydrate-v0
positive_status=passed
positive_canonical_diff=match
positive_matched_fixture_count=64
positive_worker_actual_wall_ms=2.084782
positive_worker_request_total_ms=0.203472
positive_worker_write_output_ms=0.094400
positive_compact_binary_bytes=5952
positive_compact_binary_sha256=f6dc209fad4311c61396f93ad240f56928557dc0b70f6c947c6991d2f2047504
m5r_selected_batch64_worker_actual_wall_ms=4.139341
m5r_selected_batch64_worker_request_total_ms=2.750920
m5u_selected_batch64_session_wall_speedup_vs_m5r=1.985503x
m5u_selected_batch64_worker_request_speedup_vs_m5r=13.519895x
negative_truncate_status=failed
negative_truncate_error=compact binary payload size mismatch
negative_checksum_status=failed
negative_checksum_error=compact binary checksum mismatch
graph_mutation_consumed_worker_output=false
```

Allowed M5u claim:

```text
cuFlye can request, validate, and rehydrate compact-binary-v0 CUDA
pre-divergence read-alignment output inside Flye, match CPU goodChains for the
selected batch, preserve exact artifacts, and cut selected batch64 Flye-session
worker wall time from M5r's 4.139341 ms to 2.084782 ms.
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
byte-identical. This cuts selected batch64 session wall time by about 2x versus
M5r and cuts the worker's actual request_total by about 13.5x, but it is still
not a whole-Flye speed claim because the verified output is not yet the default
read-alignment path.
```

Next highest-ROI task:

```text
M5v: after the compact-binary-v0 Flye seam validates and matches CPU
goodChains for an allowlisted batch, run a guarded vector-substitution smoke
that feeds the verified GPU-derived goodChains into the selected
_readAlignments slice while preserving exact artifacts and fail-closed
behavior.
```

M5v accepted result:

```text
cuFlye can substitute verified compact-binary-v0 CUDA-derived read-alignment
goodChains into the selected _readAlignments slice inside Flye, preserve exact
canonical artifacts, and fail closed before graph mutation on mismatch or
corrupted compact binary payloads.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5v-proof-20260701T042828Z
golden=tests/golden/cuflye-m5v-read-alignment-compact-binary-vector-substitution-smoke-dgx-aarch64.json
fixture_count=64
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
cuFlye can feed verified compact-binary CUDA-derived goodChains into Flye's
selected _readAlignments slice, preserve exact artifacts, and block mismatch or
corruption before graph mutation.
```

Forbidden M5v claim:

```text
M5v does not prove default GPU mode, full Flye acceleration, unbounded
_readAlignments replacement, CUDA minimizer overlap discovery, or a new speedup
over M5u.
```

Plain-language benefit:

```text
M5v is the first compact-binary path that actually feeds verified GPU-derived
goodChains back into Flye's selected _readAlignments slice. It keeps the
assembly byte-identical and proves mismatch or corrupted binary payloads do not
get consumed. It does not add a meaningful speedup over M5u by itself; the
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

M5w accepted result:

```text
cuFlye can scale guarded compact-binary-v0 CUDA-derived read-alignment
goodChains substitution from selected batch64 to the full3546 selected fixture
set inside Flye, preserve exact canonical artifacts, and fail closed before
graph mutation on corrupted compact binary payloads.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5w-proof-20260701T043703Z
golden=tests/golden/cuflye-m5w-read-alignment-compact-binary-substitution-scaleup-dgx-aarch64.json
fixture_count=3546
compact_binary_mode=rehydrate-v0
compact_binary_vector_substitution_mode=verified-goodchains-v0
positive_status=passed
positive_canonical_diff=match
positive_matched_fixture_count=3546
positive_total_worker_records=3616
positive_total_substituted_chains=3546
positive_graph_mutation_consumed_worker_output=true
positive_worker_actual_wall_ms=4.162895
positive_worker_request_total_ms=2.263903
positive_worker_kernel_ms=0.041136
positive_compact_binary_bytes=332736
positive_compact_binary_sha256=daaaf20276447d1e3656b36beb9f8ca21b9673cb99372b66521e7ccf2af8d4df
positive_full_flye_elapsed_seconds=20.765673444
negative_truncate_status=failed
negative_truncate_flye_exit_status=1
negative_truncate_worker_request_total_ms=1.519952
negative_truncate_graph_mutation_consumed_worker_output=false
negative_truncate_total_substituted_chains=0
negative_truncate_full_flye_elapsed_seconds=14.521368179
```

Allowed M5w claim:

```text
cuFlye can scale selected-slice compact-binary CUDA goodChains substitution to
the full3546 selected toy-hifi fixture set, preserve exact artifacts, and block
corrupted compact binary payloads before graph mutation.
```

Forbidden M5w claim:

```text
M5w does not prove default GPU mode, whole-Flye acceleration, unbounded
_readAlignments replacement, CUDA minimizer overlap discovery, or CPU
read-alignment bypass.
```

Plain-language benefit:

```text
M5w proves the compact-binary GPU path scales from a 64-read smoke to the
full3546 selected fixture set inside Flye. All selected chains are replaced by
verified CUDA-derived goodChains, the final assembly artifacts still match CPU
exactly, and corrupted payloads stop before graph mutation. The direct speed
benefit is still limited because this seam intentionally keeps CPU goodChains
as the live verifier; the value is that the GPU payload and substitution path
now work at the full selected scale, which makes CPU-bypass the next meaningful
performance step.
```

Next highest-ROI task:

```text
M5x: run an audited selected-read CPU-bypass experiment for compact-binary-v0
CUDA goodChains. The point is to stop paying CPU chain DP for the explicit
selected allowlist, preserve exact canonical artifacts, and keep the same
fail-closed behavior before making any default GPU-mode claim.
```

M5x accepted result:

```text
cuFlye can run an opt-in selected-read CPU-bypass mode for the full3546
read-alignment fixture set: Flye skips selected CPU pre-divergence chain DP,
consumes verified compact-binary CUDA-derived goodChains, preserves exact
canonical artifacts, and fails closed before graph mutation on corrupted
compact binary payloads.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5x-proof-20260701T050004Z
golden=tests/golden/cuflye-m5x-read-alignment-selected-cpu-bypass-dgx-aarch64.json
fixture_count=3546
selected_cpu_bypass_mode=verified-goodchains-v0
selected_cpu_bypass_enabled=true
positive_status=passed
positive_canonical_diff=match
positive_total_cpu_bypassed_reads=3546
positive_total_cpu_predivergence_chains=0
positive_total_cpu_good_chains=0
positive_total_cpu_bypass_inserted_chains=3546
positive_total_worker_records=3616
positive_total_substituted_chains=3546
positive_graph_mutation_consumed_worker_output=true
positive_worker_actual_wall_ms=4.145493
positive_worker_request_total_ms=2.128259
positive_worker_kernel_ms=0.042353
positive_full_flye_elapsed_seconds=20.741208213
m5w_full_flye_elapsed_seconds=20.765673444
m5x_full_flye_speedup_vs_m5w=1.001179547
m5x_full_flye_wall_seconds_saved_vs_m5w=0.024465231
negative_truncate_status=failed
negative_truncate_flye_exit_status=1
negative_truncate_selected_cpu_bypass_enabled=true
negative_truncate_total_cpu_bypassed_reads=3546
negative_truncate_graph_mutation_consumed_worker_output=false
negative_truncate_total_substituted_chains=0
```

Allowed M5x claim:

```text
cuFlye can skip selected CPU pre-divergence read-alignment chain DP for the
full3546 selected toy-hifi set, consume verified CUDA goodChains, preserve
exact artifacts, and show a small local request-time and tiny full-toy wall-time
improvement versus M5w.
```

Forbidden M5x claim:

```text
M5x does not prove default GPU mode, meaningful whole-Flye acceleration,
unbounded _readAlignments replacement, CUDA minimizer overlap discovery, or CPU
overlap-detection bypass.
```

Plain-language benefit:

```text
M5x is the first real CPU-bypass milestone for read alignment: for the full3546
selected set, Flye no longer calculates CPU pre-divergence chains and then
replaces them; it leaves audited placeholders, consumes verified CUDA
goodChains, and still produces byte-equivalent canonical artifacts. The
measurable whole-toy Flye gain is tiny, about 0.024 seconds, so the honest
claim is local correctness plus a small scoped speed win, not a meaningful
end-to-end GPU Flye speedup.
```

M6g accepted result:

```text
cuFlye's external full-query-hit replay now models Flye's libstdc++
std::sort equal-key ordering and reaches row-key equality for the selected
read-to-graph raw-overlap source pack.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m6g-proof-20260701T065424Z
golden=tests/golden/cuflye-m6g-query-hit-replay-tie-closure-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
source_pack_ab_canonical_match=true
replay_raw_overlaps_sha256=2e1201a2e768ed682afc6b0feb90d50aeeea8ad66597861c6c61ba062a34e420
replay_ab_raw_overlap_match=true
replay_status=match
row_key_exact_match=true
geometry_match=true
matched_rows=36
missing_rows=0
extra_rows=0
non_key_field_mismatch_rows=36
baseline_vs_source_a=match
baseline_vs_source_b=match
```

Allowed M6g claim:

```text
cuFlye can replay the selected M6f full-query-hit source pack to row-key
equality for read/edge coordinates and scores while preserving deterministic
source-pack and replay hashes.
```

Forbidden M6g claim:

```text
M6g does not prove CUDA replay, full non-key field reproduction, graph
consumption, default GPU mode, or whole-Flye speedup.
```

Plain-language benefit:

```text
M6g does not make Flye faster yet. It removes the last "why does the replay not
match Flye?" blocker by modeling the C++ sorting detail that changed one query
and edge. The next CUDA step now has a clean target: reproduce the same
coordinates and scores from full query-hit input.
```

M6h accepted result:

```text
cuFlye now has a standalone CUDA full-query-hit replay consumer that emits raw
overlap records canonical row-key-equivalent to the M6g CPU replay for the
selected source pack.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m6h-proof-20260701T070728Z
golden=tests/golden/cuflye-m6h-cuda-full-query-hit-replay-consumer-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
cpu_replay_raw_overlaps_sha256=2e1201a2e768ed682afc6b0feb90d50aeeea8ad66597861c6c61ba062a34e420
cpu_row_key_exact_match=true
cuda_status=ok
cuda_output_records=36
cuda_source_match_records=7747
cuda_source_ext_groups=33
cuda_active_ext_groups=22
cpu_vs_cuda_row_key_diff=match
cpu_vs_cuda_ordered_match=false
cuda_ab_row_key_diff=match
cuda_ab_ordered_match=true
unsupported_exit_status=2
unsupported_json_status=error
unsupported_error="required bytes exceed memory budget"
cpu_replay_wall_seconds=0.11
cuda_replay_wall_seconds=0.48
cuda_kernel_ms=53.170850
```

Allowed M6h claim:

```text
cuFlye can run a bounded CUDA full-query-hit replay consumer that produces the
same canonical raw-overlap row-key set as the M6g CPU replay and fails closed
on unsupported memory budget.
```

Forbidden M6h claim:

```text
M6h does not prove ordered raw row parity, full non-key field reproduction,
Flye graph consumption, default GPU mode, or any speedup.
```

Plain-language benefit:

```text
M6h moves the target boundary onto CUDA for the first time: the GPU path now
generates the same selected raw-overlap coordinates and scores after canonical
row-key comparison. It is still slower than CPU because the kernel is serial per
edge group and pays cold CUDA process overhead. This is a correctness migration
milestone, not a performance milestone.
```

M6i accepted result:

```text
cuFlye now has a `parallel-score` CUDA full-query-hit replay mode that uses
128 threads per active ext group, preserves the M6h canonical row-key output,
and records matched CPU/serial/parallel timing on the selected source pack.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m6i-proof-20260701T072117Z
golden=tests/golden/cuflye-m6i-parallel-full-query-hit-replay-benchmark-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
cpu_replay_status=match
cpu_row_key_exact_match=true
serial_kernel_mode=serial
parallel_kernel_mode=parallel-score
parallel_threads=128
cpu_vs_serial_row_key_diff=match
cpu_vs_parallel_row_key_diff=match
serial_vs_parallel_row_key_diff=match
parallel_ab_row_key_diff=match
unsupported_exit_status=2
unsupported_json_status=error
unsupported_error="required bytes exceed memory budget"
cpu_replay_wall_seconds=0.11
serial_cuda_wall_seconds=0.48
parallel_cuda_wall_seconds=0.43
serial_kernel_ms=53.287348
parallel_kernel_ms=52.542531
parallel_kernel_speedup_vs_serial_kernel=1.0141755066957092
parallel_total_speedup_vs_serial_total=1.148385663790127
```

Allowed M6i claim:

```text
cuFlye can run the selected full-query-hit CUDA replay in a deterministic
parallel-score mode that preserves canonical CPU row-key parity and slightly
improves bounded CUDA timing versus the M6h-style serial CUDA mode.
```

Forbidden M6i claim:

```text
M6i does not prove CPU-beating replay, full non-key field reproduction, Flye
graph consumption, default GPU mode, or whole-Flye speedup.
```

Plain-language benefit:

```text
M6i shows the GPU path can start doing real parallel work without changing the
raw-overlap coordinates and scores we care about. The benefit is real but tiny
on this pack: the kernel gets about 1.014x faster than serial CUDA, while the
whole cold CUDA run is still slower than CPU. The next useful move is to keep
the CUDA process warm instead of paying setup cost on every request.
```

M6j accepted result:

```text
cuFlye now has a warm-session benchmark mode for the selected full-query-hit
CUDA replay path. It keeps one process, CUDA context, and device-buffer set
alive across repeated `parallel-score` requests and records per-request timing.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m6j-proof-20260701T073041Z
golden=tests/golden/cuflye-m6j-persistent-full-query-hit-replay-session-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
cpu_replay_status=match
cpu_row_key_exact_match=true
cpu_replay_wall_ms=90.0
cold_parallel_kernel_mode=parallel-score
cold_parallel_repeat_count=1
cold_parallel_wall_ms=470.0
cold_parallel_total_ms=355.993331
session_parallel_repeat_count=5
session_warm_request_total_best_ms=52.199131
session_warm_request_total_mean_ms=52.200286750000004
session_warm_kernel_best_ms=52.174907
cpu_vs_session_row_key_diff=match
cold_vs_session_row_key_diff=match
session_ab_row_key_diff=match
unsupported_exit_status=2
unsupported_json_status=error
unsupported_repeat_count=5
bounded_hot_request_speedup_vs_cpu_replay_wall=1.7241666341150392
```

Allowed M6j claim:

```text
cuFlye can run a bounded warm full-query-hit CUDA request faster than the
matched CPU replay wall time for the selected source pack while preserving
canonical raw-overlap row-key parity.
```

Forbidden M6j claim:

```text
M6j does not prove cold-process CUDA speedup, full non-key field reproduction,
Flye graph consumption, default GPU mode, Flye-stage speedup, or whole-Flye
speedup.
```

Plain-language benefit:

```text
M6j is the first clean win for this read-to-graph full-query-hit boundary:
when CUDA stays warm, one request takes about 52.199 ms versus about 90 ms for
the matched CPU replay. The important caveat is that the full cold process is
still slower. So the engineering lesson is clear: the GPU work can win, but
only if we expose it through a warm worker/session seam instead of launching a
fresh CUDA process each time.
```

M6k accepted result:

```text
cuFlye now has a file-backed full-query-hit worker protocol. Compatible JSONL
requests reuse one CUDA session, and the second request is a real warm worker
request instead of an in-process repeat-count benchmark.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m6k-proof-20260701T074410Z
golden=tests/golden/cuflye-m6k-full-query-hit-worker-seam-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
cpu_replay_status=match
cpu_row_key_exact_match=true
cpu_replay_wall_ms=110.0
cold_parallel_wall_ms=490.0
cold_parallel_total_ms=356.641602
worker_a_actual_request_ordinal=2
worker_a_actual_cuda_context_warm=true
worker_a_actual_request_ms=52.243993
worker_a_actual_kernel_ms=52.177993
worker_a_actual_parse_ms=0.0
worker_a_actual_device_allocation_ms=0.0
cpu_vs_worker_a_row_key_diff=match
cold_vs_worker_a_row_key_diff=match
worker_ab_row_key_diff=match
unsupported_exit_status=1
unsupported_json_status=error
unsupported_error="required bytes exceed memory budget"
bounded_warm_worker_speedup_vs_cpu_replay_wall=2.105505220475778
```

Allowed M6k claim:

```text
cuFlye can request bounded full-query-hit CUDA replay through a file-backed
worker boundary, keep the second compatible request warm, and beat matched CPU
replay wall time while preserving canonical raw-overlap row-key parity.
```

Forbidden M6k claim:

```text
M6k does not prove Flye graph consumption, default GPU mode, cold-process
speedup, full non-key field reproduction, Flye-stage speedup, or whole-Flye
speedup.
```

Plain-language benefit:

```text
M6k moves the win out of a benchmark loop and behind a worker interface. In
plain terms: a caller can now ask the GPU worker for the same bounded replay,
and the warm request still wins, about 52.244 ms versus 110 ms for CPU replay.
The next risk is integration, not kernel math: Flye still needs to submit this
request, validate it, and refuse to mutate graph state until the gate passes.
```

Next highest-ROI task:

```text
M6l: move the M6k full-query-hit worker boundary into a Flye-side dry-run seam
so a real Flye run can request worker output, validate row-key parity, preserve
canonical artifacts, and still stop before graph mutation.
```

### M6l: Flye full-query-hit worker dry-run seam

Status: complete.

M6l adds `0042-cuflye-read-to-graph-full-query-hit-worker-dry-run-seam.patch`
and ABI documentation in
`docs/abi/flye-full-query-hit-worker-dry-run-seam-v0.md`. The Flye-side seam is
enabled only by:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE=full-query-hit-dry-run-v0
```

It requires the read-to-graph source pack envs, emits an M6k worker request,
validates the worker `raw-overlaps.tsv` by canonical row key, writes
`full-query-hit-worker-dry-run.json`, and throws before graph mutation.

DGX proof:

```text
proof_root=/tmp/cuflye-m6l-proof-20260701T080708Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
expected_output_records=36
positive_status=passed
positive_decision=stopped-before-graph-mutation
worker_response_status=ok
worker_wall_ms=480.644
worker_kernel_ms=52.565552
row_key_diff=match
matched_rows=36
missing_rows=0
extra_rows=0
graph_mutation_consumed_worker_output=false
negative_status=failed-before-graph-mutation
negative_error="required bytes exceed memory budget"
negative_missing_rows=36
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6l claim:

```text
cuFlye can now have a real Flye run generate the selected read-to-graph source
pack, call the CUDA full-query-hit worker through the M6k file protocol,
validate 36/36 raw-overlap row keys against the CPU oracle, and stop before
graph mutation.
```

Forbidden M6l claim:

```text
M6l does not prove whole-Flye speedup, graph consumption, default GPU mode,
warm-worker Flye integration, or full non-key raw-overlap field parity.
```

Plain-language benefit:

```text
M6l turns the previous standalone worker result into a real Flye integration
gate. It does not make Flye faster yet; in this proof the worker wall time is
still cold-process dominated at about 480.644 ms while the kernel itself is
about 52.566 ms. The value is safety and integration: Flye can now ask the GPU
for output and reject it before graph mutation unless the CPU oracle row-key
gate passes.
```

Next highest-ROI task:

```text
M6m: add a warm/persistent Flye-side full-query-hit worker lifecycle so the real
Flye seam can reuse CUDA context and device buffers instead of paying cold
worker startup for each dry-run proof.
```

### M6m: Persistent Flye full-query-hit worker lifecycle

Status: complete.

M6m adds
`0043-cuflye-read-to-graph-full-query-hit-worker-jsonl-lifecycle.patch`. The
Flye dry-run seam now supports:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_LIFECYCLE_MODE=jsonl-persistent-v0
```

In that mode Flye emits a two-line JSONL request file: one warmup request and
one actual request. The CUDA worker keeps its parsed source pack, CUDA context,
and device buffers warm inside the worker process. Flye validates only the
actual request output and still stops before graph mutation.

DGX proof:

```text
proof_root=/tmp/cuflye-m6m-proof-20260701T083036Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
expected_output_records=36
requests_jsonl_line_count=2
request_ids=read-to-graph-full-query-hit-warmup,read-to-graph-full-query-hit-actual
positive_status=passed
actual_worker_cuda_context_warm=true
worker_context_setup_ms=312.078
actual_request_total_ms=52.2432
actual_request_kernel_ms=52.179
actual_request_parse_ms=0
actual_request_device_allocation_ms=0
actual_request_host_to_device_ms=0
row_key_diff=match
matched_rows=36
missing_rows=0
extra_rows=0
graph_mutation_consumed_worker_output=false
negative_status=failed-before-graph-mutation
negative_error="CUDA full-query-hit worker failed with status 256: required bytes exceed memory budget"
negative_missing_rows=36
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6m claim:

```text
cuFlye can now have a real Flye dry-run seam send warmup plus actual
full-query-hit requests to one CUDA worker process, verify that the actual
request is warm, validate 36/36 raw-overlap row keys, and stop before graph
mutation.
```

Forbidden M6m claim:

```text
M6m does not prove whole-Flye speedup, graph consumption, default GPU mode,
cross-process daemon reuse, or full non-key raw-overlap field parity.
```

Plain-language benefit:

```text
M6m proves the warm-worker shape inside the real Flye seam. The actual request
no longer pays source parsing, device allocation, or host-to-device copy inside
the worker; those are all reported as 0 ms for the actual request. Whole-Flye is
not faster yet because this is still a dry-run proof and Flye still launches one
worker process for the proof.
```

Next highest-ROI task:

```text
M6n: replace per-Flye-process JSONL proof invocation with a true file-backed
worker session/daemon lifecycle so separate Flye seam calls can reuse one
already-running CUDA worker process, then measure whether end-to-end worker
wall time improves beyond this intra-process warm request proof.
```

### M6n: File-backed full-query-hit worker session

Status: complete.

M6n adds
`0044-cuflye-read-to-graph-full-query-hit-worker-session-file.patch` and
`docs/abi/full-query-hit-worker-session-v0.md`. The Flye dry-run seam now
supports:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_LIFECYCLE_MODE=session-file-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_DIR=/path/to/session
```

In this mode an external `cuflye-cuda-full-query-hit-replay` process owns the
CUDA context and polls `SESSION_DIR/inbox/*.ready`. Separate Flye seam calls
write normal worker request JSON, submit a ready file, wait for the matching
done file, validate row-key parity, and stop before graph mutation.

DGX proof:

```text
proof_root=/tmp/cuflye-m6n-proof-20260701T085823Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_session_processed_requests=2
first_request_id=read-to-graph-full-query-hit-session-cuflye-m6n-proof-20260701T085823Z_positive-first_worker
second_request_id=read-to-graph-full-query-hit-session-cuflye-m6n-proof-20260701T085823Z_positive-second_worker
first_status=passed
first_worker_cuda_context_warm=false
first_worker_wall_ms=100.728
first_request_total_ms=98.495
second_status=passed
second_worker_cuda_context_warm=true
second_worker_wall_ms=55.4038
second_request_total_ms=52.735775
second_parse_ms=0.0
second_device_allocation_ms=0.0
second_host_to_device_ms=0.0
first_row_key_diff=match
second_row_key_diff=match
negative_status=failed-before-graph-mutation
negative_error="CUDA full-query-hit worker session request failed: required bytes exceed memory budget"
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6n claim:

```text
cuFlye can now have separate Flye dry-run seam submissions attach to one live
file-backed CUDA full-query-hit worker session, validate row-key parity for
each actual request, and keep the second request warm without relaunching the
worker process.
```

Forbidden M6n claim:

```text
M6n does not prove whole-Flye speedup, graph consumption, default GPU mode,
full non-key raw-overlap field parity, or daemon lifecycle management beyond a
bounded worker session.
```

Plain-language benefit:

```text
M6n is the first proof that the advantage survives across separate Flye seam
calls, not only inside one worker invocation. The first session request costs
about 100.728 ms wall / 98.495 ms request time; the second request reuses the
same live CUDA worker and costs about 55.404 ms wall / 52.736 ms request time,
with parse, device allocation, and host-to-device copy all reported as 0 ms.
This is still a dry-run proof, but it is a real integration benefit.
```

Next highest-ROI task:

```text
M6o: add a session-scale/performance gate that submits several selected
full-query-hit windows through one file-backed worker session, records
amortized cold-vs-warm timing, and decides whether the next guarded
graph-consumption step has enough ROI to proceed.
```

### M6o: Session-scale full-query-hit performance gate

Status: complete.

M6o adds `scripts/run_m6o_session_scale_proof.sh` and the DGX manifest
`tests/golden/cuflye-m6o-session-scale-performance-gate-dgx-aarch64.json`.
The proof submits four separate compatible Flye full-query-hit dry-run seam
requests through one file-backed CUDA worker session, validates row-key parity
for every request, then runs a memory-budget negative proof.

DGX proof:

```text
proof_root=/tmp/cuflye-m6o-proof-20260701T090904Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_session_processed_requests=4
request_ordinals=1,2,3,4
cold_worker_wall_ms=60.1647
cold_request_total_ms=57.310081
warm_worker_wall_avg_ms=55.003433333333334
warm_request_total_avg_ms=52.690358
warm_request_total_min_ms=52.619195
warm_request_total_max_ms=52.744364
warm_kernel_avg_ms=52.52250166666667
amortized_worker_wall_including_cold_ms=56.29375
amortized_request_total_including_cold_ms=53.845288749999995
warm_parse_ms=0.0
warm_device_allocation_ms=0.0
warm_host_to_device_ms=0.0
all_row_key_diffs=match
negative_status=failed-before-graph-mutation
negative_error="CUDA full-query-hit worker session request failed: required bytes exceed memory budget"
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6o claim:

```text
cuFlye can process at least four compatible selected full-query-hit Flye
dry-run seam requests through one file-backed CUDA worker session, keep
requests 2-4 warm, preserve row-key parity for every validated request, and
fail closed on a memory-budget negative proof.
```

Forbidden M6o claim:

```text
M6o does not prove whole-Flye speedup, graph consumption, default GPU mode,
full non-key raw-overlap field parity, or production daemon lifecycle.
```

Plain-language benefit:

```text
M6o shows that M6n's file-backed full-query-hit session benefit is stable
across four separate Flye seam submissions. The first request was cold at about
60.165 ms wall / 57.310 ms request time. The next three warm requests averaged
55.003 ms wall / 52.690 ms request time, with parse, device allocation, and
host-to-device copy all at 0 ms. This still does not mutate Flye graph state,
but it proves the session path can amortize worker setup across multiple real
Flye seam calls.
```

Next highest-ROI task:

```text
M6p: design a guarded full-query-hit graph-consumption dry-run that rehydrates
session-validated raw-overlap rows into Flye-side structures without enabling
default GPU mode, then prove mismatch and corruption still fail closed before
graph mutation.
```

### M6p: Full-query-hit guarded consumption dry-run

Status: complete.

M6p adds
`0045-cuflye-read-to-graph-full-query-hit-rehydration-dry-run.patch`,
`docs/abi/read-to-graph-full-query-hit-raw-overlap-rehydration-dry-run-v0.md`,
and the DGX manifest
`tests/golden/cuflye-m6p-full-query-hit-guarded-consumption-dry-run-dgx-aarch64.json`.
The Flye full-query-hit dry-run seam now supports:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_MODE=raw-overlap-vector-dry-run-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_PROOF_FAULT=drop-first-rehydrated-record
```

After the CUDA session worker output passes canonical row-key parity, Flye
parses the worker `raw-overlaps.tsv` into checked `OverlapRange`-shaped records,
canonicalizes those typed records back to row keys, writes
`full-query-hit-worker-raw-overlap-rehydration.json`, and still stops before
graph mutation. `edge_id=0` is treated as an unresolved graph-edge binding at
this M6 boundary rather than a valid `GraphEdge*`.

DGX proof:

```text
proof_root=/tmp/cuflye-m6p-proof-20260701T093152Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_row_key_matched=true
positive_rehydration_status=passed
positive_worker_records=36
positive_parsed_records=36
positive_rehydrated_records=36
positive_typed_row_key_status=match
positive_graph_mutation_consumed_worker_output=false
negative_status=rehydration-failed-before-graph-mutation
negative_row_key_matched=true
negative_rehydration_status=failed
negative_proof_fault=drop-first-rehydrated-record
negative_proof_fault_applied=true
negative_worker_records=36
negative_rehydrated_records=35
negative_typed_row_key_status=mismatch
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6p claim:

```text
cuFlye can rehydrate session-validated CUDA full-query-hit raw-overlap rows
inside Flye into checked OverlapRange-shaped records, prove the typed records
round-trip to the validated worker row keys, and fail closed on a post-row-key
typed mismatch before graph mutation.
```

Forbidden M6p claim:

```text
M6p does not prove whole-Flye speedup, graph mutation from CUDA output, default
GPU mode, GraphEdge object-vector consumption, or full non-key raw-overlap
field parity.
```

Plain-language benefit:

```text
M6p does not make Flye faster yet. It does make the CUDA path more real: worker
rows no longer stop at "TSV text matches"; Flye can parse them back into its own
range/id representation and prove they still match. The negative proof happens
after row-key parity has already passed, so this is a new safety gate rather
than a repeat of M6l/M6n.
```

Next highest-ROI task:

```text
M6q: add a shadow consumption ledger for M6p-rehydrated full-query-hit rows,
including explicit accounting for unresolved edge_id=0 rows, while still
keeping graph mutation disabled. This should determine whether there is a safe
first read-to-graph consumption candidate or whether the next blocker is graph
edge identity.
```

### M6q: Full-query-hit shadow consumption ledger

M6q adds
`0046-cuflye-read-to-graph-full-query-hit-shadow-ledger.patch`,
`docs/abi/read-to-graph-full-query-hit-shadow-consumption-ledger-v0.md`, and
`tests/golden/cuflye-m6q-full-query-hit-shadow-consumption-ledger-dgx-aarch64.json`.
The Flye full-query-hit dry-run seam now supports:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_MODE=raw-overlap-chain-input-shadow-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_PROOF_FAULT=drop-first-ledger-row
```

The ledger only runs after M6p rehydration passes. It reparses the validated
worker raw-overlap TSV through the typed M6p parser, writes
`full-query-hit-worker-shadow-consumption-ledger.json`, records per-query and
total row accounting, and still stops before graph mutation. The proof fault
drops one ledger row after rehydration passes, proving this gate fails closed
independently of row-key parity and typed rehydration.

DGX proof:

```text
proof_root=/tmp/cuflye-m6q-proof-20260701T095436Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_worker_records=36
positive_rehydrated_records=36
positive_shadow_ledger_rows=36
positive_chain_input_filter_rows=0
positive_unresolved_edge_id_zero_rows=36
positive_resolved_edge_id_rows=0
positive_graph_edge_consumption_candidate_rows=0
positive_graph_mutation_consumed_worker_output=false
negative_status=shadow-ledger-failed-before-graph-mutation
negative_rehydration_status=passed
negative_shadow_ledger_status=failed
negative_proof_fault=drop-first-ledger-row
negative_proof_fault_applied=true
negative_rehydrated_records=36
negative_shadow_ledger_rows=35
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6q claim:

```text
cuFlye can write a deterministic no-mutation shadow ledger for M6p-rehydrated
CUDA full-query-hit rows, prove all 36 selected rows are accounted as future
raw-overlap shadow rows, record that all 36 still have unresolved edge_id=0,
and fail closed if the ledger row accounting is corrupted after rehydration
passes.
```

Forbidden M6q claim:

```text
M6q does not prove whole-Flye speedup, chain-input-positive consumption,
graph-edge identity, GraphEdge object-vector consumption, graph mutation, or a
default GPU mode.
```

Plain-language benefit:

```text
M6q still does not make Flye faster. It makes the next decision concrete:
row-key parity and typed parsing are no longer the blocker for this selected
full-query-hit pack, but the pack has zero chain-input-filter rows and zero
graph-edge consumption candidates in the CUDA worker output. A source-pack scan
shows the CPU oracle already has chain-input-positive rows for this selection,
so the next high-ROI step is to propagate those oracle-only non-key fields into
the worker output after row-key replay succeeds.
```

Next highest-ROI task:

```text
M6r: preserve source-pack oracle-only raw-overlap metadata in the CUDA
full-query-hit worker output by row key, then rerun the existing M6p/M6q gates
to prove nonzero chain-input rows and resolved edge ids are visible before graph
mutation remains disabled.
```

## 2026-07-01 Update: M6r Full Query-Hit Non-Key Field Propagation

Status: completed.

Task Card:

- `docs/tasks/2026-07-01-cuflye-m6r-full-query-hit-non-key-field-propagation.md`

Golden proof:

- `tests/golden/cuflye-m6r-full-query-hit-non-key-field-propagation-dgx-aarch64.json`

What changed:

- Added `tools/select_read_to_graph_chain_input_positive.py` to prove whether a
  source pack contains chain-input-positive raw-overlap rows.
- Extended the CUDA full-query-hit replay worker to load source-pack
  raw-overlap oracle metadata and backfill these non-key fields by row key after
  CUDA row-key replay succeeds:
  - `edge_id`;
  - `seq_divergence`;
  - `passes_chain_input_filter`.
- Kept CUDA kernel row-key generation unchanged.
- Kept graph mutation disabled and audited as not consumed.

DGX proof:

```text
proof_root=/tmp/cuflye-m6r-proof-20260701T105200Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
source_selection_chain_input_rows=8
source_selection_raw_rows=36
positive_status=passed
positive_row_key_matched=true
positive_external_row_key_status=match
positive_rehydration_status=passed
positive_worker_records=36
positive_rehydrated_records=36
positive_shadow_ledger_status=passed
positive_shadow_ledger_rows=36
positive_chain_input_filter_rows=8
positive_unresolved_edge_id_zero_rows=0
positive_resolved_edge_id_rows=36
positive_graph_edge_consumption_candidate_rows=0
positive_graph_mutation_consumed_worker_output=false
negative_status=shadow-ledger-failed-before-graph-mutation
negative_rehydration_status=passed
negative_shadow_ledger_status=failed
negative_proof_fault=drop-first-ledger-row
negative_proof_fault_applied=true
negative_rehydrated_records=36
negative_shadow_ledger_rows=35
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6r claim:

```text
cuFlye can preserve source-pack oracle-only raw-overlap metadata in CUDA
full-query-hit worker output after row-key replay succeeds, allowing the M6q
ledger to see 8 chain-input-positive rows and 36 resolved edge-id rows while
still blocking graph mutation.
```

Forbidden M6r claim:

```text
M6r does not prove whole-Flye speedup, GPU-computed chain-input filtering,
GPU-computed graph-edge identity, GraphEdge object-vector consumption, graph
mutation, or a default GPU mode.
```

Plain-language benefit:

```text
M6r still does not make full Flye faster. It removes a real integration blocker:
the CUDA worker no longer loses the CPU oracle's non-key raw-overlap metadata
after row-key replay. The next bottleneck is now sharper: the rows have
chain-input flags and edge ids, but they are still not bound to live Flye graph
edge objects.
```

Next highest-ROI task:

```text
M6s: add an opt-in no-mutation graph-edge binding audit for M6r/M6q rows. It
should prove that chain-input-positive CUDA full-query-hit rows with resolved
edge_id values can bind back to live Flye GraphEdge objects, then fail closed on
a deliberate binding fault before any graph mutation is possible.
```

## 2026-07-01 Update: M6s Full Query-Hit Graph Edge Binding Dry-Run

Status: completed.

Task Card:

- `docs/tasks/2026-07-01-cuflye-m6s-full-query-hit-graph-edge-binding-dry-run.md`

Golden proof:

- `tests/golden/cuflye-m6s-full-query-hit-graph-edge-binding-dry-run-dgx-aarch64.json`

What changed:

- Added Flye patch `0047` with an opt-in no-mutation graph-edge binding audit.
- Added ABI notes for
  `cuflye-read-to-graph-full-query-hit-graph-edge-binding-dry-run-v0`.
- Extended `scripts/run_flye_fixture.sh` so proof runs can enable graph-edge
  binding mode and inject a binding proof fault.
- Kept graph mutation disabled and audited as not consumed.

DGX proof:

```text
proof_root=/tmp/cuflye-m6s-proof-20260701T120300Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_graph_edge_binding_status=passed
positive_chain_input_filter_rows=8
positive_graph_edge_binding_rows=8
positive_graph_edge_binding_resolved_edge_id_rows=8
positive_graph_edge_binding_live_edge_rows=8
positive_graph_edge_binding_missing_edge_rows=0
positive_graph_mutation_consumed_worker_output=false
negative_status=graph-edge-binding-failed-before-graph-mutation
negative_rehydration_status=passed
negative_shadow_ledger_status=passed
negative_graph_edge_binding_status=failed
negative_proof_fault=drop-first-binding-row
negative_proof_fault_applied=true
negative_chain_input_filter_rows=8
negative_graph_edge_binding_rows=7
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6s claim:

```text
cuFlye can take M6r/M6q CUDA full-query-hit rows that pass chain-input filtering
and prove that all 8 selected rows bind back to live Flye GraphEdge objects in a
no-mutation audit.
```

Forbidden M6s claim:

```text
M6s does not prove whole-Flye speedup, object-vector substitution, graph
mutation, default GPU mode, or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6s still does not make full Flye faster. It proves the next safety boundary:
the selected CUDA-derived rows are no longer just TSV records with edge ids;
they can be tied back to actual live Flye graph edge objects. This makes the
next step an object-vector consumption smoke instead of another identity check.
```

Next highest-ROI task:

```text
M6t: construct and account a bounded graph-facing object vector from the M6s
bound rows, keep it behind a no-mutation gate, and fail closed if object
accounting is corrupted before the vector can be returned to Flye's mutating
read-to-graph path.
```

## 2026-07-01 Update: M6t Full Query-Hit Object Vector Consumption Smoke

Status: completed.

Task Card:

- `docs/tasks/2026-07-01-cuflye-m6t-full-query-hit-object-vector-consumption-smoke.md`

Golden proof:

- `tests/golden/cuflye-m6t-full-query-hit-object-vector-smoke-dgx-aarch64.json`

What changed:

- Added Flye patch `0048` with an opt-in no-mutation object-vector smoke audit.
- Added ABI notes for
  `cuflye-read-to-graph-full-query-hit-object-vector-smoke-v0`.
- Extended `scripts/run_flye_fixture.sh` so proof runs can enable object-vector
  smoke mode and inject an object-accounting proof fault.
- Kept graph mutation disabled and audited as not consumed.

DGX proof:

```text
proof_root=/tmp/cuflye-m6t-proof-20260701T105600Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_graph_edge_binding_status=passed
positive_object_vector_smoke_status=passed
positive_object_rows=8
positive_object_accounting_rows=8
positive_query_accounted_rows=8
positive_edge_accounted_rows=8
positive_query_edge_accounted_rows=8
positive_graph_mutation_consumed_worker_output=false
negative_status=object-vector-smoke-failed-before-graph-mutation
negative_rehydration_status=passed
negative_shadow_ledger_status=passed
negative_graph_edge_binding_status=passed
negative_object_vector_smoke_status=failed
negative_proof_fault=drop-first-object-accounting-row
negative_proof_fault_applied=true
negative_object_rows=8
negative_object_accounting_rows=7
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6t claim:

```text
cuFlye can construct 8 graph-facing in-memory objects from selected CUDA
full-query-hit rows, bind each to live Flye graph edges, account every object
by query and edge, and still block graph mutation.
```

Forbidden M6t claim:

```text
M6t does not prove whole-Flye speedup, object-vector substitution, graph
mutation, default GPU mode, or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6t still does not make full Flye faster. It proves the CUDA output can become
Flye-facing objects with complete accounting, instead of remaining an external
TSV audit. The next boundary is a guarded substitution handoff: can Flye see
the vector at the replacement point and still refuse mutation unless all counts
match?
```

Next highest-ROI task:

```text
M6u: add a no-mutation substitution guard after M6t. It should receive the
object vector at the handoff boundary, prove the handoff count matches M6t
accounting, and fail closed on a deliberately corrupted handoff before graph
mutation.
```

## 2026-07-01 Update: M6u Full Query-Hit Object Vector Substitution Guard

Status: completed.

Task Card:

- `docs/tasks/2026-07-01-cuflye-m6u-full-query-hit-object-vector-substitution-guard.md`

Golden proof:

- `tests/golden/cuflye-m6u-full-query-hit-substitution-guard-dgx-aarch64.json`

What changed:

- Added Flye patch `0049` with an opt-in no-mutation substitution guard after
  the M6t object-vector smoke.
- Added ABI notes for
  `cuflye-read-to-graph-full-query-hit-substitution-guard-dry-run-v0`.
- Extended `scripts/run_flye_fixture.sh` so proof runs can enable substitution
  guard mode and inject a handoff-count proof fault.
- Kept graph mutation disabled and audited as not consumed.

DGX proof:

```text
proof_root=/tmp/cuflye-m6u-proof-20260701T111200Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_graph_edge_binding_status=passed
positive_object_vector_smoke_status=passed
positive_substitution_guard_status=passed
positive_object_rows=8
positive_handoff_rows=8
positive_handoff_accounting_rows=8
positive_handoff_query_accounted_rows=8
positive_handoff_edge_accounted_rows=8
positive_handoff_query_edge_accounted_rows=8
positive_handoff_object_summary_rows=8
positive_graph_mutation_consumed_worker_output=false
negative_status=substitution-guard-failed-before-graph-mutation
negative_rehydration_status=passed
negative_shadow_ledger_status=passed
negative_graph_edge_binding_status=passed
negative_object_vector_smoke_status=passed
negative_substitution_guard_status=failed
negative_proof_fault=drop-first-handoff-row
negative_proof_fault_applied=true
negative_object_rows=8
negative_handoff_rows=7
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6u claim:

```text
cuFlye can carry 8 CUDA-derived graph-facing full-query-hit objects to a guarded
substitution handoff, prove the handoff count and accounting match the M6t
object vector, and still block graph mutation.
```

Forbidden M6u claim:

```text
M6u does not prove whole-Flye speedup, real substitution, graph mutation,
default GPU mode, or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6u still does not make full Flye faster. It proves Flye can see the
CUDA-derived object vector at the replacement boundary, and that a bad handoff
is rejected before the graph can be mutated.
```

Next highest-ROI task:

```text
M6v: add a verified-substitution smoke after M6u. It should compare the guarded
CUDA object vector against the selected CPU-derived handoff shape, record a
rollback-safe would-substitute ledger, and still fail closed before graph
mutation on a deliberately corrupted substitution ledger.
```

## 2026-07-01 Update: M6v Full Query-Hit Verified Substitution Smoke

Status: completed.

Task Card:

- `docs/tasks/2026-07-01-cuflye-m6v-full-query-hit-verified-substitution-smoke.md`

Golden proof:

- `tests/golden/cuflye-m6v-full-query-hit-verified-substitution-smoke-dgx-aarch64.json`

What changed:

- Added Flye patch `0050` with an opt-in no-mutation verified-substitution
  smoke after the M6u substitution guard.
- Added ABI notes for
  `cuflye-read-to-graph-full-query-hit-verified-substitution-smoke-v0`.
- Extended `scripts/run_flye_fixture.sh` so proof runs can enable verified
  substitution mode and inject a substitution-ledger proof fault.
- Kept graph mutation disabled and audited as not consumed.

DGX proof:

```text
proof_root=/tmp/cuflye-m6v-proof-20260701T113000Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_graph_edge_binding_status=passed
positive_object_vector_smoke_status=passed
positive_substitution_guard_status=passed
positive_verified_substitution_status=passed
positive_guard_handoff_rows=8
positive_selected_cpu_handoff_rows=8
positive_would_substitute_rows=8
positive_substitution_ledger_rows=8
positive_substitution_row_key_diff_status=match
positive_substitution_ordered_row_key_matched=true
positive_graph_mutation_consumed_worker_output=false
negative_status=verified-substitution-smoke-failed-before-graph-mutation
negative_rehydration_status=passed
negative_shadow_ledger_status=passed
negative_graph_edge_binding_status=passed
negative_object_vector_smoke_status=passed
negative_substitution_guard_status=passed
negative_verified_substitution_status=failed
negative_proof_fault=drop-first-substitution-ledger-row
negative_proof_fault_applied=true
negative_guard_handoff_rows=8
negative_would_substitute_rows=7
negative_substitution_ledger_rows=7
negative_substitution_row_key_diff_status=mismatch
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Allowed M6v claim:

```text
cuFlye can compare the selected CUDA-derived would-substitute ledger against
the selected CPU handoff row keys and order, prove `8/8` rows match, and fail
closed on a corrupted `7/8` substitution ledger before graph mutation.
```

Forbidden M6v claim:

```text
M6v does not prove whole-Flye speedup, real graph mutation, default GPU mode,
or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6v still does not make full Flye faster. It proves the CUDA-derived selected
handoff is not only the right size: it matches the CPU-selected handoff row
keys and order, so the next step can reason about a guarded selected CPU-bypass
plan instead of another object identity check.
```

Next highest-ROI task:

```text
M6w: add a selected substitution bypass-plan audit after M6v. It should record
which selected CPU handoff rows could be bypassed by the verified CUDA ledger,
which rows remain CPU-owned, and fail closed on a corrupted bypass ledger
before graph mutation.
```

## 2026-07-01 Update: M6w Full Query-Hit Selected Substitution Bypass Plan

Status: completed.

Task Card:

- `docs/tasks/2026-07-01-cuflye-m6w-full-query-hit-selected-substitution-bypass-plan.md`

Golden proof:

- `tests/golden/cuflye-m6w-full-query-hit-selected-bypass-plan-dgx-aarch64.json`

What changed:

- Added Flye patch `0051` with an opt-in selected bypass-plan audit after the
  M6v verified-substitution smoke.
- Added ABI notes for
  `cuflye-read-to-graph-full-query-hit-selected-bypass-plan-v0`.
- Extended `scripts/run_flye_fixture.sh` so proof runs can enable selected
  bypass-plan mode and inject a bypass-ledger proof fault.
- Kept graph mutation disabled and audited as not consumed.

DGX proof:

```text
proof_root=/tmp/cuflye-m6w-proof-20260701T114500Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
baseline_artifact_hashes_match_golden=true
positive_status=passed
positive_verified_substitution_status=passed
positive_selected_bypass_plan_status=passed
positive_selected_bypass_eligible_rows=8
positive_selected_bypass_ledger_rows=8
positive_verified_substitution_ledger_rows=8
positive_cpu_owned_residual_rows=28
positive_cpu_owned_non_selected_rows=28
positive_cpu_owned_missing_bypass_rows=0
positive_total_cpu_raw_overlap_rows=36
positive_bypass_row_key_diff_status=match
positive_bypass_ordered_row_key_matched=true
positive_plan_checks=18/18
negative_status=selected-bypass-plan-failed-before-graph-mutation
negative_verified_substitution_status=passed
negative_selected_bypass_plan_status=failed
negative_proof_fault=drop-first-bypass-ledger-row
negative_proof_fault_applied=true
negative_selected_bypass_ledger_rows=7
negative_cpu_owned_residual_rows=29
negative_cpu_owned_missing_bypass_rows=1
negative_bypass_row_key_diff_status=mismatch
negative_graph_mutation_consumed_worker_output=false
summary_checks=24/24
```

Allowed M6w claim:

```text
cuFlye can turn the M6v verified selected substitution ledger into an explicit
selected CPU-bypass plan: 8 selected rows are bypass-eligible, 28 residual rows
remain CPU-owned, all 36 CPU raw-overlap rows are accounted for, and a corrupt
bypass ledger fails closed before graph mutation.
```

Forbidden M6w claim:

```text
M6w does not prove whole-Flye speedup, real graph mutation, default GPU mode,
or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6w still does not make full Flye faster. It tells us exactly which rows are
safe candidates to skip on the CPU side and which rows must stay CPU-owned, so
the next milestone can try a real selected bypass without guessing.
```

Next highest-ROI task:

```text
M6x: add an opt-in selected bypass dry-run after M6w. It should mark selected
rows as actually bypassed in dry-run state, keep residual rows CPU-owned,
account for all CPU raw-overlap rows in a merged ledger, and fail closed before
graph mutation on a corrupted selected bypass payload.
```

## 2026-07-01 Update: M6x Full Query-Hit Selected Bypass Dry-Run

Status: completed.

Task Card:

- `docs/tasks/2026-07-01-cuflye-m6x-full-query-hit-selected-bypass-dry-run.md`

Golden proof:

- `tests/golden/cuflye-m6x-full-query-hit-selected-bypass-dry-run-dgx-aarch64.json`

What changed:

- Added Flye patch `0052` with an opt-in selected bypass dry-run after the M6w
  selected bypass-plan audit.
- Added ABI notes for
  `cuflye-read-to-graph-full-query-hit-selected-bypass-dry-run-v0`.
- Extended `scripts/run_flye_fixture.sh` so proof runs can enable selected
  bypass dry-run mode and inject a selected bypass payload proof fault.
- Kept graph mutation disabled and audited as not consumed.

DGX proof:

```text
proof_root=/tmp/cuflye-m6x-proof-20260701T123000Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
baseline_artifact_hashes_match_golden=true
positive_status=passed
positive_bypass_plan_status=passed
positive_selected_bypass_dry_run_status=passed
positive_selected_bypassed_rows=8
positive_bypass_plan_ledger_rows=8
positive_cpu_owned_residual_rows=28
positive_merged_ledger_rows=36
positive_total_cpu_raw_overlap_rows=36
positive_selected_bypass_missing_rows=0
positive_selected_bypass_unexpected_rows=0
positive_row_key_diff_status=match
positive_ordered_row_key_matched=true
positive_selected_bypass_checks=17/17
negative_status=selected-bypass-dry-run-failed-before-graph-mutation
negative_bypass_plan_status=passed
negative_selected_bypass_dry_run_status=failed
negative_proof_fault=drop-first-selected-bypass-row
negative_proof_fault_applied=true
negative_selected_bypassed_rows=7
negative_bypass_plan_ledger_rows=8
negative_cpu_owned_residual_rows=28
negative_merged_ledger_rows=36
negative_selected_bypass_missing_rows=1
negative_row_key_diff_status=mismatch
summary_checks=28/28
```

Allowed M6x claim:

```text
cuFlye can mark the 8 M6w-selected full-query-hit rows as actually bypassed in
dry-run state, preserve 28 CPU-owned residual rows, account for all 36 CPU
raw-overlap rows in a merged ledger, and fail closed before graph mutation when
the selected bypass payload is corrupted.
```

Forbidden M6x claim:

```text
M6x does not prove whole-Flye speedup, default GPU mode, real graph mutation,
or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6x still does not make full Flye faster. It is the first step where selected
rows are no longer only "eligible" on paper: they are marked as bypassed in a
dry-run execution ledger, while the rest remains CPU-owned and the graph is
still protected.
```

Next highest-ROI task:

```text
M6y: add a selected CPU-bypass smoke after M6x. It should record selected CPU
handoff rows as skipped, supply those rows from the CUDA-derived selected
bypass payload, preserve CPU-owned residual rows, and still fail closed before
graph mutation on a skipped-row leak or missing selected bypass row.
```

## 2026-07-01 Update: M6y Full Query-Hit Selected CPU-Bypass Smoke

Status: completed.

Task Card:

- `docs/tasks/2026-07-01-cuflye-m6y-full-query-hit-selected-cpu-bypass-smoke.md`

Golden proof:

- `tests/golden/cuflye-m6y-full-query-hit-selected-cpu-bypass-smoke-dgx-aarch64.json`

What changed:

- Added Flye patch `0053` with an opt-in selected CPU-bypass smoke after the
  M6x selected bypass dry-run.
- Added ABI notes for
  `cuflye-read-to-graph-full-query-hit-selected-cpu-bypass-smoke-v0`.
- Extended `scripts/run_flye_fixture.sh` so proof runs can enable selected
  CPU-bypass smoke mode and inject a skipped-row leak proof fault.
- Kept graph mutation disabled and audited as not consumed.

DGX proof:

```text
proof_root=/tmp/cuflye-m6y-proof-20260701T130000Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
baseline_artifact_hashes_match_golden=true
positive_status=passed
positive_m6x_selected_bypass_status=passed
positive_m6y_selected_cpu_bypass_smoke_status=passed
positive_skipped_cpu_selected_rows=8
positive_cuda_supplied_selected_rows=8
positive_cpu_owned_residual_rows=28
positive_final_merged_ledger_rows=36
positive_final_cuda_supplied_rows=8
positive_leaked_selected_cpu_rows=0
positive_row_key_diff_status=match
positive_consumed=false
positive_not_consumed=true
positive_selected_cpu_bypass_smoke_checks=22/22
negative_status=selected-cpu-bypass-smoke-failed-before-graph-mutation
negative_m6x_selected_bypass_status=passed
negative_m6y_selected_cpu_bypass_smoke_status=failed
negative_proof_fault=leak-first-skipped-cpu-row
negative_proof_fault_applied=true
negative_final_cuda_supplied_rows=7
negative_leaked_selected_cpu_rows=1
negative_failed_checks=final_cuda_supplied_rows_match_supplier,leaked_selected_cpu_rows_zero
summary_checks=27/27
```

Allowed M6y claim:

```text
cuFlye can skip the 8 M6x-selected CPU handoff rows in a guarded smoke ledger,
supply the same 8 rows from CUDA-derived selected bypass output, preserve 28
CPU-owned residual rows, account for all 36 CPU raw-overlap rows in the final
merged handoff, and fail closed before graph mutation if a skipped selected CPU
row leaks back into CPU-owned handling.
```

Forbidden M6y claim:

```text
M6y does not prove whole-Flye speedup, default GPU mode, real graph mutation,
or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6y still does not make full Flye faster. It proves the selected rows can now
be treated as "CPU handoff skipped and CUDA supplied" under audit, while all
other rows stay CPU-owned and a bad handoff stops before graph mutation.
```

Next highest-ROI task:

```text
M6z: add selected CPU-bypass timing attribution. Now that M6y proves the
semantic skip boundary, measure the skipped CPU handoff work, CUDA supplier
handoff cost, seam overhead, and residual CPU work so the next integrated gate
can make or reject a real performance claim with numbers.
```
