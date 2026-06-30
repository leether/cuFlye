# cuFlye Real Data Pack Dump v0

Status: active

Introduced: M2b

Scope: deterministic extraction of real Flye query read windows and relevant
`VertexIndex` buckets into the packed candidate-backend input format.

## Purpose

M2b bridges the gap between hand-written M1i fixtures and real Flye data
structures. It does not run the CUDA candidate backend for real reads yet.
Instead, it proves Flye can pack a real `FastaRecord` query and the matching
`VertexIndex` buckets into a bounded, replayable input bundle.

## Adapter Mode

The mode is selected through the existing CUDA backend selector:

```text
CUFLYE_CANDIDATE_BACKEND=cuda
CUFLYE_CUDA_ADAPTER_MODE=pack-dump-v0
CUFLYE_CUDA_PACK_DUMP_DIR=/path/to/output
```

The pack-dump adapter requires `--threads 1` for deterministic proof capture.
It captures one query and then fails closed before downstream graph logic.

## Output Layout

For a captured query with signed id `N`, files are written under:

```text
${CUFLYE_CUDA_PACK_DUMP_DIR}/query_<N>/
```

Negative ids use `query_neg<N>`.

Files:

| File | Meaning |
| --- | --- |
| `reads.tsv` | Current Flye query id and full query sequence. |
| `index.tsv` | Deduplicated flattened target bucket entries relevant to query k-mers. |
| `repetitive-kmers.tsv` | Deduplicated repetitive lookup k-mers observed in the query. |
| `cpu-candidates.tsv` | Candidate-record-v1 rows produced by Flye CPU semantics for this query. |
| `pack-manifest.json` | Counts and parameters for the captured pack. |

`reads.tsv`:

```text
query_id<TAB>sequence
```

`index.tsv`:

```text
target_id<TAB>target_pos<TAB>target_strand<TAB>lookup_kmer_sequence
```

`repetitive-kmers.tsv`:

```text
lookup_kmer_sequence
```

`cpu-candidates.tsv` uses `candidate-record-v1`.

## Semantics

The packer walks the same `IterKmers(fastaRec.sequence)` stream as Flye's CPU
candidate collector:

- repetitive k-mers are added to `repetitive-kmers.tsv` and excluded from
  candidates;
- absent k-mers are skipped;
- non-repetitive present k-mers flatten `vertexIndex.iterKmerPos(kmer)` into
  `index.tsv`;
- exact self hits with identical read id and position are skipped;
- emitted CPU candidate records preserve `Kmer::numRepr()` for the query k-mer.

`index.tsv` is deduplicated by target id, target position, target strand, and
lookup k-mer sequence. `cpu-candidates.tsv` preserves candidate multiplicity.

## Failure Semantics

The adapter must fail non-zero after writing the first pack:

```text
adapter=pack-dump-v0 ... failing closed before downstream graph logic
```

This is deliberate. M2b is a data extraction proof, not a replacement candidate
backend. It must not silently continue through Flye using CPU-generated
candidate records while reporting the backend as CUDA.

The adapter also fails when:

- `CUFLYE_CUDA_PACK_DUMP_DIR` is unset;
- `--threads` is not `1`;
- a second query would be processed in the same run;
- `CUFLYE_CUDA_PACK_QUERY_ID` is set and the first processed query differs.

## Non-Goals

M2b does not:

- call a CUDA kernel on real Flye reads;
- overcome the M1i `MAX_READ_SIZE=256` smoke backend limit;
- prove candidate parity for the CUDA backend on real Flye data;
- prove speedup for an integrated Flye stage.

## Next Contract

M2c should consume a `pack-dump-v0` bundle with a CUDA backend that supports
real query lengths or chunked read windows, then compare its output to
`cpu-candidates.tsv`.
