# cuFlye Coding Style

Status: active

Last updated: 2026-06-30

## Purpose

cuFlye is a Flye-compatible CUDA acceleration project. Coding style must protect
that compatibility goal before it optimizes for cosmetic uniformity.

The project does not wholesale adopt Google C++ Style, LLVM Style, or any other
large external style guide. The highest-value rule is local compatibility:

```text
Keep Flye patches minimal, keep CUDA boundaries explicit, and keep all GPU
outputs deterministic and machine-checkable against the CPU oracle.
```

## Style Layers

| Area | Language level | Style source | Formatter policy |
| --- | --- | --- | --- |
| `upstream-flye/` | Upstream Flye default, currently C++11 | Upstream Flye | Do not reformat. |
| `patches/flye/` | C++11-compatible Flye diffs | Upstream Flye surrounding code | Do not bulk-format patch files. |
| `cuda/` | CUDA C++14 for standalone prototypes | cuFlye CUDA style | May use root `.clang-format`. |
| host-only probes | C++11 unless there is a clear CUDA toolchain reason | cuFlye C++ style | May use root `.clang-format`. |
| `tools/`, `scripts/`, `bench/` | Existing interpreter/tool style | Local script style | Keep focused and shell-checkable. |

The root `.clang-format` is a lightweight formatting tool for original cuFlye
C++/CUDA source. It is intentionally based on LLVM formatting mechanics, but
this repository does not adopt LLVM design rules as project policy.

## Compatibility Rules

- Flye integration patches must remain C++11-compatible unless the upstream
  Flye baseline changes.
- Standalone CUDA prototypes may use CUDA C++14.
- Do not raise a language standard as a drive-by change.
- Do not reformat `upstream-flye/`, `GenomeWorks/`, or patch queues.
- Keep Flye patches small enough that an upstream reviewer can separate the
  semantic change from the CUDA experiment.
- Do not introduce a new dependency in Flye integration code without a Task Card
  that explains build, license, deployment, and fallback impact.

## C++ and CUDA Rules

- Use explicit-width integer types at ABI, file-format, CUDA kernel, and device
  memory boundaries.
- Use `size_t` for host container sizes, then check conversions before passing
  values to narrower ABI fields.
- Check multiplication and allocation sizes before allocating host or device
  buffers.
- Keep host-device record structs plain, trivially copyable, and documented by
  an ABI file under `docs/abi/`.
- Initialize padding and reserved fields before writing binary or textual proof
  artifacts.
- Wrap CUDA Runtime API calls with diagnostics that include numeric code, CUDA
  error name, and CUDA error text.
- Include adapter name, device id, memory budget, input shape, and output path
  in failure metadata when possible.
- CUDA paths must fail closed on unsupported shapes. Silent CPU fallback is not
  allowed.
- GPU output ordering must be deterministic, or a canonical sort/diff gate must
  be part of the acceptance proof.
- Do not feed GPU output into downstream Flye graph logic until the relevant
  CPU oracle diff gate passes.

## Memory and Resource Ownership

Raw resource management is the highest-risk C++ failure mode for cuFlye because
the project crosses CPU containers, Flye adapter boundaries, CUDA device memory,
CUDA events, CUDA streams, and error paths.

The default rule is:

```text
Ownership must be visible in the type system, and reusable backend code must use
RAII for every CPU, CUDA, file, stream, and event resource.
```

- Do not use direct `new`, `delete`, `malloc`, `calloc`, `realloc`, or `free` in
  original cuFlye business logic.
- Prefer `std::vector`, `std::string`, `std::array`, and stack objects for
  ordinary CPU memory.
- Use `std::unique_ptr` only when object lifetime cannot be represented by a
  standard container or stack object.
- Treat raw pointers as non-owning by default. If a raw pointer crosses a
  boundary, the owner and lifetime must be obvious from the function contract.
- Avoid `std::shared_ptr` in hot paths and adapter boundaries. If shared
  ownership is unavoidable, document why unique ownership does not work.
- Avoid `std::weak_ptr` unless it is breaking an explicit shared ownership
  cycle.
- Resource-owning classes should follow Rule of Zero. If they must own a
  non-standard resource, they must be move-only and explicitly delete copy
  construction and copy assignment.
- Destructors and RAII cleanup paths must not throw. If checked teardown matters,
  expose an explicit checked `reset` or `close` operation before destruction.
- Reusable CUDA backend code must not call `cudaMalloc`, `cudaFree`,
  `cudaHostAlloc`, `cudaFreeHost`, `cudaStreamCreate`, `cudaStreamDestroy`,
  `cudaEventCreate`, or `cudaEventDestroy` directly. Wrap these resources in
  move-only RAII types.
- Standalone M1 smoke prototypes may contain direct CUDA resource calls only as
  temporary proof code. Do not copy that pattern into M2+ backend integration
  code.
- CUDA allocation wrappers must check memory budgets before allocation and
  report device id, requested bytes, CUDA error code, CUDA error name, and CUDA
  error text on failure.
- Flye integration patches should adapt to upstream ownership conventions at the
  narrowest possible boundary instead of rewriting large upstream ownership
  surfaces.

## Naming and Layout

- Match upstream Flye naming inside Flye patches.
- In original cuFlye C++/CUDA files, use `UpperCamelCase` for structs/classes,
  `lowerCamelCase` for functions and variables, and `UPPER_SNAKE_CASE` for
  compile-time constants.
- Keep file-level SPDX license identifiers in original source files.
- Put CUDA runtime includes before standard library includes when a file directly
  calls CUDA Runtime APIs.
- Prefer small anonymous-namespace helpers for standalone tools.
- Add comments only where they clarify non-obvious ABI, determinism, memory, or
  CUDA synchronization constraints.

## Verification Rules

Formatting is never the main acceptance gate for cuFlye. A change is ready only
when its relevant proof gates pass:

- candidate-record outputs validate with `tools/validate_candidate_dump.py`;
- CPU and CUDA candidate outputs diff cleanly with `tools/diff_candidate_dumps.py`;
- runtime probes report CUDA device and memory facts when CUDA is required;
- benchmark claims include matched counts and bounded input shape;
- ownership scans show no new direct CPU allocation APIs and no direct CUDA
  resource APIs outside approved low-level RAII wrappers or grandfathered smoke
  prototypes;
- generated large artifacts stay under `out/` and are not committed;
- compact manifests, hashes, and proof summaries are committed under `tests/`
  or `docs/` when they support a milestone claim.

## When External Style Guides Help

Google and LLVM style guides are useful references for general C++ hygiene, but
they are not the cuFlye source of truth. If an external rule conflicts with
Flye compatibility, ABI determinism, or minimal patch reviewability, cuFlye's
local rule wins.
