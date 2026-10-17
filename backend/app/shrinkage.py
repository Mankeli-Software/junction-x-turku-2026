"""Beta-binomial shrinkage toward a prior rate."""


def shrunk_rate(r: float, n: float, alpha: float, beta: float) -> float:
    """Posterior mean (R + alpha) / (n + alpha + beta).

    r is the number of resistant (or non-covered) isolates out of n. With few
    isolates the result stays near the prior mean alpha / (alpha + beta); with
    many it approaches r / n, with no jump at any threshold.
    """
    if alpha <= 0 or beta <= 0:
        raise ValueError("alpha and beta must be positive")
    if n < 0 or r < 0 or r > n:
        raise ValueError("need 0 <= r <= n")
    return (r + alpha) / (n + alpha + beta)


def prior_from_rate(rate: float, strength: float) -> tuple[float, float]:
    """Beta prior (alpha, beta) with mean `rate` worth `strength` pseudo-isolates."""
    if not 0 < rate < 1 or strength <= 0:
        raise ValueError("need 0 < rate < 1 and strength > 0")
    return rate * strength, (1 - rate) * strength
