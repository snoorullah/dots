"""A small JSON Schema checker: the subset docs/contracts/*.schema.json uses.

Stdlib only, so the tests run in the bare nix environment with no jsonschema package.
Supported: type (string or list), enum, const, required, properties, additionalProperties
(bool or schema), items, oneOf, pattern, minimum, maximum.
"""
import json
import re
from pathlib import Path

CONTRACTS = Path(__file__).resolve().parents[4] / "docs" / "contracts"

_TYPES = {"string": str, "integer": int, "number": (int, float), "boolean": bool,
          "array": list, "object": dict, "null": type(None)}


def load(name):
    return json.loads((CONTRACTS / f"{name}.schema.json").read_text())


def _is(v, t):
    if t == "integer" and isinstance(v, bool):
        return False
    if t == "number" and isinstance(v, bool):
        return False
    return isinstance(v, _TYPES[t])


def errors(inst, schema, path="$"):
    out = []
    t = schema.get("type")
    if t is not None:
        ts = t if isinstance(t, list) else [t]
        if not any(_is(inst, x) for x in ts):
            return [f"{path}: expected {ts}, got {type(inst).__name__}"]
    if "const" in schema and inst != schema["const"]:
        out.append(f"{path}: expected const {schema['const']!r}, got {inst!r}")
    if "enum" in schema and inst not in schema["enum"]:
        out.append(f"{path}: {inst!r} not in {schema['enum']}")
    if "oneOf" in schema:
        if sum(1 for s in schema["oneOf"] if not errors(inst, s, path)) != 1:
            out.append(f"{path}: does not match exactly one of oneOf")
    if isinstance(inst, str) and "pattern" in schema and not re.search(schema["pattern"], inst):
        out.append(f"{path}: {inst!r} does not match {schema['pattern']}")
    if isinstance(inst, (int, float)) and not isinstance(inst, bool):
        if "minimum" in schema and inst < schema["minimum"]:
            out.append(f"{path}: {inst} < minimum")
        if "maximum" in schema and inst > schema["maximum"]:
            out.append(f"{path}: {inst} > maximum")
    if isinstance(inst, dict):
        for k in schema.get("required", []):
            if k not in inst:
                out.append(f"{path}: missing required {k!r}")
        props = schema.get("properties", {})
        for k, v in inst.items():
            if k in props:
                out += errors(v, props[k], f"{path}.{k}")
            elif schema.get("additionalProperties") is False:
                out.append(f"{path}: unexpected {k!r}")
            elif isinstance(schema.get("additionalProperties"), dict):
                out += errors(v, schema["additionalProperties"], f"{path}.{k}")
    if isinstance(inst, list) and "items" in schema:
        for i, v in enumerate(inst):
            out += errors(v, schema["items"], f"{path}[{i}]")
    return out
