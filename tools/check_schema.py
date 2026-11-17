#!/usr/bin/env python3
"""Validates .chipsong, .chipsfx and .chipkit files against the published
JSON Schemas in docs/schema/.

    python3 tools/check_schema.py file.chipsong [more files...]

Needs the jsonschema package (pip install jsonschema). Exits 1 if any file
does not match its schema.
"""
import json
import pathlib
import sys

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

SCHEMAS = pathlib.Path(__file__).resolve().parent.parent / "docs" / "schema"
KINDS = {".chipsong": "chipsong", ".chipsfx": "chipsfx", ".chipkit": "chipkit"}


def main(paths):
    loaded = {}
    registry = Registry()
    for path in SCHEMAS.glob("*.schema.json"):
        schema = json.loads(path.read_text())
        loaded[path.name.split(".")[0]] = schema
        resource = Resource.from_contents(schema)
        registry = registry.with_resources([(schema["$id"], resource), (path.name, resource)])
    failed = 0
    for name in paths:
        kind = KINDS.get(pathlib.Path(name).suffix)
        if kind is None:
            print(f"skip {name}: not a song, sound or kit")
            continue
        validator = Draft202012Validator(loaded[kind], registry=registry)
        errors = sorted(validator.iter_errors(json.loads(pathlib.Path(name).read_text())), key=lambda e: list(e.path))
        for error in errors[:10]:
            print(f"{name}: {'/'.join(map(str, error.path)) or '(top)'}: {error.message}")
        if errors:
            failed += 1
        else:
            print(f"ok {name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
