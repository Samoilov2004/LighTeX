#!/usr/bin/env python3
"""Regenerate the deterministic convergence table used by the demo article."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def rows() -> list[dict[str, str | int]]:
    energy_errors = [0.211, 0.104, 0.0517, 0.0258, 0.0129]
    l2_errors = [0.0381, 0.00942, 0.00234, 0.000584, 0.000146]
    output: list[dict[str, str | int]] = []
    for index, level in enumerate(range(2, 7)):
        subdivisions = 2**level
        output.append(
            {
                "level": level,
                "dofs": (subdivisions - 1) ** 2,
                "h": f"{1 / subdivisions:.6f}",
                "energy_error": f"{energy_errors[index]:.6f}",
                "l2_error": f"{l2_errors[index]:.6f}",
            }
        )
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "data" / "convergence.csv",
    )
    arguments = parser.parse_args()
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    with arguments.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["level", "dofs", "h", "energy_error", "l2_error"],
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows())
    print(f"Wrote {arguments.output}")


if __name__ == "__main__":
    main()
