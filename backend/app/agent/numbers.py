"""'The AI never writes a number': check the one free-text summary against the tool results.

A number in the text is accepted when it appears in this request's tool results, in the user's own
message or context, or is a percentage of a fraction in a result (0.376 may be written 38 %, 37.6
or 37,6). Anything else is a number the model made up. Dates are checked by their parts.
"""

import json
import re
from typing import Any

_NUMBER = re.compile(r"\d+(?:[.,]\d+)?")
# Structural numbers that carry no data: the two windows, the 30-isolate rule and the 90 % line.
ALWAYS_OK = {4.0, 12.0, 28.0, 30.0, 90.0, 365.0}


def tokens(text: str) -> list[tuple[float, int]]:
    """(value, decimals) for every number written in the text."""
    out = []
    for m in _NUMBER.findall(text):
        m = m.replace(",", ".")
        out.append((float(m), len(m.split(".")[1]) if "." in m else 0))
    return out


def allowed_values(sources: list[Any]) -> set[float]:
    """Every number the model may repeat, from tool results and context (any JSON-able value)."""
    allowed = set(ALWAYS_OK)
    for src in sources:
        text = src if isinstance(src, str) else json.dumps(src, ensure_ascii=False)
        for value, _ in tokens(text):
            allowed.add(value)
            if 0 < value <= 1:  # a fraction: its percentage may be written
                allowed.add(value * 100)
    return allowed


def unsupported(text: str, allowed: set[float]) -> list[str]:
    """Numbers in `text` that no source supports, as written."""
    bad = []
    for value, decimals in tokens(text):
        if not any(round(a, decimals) == round(value, decimals) for a in allowed):
            bad.append(f"{value:g}")
    return bad
