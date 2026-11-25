#!/usr/bin/env python3
"""Compare two private meal snapshots offline. Never connect to a feeder."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

ORDERS = {"sunday_bit_0", "saturday_bit_0"}
FIELDS = {"weekdays", "hour", "minute", "portions", "enabled"}


def normalize(snapshot: Any) -> tuple[str, list[dict[str, Any]]]:
    """Validate and normalize an explicitly identified snapshot to HA day order."""
    if not isinstance(snapshot, dict) or type(snapshot.get("format")) is not int or snapshot["format"] != 1:
        raise ValueError("Unsupported snapshot format")
    identity = snapshot.get("device_id")
    if not isinstance(identity, str) or not 1 <= len(identity) <= 128 or any(ord(c) < 32 for c in identity):
        raise ValueError("A device identity is required in both snapshots")
    order = snapshot.get("weekday_order")
    if not isinstance(order, str) or order not in ORDERS:
        raise ValueError("Declare sunday_bit_0 (HA) or saturday_bit_0 (raw API v1)")
    rows = snapshot.get("meals")
    if not isinstance(rows, list) or len(rows) > 8:
        raise ValueError("A snapshot must contain at most eight meal rows")
    meals = []
    for row in rows:
        if not isinstance(row, dict) or set(row) != FIELDS:
            raise ValueError("A meal must contain exactly the five supported fields")
        for name, low, high in (("weekdays", 0, 127), ("hour", 0, 23), ("minute", 0, 59), ("portions", 1, 10)):
            if type(row[name]) is not int or not low <= row[name] <= high:
                raise ValueError("A meal field is outside the supported range")
        if type(row["enabled"]) is not bool:
            raise ValueError("Meal enabled must be a boolean")
        meal = row.copy()
        if order == "saturday_bit_0":
            mask = meal["weekdays"]
            meal["weekdays"] = sum(((mask >> bit) & 1) << (6 - bit) for bit in range(7))
        meals.append(meal)
    return identity, meals


def compare(before: Any, after: Any) -> dict[str, Any]:
    """Report mismatching row numbers without exposing meal times or device IDs."""
    before_id, old = normalize(before)
    after_id, new = normalize(after)
    if before_id != after_id:
        raise ValueError("Snapshots belong to different devices; comparison refused")
    changed = [index + 1 for index in range(max(len(old), len(new)))
               if index >= len(old) or index >= len(new) or old[index] != new[index]]
    return {"match": not changed, "same_device": True, "rows_before": len(old), "rows_after": len(new),
            "enabled_before": sum(row["enabled"] for row in old), "enabled_after": sum(row["enabled"] for row in new),
            "changed_row_numbers": changed, "network_requests": 0, "device_commands": 0}


def read_snapshot(path: Path) -> Any:
    with path.open("rb") as source:
        data = source.read(65537)
    if len(data) > 65536:
        raise ValueError("Snapshot exceeds the 64 KiB limit")
    try:
        return json.loads(data)
    except (ValueError, UnicodeError):
        raise ValueError("Snapshot is not valid UTF-8 JSON") from None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = compare(read_snapshot(args.before), read_snapshot(args.after))
    except OSError:
        print("Cannot read a snapshot file", file=sys.stderr)
        return 2
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2))
    return 0 if result["match"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
