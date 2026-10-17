from datetime import date

from app import warmup
from app.main import REGISTRY
from app.registry import clear_results


def test_every_warm_up_query_is_valid():
    """The list names real functions with parameters their inputs accept; a renamed field fails here."""
    plan = warmup.queries(date(2026, 9, 27))
    assert plan
    for name, params in plan:
        assert name in REGISTRY, name
        REGISTRY[name].input_model(**{"as_of": "2026-09-27", **params})


def test_research_periods_match_the_research_page():
    """The three periods seen in the browser trace of the Research page."""
    assert warmup._research_periods(date(2026, 9, 27)) == [
        (date(2023, 10, 2), date(2024, 9, 27)),
        (date(2024, 9, 28), date(2025, 9, 27)),
        (date(2025, 9, 28), date(2026, 9, 27)),
    ]


def test_warm_up_fills_the_result_cache():
    clear_results()
    result = warmup.run(budget_seconds=600)
    assert result["failed"] == 0 and result["queries"] > 100
    q = REGISTRY["get_organisms"].input_model(ward="URO", infection_type="uti", window="365d")
    assert REGISTRY["get_organisms"].handler(q) is REGISTRY["get_organisms"].handler(q)
