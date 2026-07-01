#!/usr/bin/env python3
"""Validate cuFlye compact read-alignment binary payloads."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


MAGIC = b"CUFRALB0"
HEADER_BYTES = 64
RECORD_BYTES = 92


class BinaryPayloadValidationError(ValueError):
    pass


def read_u32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset:offset + 4], "little", signed=False)


def read_u64(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset:offset + 8], "little", signed=False)


def validate_payload(args: argparse.Namespace) -> dict[str, object]:
    path = Path(args.payload)
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if len(data) < HEADER_BYTES:
        raise BinaryPayloadValidationError(
            f"{path}: payload is shorter than {HEADER_BYTES}-byte header"
        )
    if data[:8] != MAGIC:
        raise BinaryPayloadValidationError(f"{path}: invalid compact binary magic")

    header_bytes = read_u32(data, 8)
    record_bytes = read_u32(data, 12)
    version_major = read_u32(data, 16)
    version_minor = read_u32(data, 20)
    fixture_count = read_u64(data, 24)
    output_records = read_u64(data, 32)
    total_input_records = read_u64(data, 40)
    min_input_records = read_u32(data, 48)
    max_input_records = read_u32(data, 52)
    output_mode = read_u32(data, 56)
    reserved0 = read_u32(data, 60)

    if header_bytes != HEADER_BYTES:
        raise BinaryPayloadValidationError(
            f"{path}: unsupported header size {header_bytes}"
        )
    if record_bytes != RECORD_BYTES:
        raise BinaryPayloadValidationError(
            f"{path}: unsupported record size {record_bytes}"
        )
    if (version_major, version_minor) != (0, 0):
        raise BinaryPayloadValidationError(
            f"{path}: unsupported compact binary version "
            f"{version_major}.{version_minor}"
        )
    if output_mode != 1:
        raise BinaryPayloadValidationError(f"{path}: unsupported output mode {output_mode}")
    if reserved0 != 0:
        raise BinaryPayloadValidationError(f"{path}: reserved header field is nonzero")
    if min_input_records > max_input_records:
        raise BinaryPayloadValidationError(
            f"{path}: min_input_records exceeds max_input_records"
        )

    expected_size = header_bytes + output_records * record_bytes
    if len(data) != expected_size:
        raise BinaryPayloadValidationError(
            f"{path}: payload size {len(data)} does not match expected {expected_size}"
        )
    if args.expected_sha256 and digest != args.expected_sha256:
        raise BinaryPayloadValidationError(
            f"{path}: sha256 {digest} does not match expected {args.expected_sha256}"
        )
    if args.expected_fixture_count is not None and fixture_count != args.expected_fixture_count:
        raise BinaryPayloadValidationError(
            f"{path}: fixture_count {fixture_count} does not match expected "
            f"{args.expected_fixture_count}"
        )
    if args.expected_output_records is not None and output_records != args.expected_output_records:
        raise BinaryPayloadValidationError(
            f"{path}: output_records {output_records} does not match expected "
            f"{args.expected_output_records}"
        )
    if (args.expected_total_input_records is not None and
            total_input_records != args.expected_total_input_records):
        raise BinaryPayloadValidationError(
            f"{path}: total_input_records {total_input_records} does not match expected "
            f"{args.expected_total_input_records}"
        )

    return {
        "schema": "cuflye-read-alignment-compact-binary-validation-v0",
        "status": "ok",
        "payload": str(path),
        "sha256": digest,
        "bytes": len(data),
        "header": {
            "magic": MAGIC.decode("ascii"),
            "header_bytes": header_bytes,
            "record_bytes": record_bytes,
            "version_major": version_major,
            "version_minor": version_minor,
            "fixture_count": fixture_count,
            "output_records": output_records,
            "total_input_records": total_input_records,
            "min_input_records": min_input_records,
            "max_input_records": max_input_records,
            "output_mode": "pre-divergence-chains",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate cuFlye compact read-alignment binary payloads."
    )
    parser.add_argument("payload")
    parser.add_argument("--expected-fixture-count", type=int)
    parser.add_argument("--expected-output-records", type=int)
    parser.add_argument("--expected-total-input-records", type=int)
    parser.add_argument("--expected-sha256")
    parser.add_argument("--json-output")
    args = parser.parse_args()

    try:
        result = validate_payload(args)
    except BinaryPayloadValidationError as exc:
        if args.json_output:
            Path(args.json_output).write_text(
                json.dumps({
                    "schema": "cuflye-read-alignment-compact-binary-validation-v0",
                    "status": "error",
                    "error_message": str(exc),
                }, indent=2, sort_keys=True) + "\n"
            )
        raise SystemExit(str(exc))

    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        Path(args.json_output).write_text(text)
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
