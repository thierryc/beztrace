#!/usr/bin/env python3
"""Generate the deterministic 256-input malformed-image smoke corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / "Tests" / "Fixtures" / "corpus" / "deterministic" / "glyphs" / "glyph-upper-a.png"
OUTPUT = ROOT / "Tests" / "Fixtures" / "malformed" / "v1"
RANDOM_SEED = 0xB37ACE502026


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def payloads(seed: bytes) -> list[tuple[str, str, bytes]]:
    values: list[tuple[str, str, bytes]] = []
    for index in range(64):
        length = (len(seed) * index) // 64
        values.append((f"truncate-{index:03d}.bin", "truncated-png", seed[:length]))

    for index in range(64):
        data = bytearray(seed)
        position = 24 + ((index * 104_729) % max(len(data) - 24, 1))
        data[position] ^= 1 << (index % 8)
        values.append((f"bitflip-{index:03d}.bin", "single-bit-png-mutation", bytes(data)))

    randomizer = random.Random(RANDOM_SEED)
    for index in range(64):
        length = 1 + ((index * 97) % 2048)
        data = bytes(randomizer.randrange(256) for _ in range(length))
        if index % 2 == 0 and length >= 8:
            data = b"\x89PNG\r\n\x1a\n" + data[8:]
        values.append((f"random-{index:03d}.bin", "seeded-random-bytes", data))

    for index in range(64):
        data = bytearray(seed[: min(len(seed), 4096 + index * 64)])
        if len(data) >= 24:
            selector = index % 4
            if selector == 0:
                data[16:20] = (0xFFFF_FFFF).to_bytes(4, "big")
            elif selector == 1:
                data[20:24] = (0).to_bytes(4, "big")
            elif selector == 2:
                data[12:16] = b"NOPE"
            else:
                data[8:12] = (0x7FFF_FFFF).to_bytes(4, "big")
        values.append((f"header-{index:03d}.bin", "png-header-mutation", bytes(data)))
    return values


def generate(destination: Path) -> dict:
    seed = SEED.read_bytes()
    records = []
    destination.mkdir(parents=True, exist_ok=True)
    for name, mutation, data in payloads(seed):
        (destination / name).write_bytes(data)
        records.append({"path": name, "mutation": mutation, "size": len(data), "sha256": sha256(data)})
    manifest = {
        "schemaVersion": 1,
        "seed": str(SEED.relative_to(ROOT)),
        "seedSHA256": sha256(seed),
        "randomSeed": RANDOM_SEED,
        "count": len(records),
        "files": records,
    }
    (destination / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="beztrace-malformed-") as temporary:
            candidate = Path(temporary) / "v1"
            generate(candidate)
            expected = sorted(path.relative_to(candidate) for path in candidate.rglob("*") if path.is_file())
            actual = sorted(path.relative_to(OUTPUT) for path in OUTPUT.rglob("*") if path.is_file()) if OUTPUT.exists() else []
            changed = expected != actual or any(
                (candidate / path).read_bytes() != (OUTPUT / path).read_bytes() for path in expected if (OUTPUT / path).is_file()
            )
            if changed:
                print("malformed corpus differs; run scripts/generate_malformed_corpus.py")
                return 1
    else:
        manifest = generate(OUTPUT)
        print(f"generated {manifest['count']} malformed inputs at {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
