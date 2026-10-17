import pytest

from app.shrinkage import prior_from_rate, shrunk_rate


def test_no_data_returns_prior_mean():
    assert shrunk_rate(0, 0, 2, 18) == pytest.approx(0.1)


def test_formula():
    assert shrunk_rate(3, 10, 2, 8) == pytest.approx(5 / 20)


def test_many_isolates_approach_raw_rate():
    assert shrunk_rate(500, 1000, 2, 18) == pytest.approx(0.5, abs=0.01)


def test_few_isolates_stay_near_prior():
    # 3 of 5 resistant against a 5% prior worth 100 isolates barely moves.
    assert shrunk_rate(3, 5, *prior_from_rate(0.05, 100)) < 0.08


def test_monotone_in_r():
    assert shrunk_rate(2, 10, 1, 9) < shrunk_rate(3, 10, 1, 9)


@pytest.mark.parametrize("r,n", [(-1, 5), (6, 5), (1, -1)])
def test_invalid_counts(r, n):
    with pytest.raises(ValueError):
        shrunk_rate(r, n, 1, 1)


def test_invalid_prior():
    with pytest.raises(ValueError):
        shrunk_rate(1, 2, 0, 1)
    with pytest.raises(ValueError):
        prior_from_rate(1.2, 10)
