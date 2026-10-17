"""Per-IP limits on the routes that cost money or write: the Claude calls under `/v1/agent/` and
`PUT /v1/dashboard`.

A forged `Origin` header gets past the API key (see auth.py), so these keep one caller from
spending the Anthropic budget or filling the dashboard table. The counts live in each worker's
memory: with gunicorn's 2 workers a caller can get up to twice the limit, and a restart clears
them. The client is the rightmost public address in X-Forwarded-For (the App Service front end
appends the caller's address; anything to its left came from the caller), and IPv6 counts per /64.
Like the key check, the limits apply only when API_KEY is set: local work and the tests are unlimited.
"""

import ipaddress
import math
import time
from collections import deque
from dataclasses import dataclass, field

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from app.config import settings

MAX_CLIENTS = 10_000  # past this many callers, forget the ones whose window has passed


@dataclass
class Limit:
    method: str
    prefix: str
    requests: int
    seconds: float
    hits: dict[str, deque[float]] = field(default_factory=dict)

    def take(self, client: str, now: float) -> float:
        """Count one request: 0 when allowed, else the seconds until the caller may try again."""
        if len(self.hits) > MAX_CLIENTS:
            self.hits = {c: q for c, q in self.hits.items() if q[-1] > now - self.seconds}
        q = self.hits.setdefault(client, deque())
        while q and q[0] <= now - self.seconds:
            q.popleft()
        if len(q) >= self.requests:
            return q[0] + self.seconds - now
        q.append(now)
        return 0.0


LIMITS = (
    Limit("POST", "/v1/agent/screen", 20, 600),  # a chat question: up to 8 Claude calls
    Limit("GET", "/v1/agent/in-short", 120, 600),  # one short call per page, none when remembered
    Limit("PUT", "/v1/dashboard", 30, 600),
)


def _address(entry: str) -> ipaddress.IPv4Address | ipaddress.IPv6Address | None:
    s = entry.strip()
    if s.startswith("["):  # [v6]:port
        s = s[1 : s.find("]")]
    elif s.count(":") == 1:  # v4:port, as App Service sends it
        s = s.split(":")[0]
    try:
        return ipaddress.ip_address(s)
    except ValueError:
        return None


def client_ip(scope: Scope) -> str:
    forwarded = next((v.decode("latin-1") for k, v in scope["headers"] if k == b"x-forwarded-for"), "")
    for entry in reversed(forwarded.split(",")):
        ip = _address(entry)
        if ip and ip.is_global:
            return str(ipaddress.ip_network(f"{ip}/64", strict=False)) if ip.version == 6 else str(ip)
    return scope["client"][0] if scope.get("client") else ""


class RateLimitMiddleware:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] == "http" and settings.api_key:
            method, path = scope["method"], scope["path"]
            limit = next((x for x in LIMITS if x.method == method and path.startswith(x.prefix)), None)
            wait = limit.take(client_ip(scope), time.monotonic()) if limit else 0.0
            if wait:
                resp = JSONResponse(
                    {"detail": "Too many requests from this network. Try again in a few minutes."},
                    status_code=429,
                    headers={"Retry-After": str(math.ceil(wait))},
                )
                return await resp(scope, receive, send)
        await self.app(scope, receive, send)
