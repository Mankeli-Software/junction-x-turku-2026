"""MCP server: the registry's read-only functions as tools, over streamable HTTP at `/mcp`.

One set of functions, three callers: a tool call runs the same handler as the REST route (and the
same remembered result), after the same input validation. Stateless JSON responses, so any of the
gunicorn workers can answer any request. The API key is checked in `app/auth.py`.
"""

import asyncio
import json

from fastapi import HTTPException
from mcp import types
from mcp.server.lowlevel import Server
from mcp.server.lowlevel.server import ServerRequestContext
from pydantic import ValidationError

from app.registry import REGISTRY

INSTRUCTIONS = (
    "Local antimicrobial susceptibility coverage for a hospital, from a synthetic dataset. "
    "Every tool returns aggregates with sample sizes and ranges; nothing is a prescribing recommendation. "
    "`as_of` replays the data up to a date (2023-10-02 to 2026-09-27, default the end)."
)


def tools() -> list[types.Tool]:
    """Every GET function in the registry; the dashboard (user state) and PUT functions are not exposed."""
    return [
        types.Tool(
            name=fn.name,
            description=f"{fn.description} Read-only; aggregates only.",
            input_schema=fn.input_schema(),
            output_schema=fn.output_schema(),
        )
        for fn in REGISTRY.values()
        if fn.method == "GET" and fn.name != "get_dashboard"
    ]


def _error(text: str) -> types.CallToolResult:
    return types.CallToolResult(content=[types.TextContent(type="text", text=text)], is_error=True)


def call(name: str, arguments: dict | None) -> types.CallToolResult:
    fn = REGISTRY.get(name)
    if fn is None or fn.method != "GET" or name == "get_dashboard":
        return _error(f"unknown tool {name!r}")
    try:
        query = fn.input_model.model_validate(arguments or {})
        out = fn.handler(query).model_dump(mode="json")
    except ValidationError as e:
        return _error("; ".join(f"{'.'.join(map(str, x['loc'])) or 'input'}: {x['msg']}" for x in e.errors()[:6]))
    except (HTTPException, ValueError) as e:  # an HTTPException (unknown alert id) or a data error: the client may correct it
        return _error(f"{name} failed: {getattr(e, 'detail', None) or e}")
    text = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    return types.CallToolResult(content=[types.TextContent(type="text", text=text)], structured_content=out)


async def _list_tools(ctx: ServerRequestContext, params: types.PaginatedRequestParams | None) -> types.ListToolsResult:
    return types.ListToolsResult(tools=tools())


async def _call_tool(ctx: ServerRequestContext, params: types.CallToolRequestParams) -> types.CallToolResult:
    return await asyncio.to_thread(call, params.name, params.arguments)  # pandas work: off the event loop


server = Server("amright", version="0.1.0", instructions=INSTRUCTIONS, on_list_tools=_list_tools, on_call_tool=_call_tool)
# Stateless and plain JSON: with two workers a session held in one of them would break the next request.
app = server.streamable_http_app(streamable_http_path="/mcp", json_response=True, stateless_http=True, host="0.0.0.0")
