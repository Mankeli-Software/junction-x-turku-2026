import pytest
from app import ratelimit
from app.config import settings
from app.main import app
from app.ratelimit import Limit, client_ip
from fastapi.testclient import TestClient

client = TestClient(app)
BODY = {"user_id": "rate-limit-test", "role": "lab", "layout": []}


@pytest.fixture
def two_puts(monkeypatch):
    monkeypatch.setattr(ratelimit, "LIMITS", (Limit("PUT", "/v1/dashboard", 2, 600),))


def put(forwarded: str):
    return client.put("/v1/dashboard", json=BODY, headers={"X-API-Key": "secret", "X-Forwarded-For": forwarded})


def test_a_caller_over_the_limit_gets_429_and_other_callers_do_not(two_puts, monkeypatch):
    monkeypatch.setattr(settings, "api_key", "secret")
    assert put("8.8.8.8").status_code == 200
    assert put("8.8.8.8:51000").status_code == 200
    r = put("1.1.1.1, 8.8.8.8:51001")  # a forged address on the left changes nothing
    assert r.status_code == 429 and int(r.headers["retry-after"]) > 0
    assert put("8.8.4.4").status_code == 200


def test_reads_are_not_limited(two_puts, monkeypatch):
    monkeypatch.setattr(settings, "api_key", "secret")
    headers = {"X-API-Key": "secret", "X-Forwarded-For": "8.8.8.8"}
    assert all(client.get("/v1/dashboard", headers=headers).status_code == 200 for _ in range(3))


def test_no_limits_without_a_key(two_puts):
    assert all(put("8.8.8.8").status_code == 200 for _ in range(3))


def test_the_window_slides():
    limit = Limit("PUT", "/x", 2, 60)
    assert limit.take("a", 0) == 0 and limit.take("a", 10) == 0
    assert limit.take("a", 20) == 40
    assert limit.take("a", 60) == 0  # the first request has left the window


def _scope(forwarded: str | None = None) -> dict:
    headers = [(b"x-forwarded-for", forwarded.encode())] if forwarded else []
    return {"headers": headers, "client": ("10.0.0.9", 1234)}


def test_the_client_is_the_rightmost_public_address():
    assert client_ip(_scope("8.8.8.8:51000")) == "8.8.8.8"
    assert client_ip(_scope("1.1.1.1, 8.8.8.8:51000")) == "8.8.8.8"
    assert client_ip(_scope("8.8.8.8:51000, 10.0.0.4")) == "8.8.8.8"  # an internal hop is skipped
    assert client_ip(_scope("[2001:4860::1]:443")) == client_ip(_scope("2001:4860::ffff")) == "2001:4860::/64"
    assert client_ip(_scope("not an address")) == client_ip(_scope()) == "10.0.0.9"


def test_every_claude_and_write_route_has_a_limit():
    """A new agent route or write must get a limit too."""
    covered = {(x.method, x.prefix) for x in ratelimit.LIMITS}
    for route in app.routes:
        path = getattr(route, "path", "")
        for method in getattr(route, "methods", None) or ():
            if (path.startswith("/v1/agent/") or method in {"POST", "PUT", "DELETE"}) and path.startswith("/v1/"):
                assert any(method == m and path.startswith(p) for m, p in covered), (method, path)
