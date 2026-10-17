"""Demo-grade API key for non-browser clients.

`/mcp` always needs the key. REST under `/v1` needs it unless the request comes from an allowed browser
origin (the Flutter app, which does not log in). `/healthz` and `/v1/data-status` stay open for the
health probe and the deploy checks. The `Origin` header can be forged by a non-browser client, so
this keeps casual callers out and nothing more; real data would need real authentication.
With no `API_KEY` set (local work, tests) everything is open.
"""

import hmac
import re

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from app.config import settings

ORIGIN_REGEX = re.compile(r"https://.*\.azurestaticapps\.net")
OPEN_PATHS = ("/v1/data-status",)


def _header(scope: Scope, name: bytes) -> str:
    return next((v.decode("latin-1") for k, v in scope["headers"] if k == name), "")


def _key_ok(scope: Scope) -> bool:
    given = _header(scope, b"x-api-key")
    auth = _header(scope, b"authorization")
    if not given and auth.lower().startswith("bearer "):
        given = auth[7:].strip()
    return hmac.compare_digest(given.encode(), settings.api_key.encode())


def _browser_origin(scope: Scope) -> bool:
    origin = _header(scope, b"origin")
    return origin in settings.cors_origin_list or bool(ORIGIN_REGEX.fullmatch(origin))


class ApiKeyMiddleware:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] == "http" and settings.api_key and scope["method"] != "OPTIONS":
            path = scope["path"]
            needs_key = path == "/mcp" or path.startswith("/mcp/")
            needs_key = needs_key or (path.startswith("/v1/") and path not in OPEN_PATHS and not _browser_origin(scope))
            if needs_key and not _key_ok(scope):
                resp = JSONResponse({"detail": "API key required: send X-API-Key"}, status_code=401)
                return await resp(scope, receive, send)
        await self.app(scope, receive, send)
