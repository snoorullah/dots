"""Rule-based categorization of activity into the fixed taxonomy."""
import re, tomllib
from . import config

UNCATEGORIZED = "Uncategorized"

def load_rules(path=None) -> list[dict]:
    path = path or config.CATEGORIES_TOML
    with open(path, "rb") as f:
        return tomllib.load(f).get("rule", [])

def _hit(pattern, value) -> bool:
    return bool(value) and re.search(pattern, value, re.IGNORECASE) is not None

def categorize(app: str, title: str, domain: str | None = None, rules: list[dict] | None = None) -> str:
    if rules is None:
        rules = load_rules()
    for r in rules:
        if (("match_app" in r and _hit(r["match_app"], app)) or
            ("match_title" in r and _hit(r["match_title"], title)) or
            ("match_domain" in r and _hit(r["match_domain"], domain))):
            return r["category"]
    return UNCATEGORIZED
