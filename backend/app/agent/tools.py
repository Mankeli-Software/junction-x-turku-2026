"""The tools Claude may call.

Data tools are the registry functions (the same code as the REST API and the MCP server). They
return aggregates only. Three more tools place things on the screen:

- render_widget: pick a catalog widget and its query parameters. Nothing is fetched for the model;
  the server validates the parameters and the widget loads its own numbers.
- in_short: the one free-text line, checked against this request's tool results.
- ask_user: a clarifying question with tappable answers.

Every tool input is validated here, whatever the schema promised: a stream cut short by
max_tokens can leave a truncated but well-formed input.
"""

import asyncio
import json
from datetime import date
from typing import Any

from pydantic import ValidationError

import app.functions.alerts
import app.functions.data  # noqa: F401
from app.agent.schema import AgentProfile
from app.registry import REGISTRY
from app.widgets.catalog import CATALOG

DATA_TOOLS = [
    "get_coverage",
    "get_organisms",
    "get_susceptibility",
    "get_alerts",
    "get_alert_detail",
    "get_spreading",
    "get_volume",
    "get_ward_links",
]
UI_TOOLS = ("render_widget", "in_short", "ask_user")
MAX_RESULT_CHARS = 24_000  # a tool result is cut here so one call cannot fill the context


def _plain_schema(schema: dict[str, Any]) -> dict[str, Any]:
    """The pydantic schema without as_of: the server sets the replay date, the model never does."""
    schema = json.loads(json.dumps(schema))
    schema.get("properties", {}).pop("as_of", None)
    schema.pop("title", None)
    return schema


def tool_definitions() -> list[dict[str, Any]]:
    """Tools in a fixed order, so the cached prompt prefix stays byte-identical between requests."""
    tools: list[dict[str, Any]] = []
    for name in DATA_TOOLS:
        fn = REGISTRY[name]
        tools.append(
            {
                "name": name,
                "description": f"{fn.description} Read-only; returns aggregates, never patient identifiers.",
                "input_schema": _plain_schema(fn.input_schema()),
                "eager_input_streaming": True,
            }
        )
    tools.append(
        {
            "name": "render_widget",
            "description": (
                "Put one catalog widget on the user's screen. Give the widget name and its query parameters; "
                "the widget loads its own numbers from the API, so you never supply a number. Call it once per widget."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "widget": {"type": "string", "enum": sorted(CATALOG)},
                    "params": {"type": "object", "description": "query parameters of the widget, see the catalog"},
                },
                "required": ["widget", "params"],
                "additionalProperties": False,
            },
            "eager_input_streaming": True,
        }
    )
    tools.append(
        {
            "name": "in_short",
            "description": (
                "The one short line shown under the widgets, in the user's language. Call it last, after the data "
                "tools. It may repeat numbers from the tool results but must not contain any other number."
            ),
            "input_schema": {
                "type": "object",
                "properties": {"text": {"type": "string", "maxLength": 400}},
                "required": ["text"],
                "additionalProperties": False,
            },
            "eager_input_streaming": True,
        }
    )
    tools.append(
        {
            "name": "ask_user",
            "description": (
                "Ask one clarifying question when something needed is missing (for example the infection type or "
                "whether it started at home or in hospital). Give 2 to 4 short answers, the likeliest first."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "question": {"type": "string", "maxLength": 200},
                    "options": {"type": "array", "items": {"type": "string", "maxLength": 60}, "minItems": 2, "maxItems": 4},
                    "understood": {
                        "type": "object",
                        "description": "the patient fields you already understood (ward, infection_type, sex, age_band, onset), so the app keeps them for the answer",
                    },
                },
                "required": ["question", "options"],
                "additionalProperties": False,
            },
            "eager_input_streaming": True,
        }
    )
    return tools


class ToolError(Exception):
    """A tool call the model should see as an error and can correct."""


def _fix_as_of(model: type, params: dict[str, Any], as_of: date) -> dict[str, Any]:
    out = dict(params)
    if "as_of" in model.model_fields:
        out["as_of"] = as_of.isoformat()  # the replay slider decides the date, never the model
    return out


def _errors(e: ValidationError) -> str:
    return "; ".join(f"{'.'.join(map(str, err['loc'])) or 'input'}: {err['msg']}" for err in e.errors()[:6])


def validate_widget(inp: Any, as_of: date) -> tuple[str, dict[str, Any]]:
    """(widget, params) ready to send, or ToolError."""
    if not isinstance(inp, dict) or not isinstance(inp.get("widget"), str) or not isinstance(inp.get("params"), dict):
        raise ToolError("render_widget needs a widget name and a params object")
    name = inp["widget"]
    model = CATALOG.get(name)
    if model is None:
        raise ToolError(f"unknown widget {name!r}; choose one of {', '.join(sorted(CATALOG))}")
    try:
        valid = model.model_validate(_fix_as_of(model, inp["params"], as_of))
    except ValidationError as e:
        raise ToolError(f"bad params for {name}: {_errors(e)}") from e
    return name, valid.model_dump(mode="json", exclude_none=True)


def validate_ask(inp: Any) -> tuple[str, list[str], dict[str, Any] | None]:
    """(question, options, profile understood so far)."""
    if not isinstance(inp, dict) or not isinstance(inp.get("question"), str):
        raise ToolError("ask_user needs a question and options")
    options = inp.get("options")
    if not isinstance(options, list) or not 2 <= len(options) <= 4 or not all(isinstance(o, str) and o for o in options):
        raise ToolError("ask_user needs 2 to 4 non-empty text options")
    understood = None
    if isinstance(inp.get("understood"), dict):
        try:
            understood = AgentProfile.model_validate(inp["understood"]).model_dump(mode="json", exclude_none=True)
        except ValidationError as e:
            raise ToolError(f"bad understood profile: {_errors(e)}") from e
    return inp["question"].strip(), [o.strip() for o in options], understood


def validate_text(inp: Any) -> str:
    if not isinstance(inp, dict) or not isinstance(inp.get("text"), str) or not inp["text"].strip():
        raise ToolError("in_short needs a non-empty text")
    return inp["text"].strip()


async def run_data_tool(name: str, inp: Any, as_of: date) -> Any:
    """Run a registry function and return its output as plain JSON data."""
    fn = REGISTRY.get(name)
    if fn is None or name not in DATA_TOOLS:
        raise ToolError(f"unknown tool {name!r}")
    if not isinstance(inp, dict):
        raise ToolError("the tool input must be an object")
    try:
        query = fn.input_model.model_validate(_fix_as_of(fn.input_model, inp, as_of))
    except ValidationError as e:
        raise ToolError(f"bad input for {name}: {_errors(e)}") from e
    try:
        out = await asyncio.to_thread(fn.handler, query)  # pandas work: keep it off the event loop
    except Exception as e:  # an HTTPException (unknown alert id) or a data error: the model may correct it
        detail = getattr(e, "detail", None) or str(e)
        raise ToolError(f"{name} failed: {detail}") from e
    return out.model_dump(mode="json")


def result_text(data: Any) -> str:
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    if len(text) > MAX_RESULT_CHARS:
        text = text[:MAX_RESULT_CHARS] + '..."[result cut]"'
    return text
