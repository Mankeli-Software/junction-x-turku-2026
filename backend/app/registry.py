"""Function registry: each function is declared once with input and output models.

REST routes are generated from it now. The MCP server and the agent tools read
the same registry later (name, description, input/output JSON Schema, handler).
"""

import threading
from collections import OrderedDict
from collections.abc import Callable
from dataclasses import dataclass
from typing import Annotated, Literal

from fastapi import APIRouter, Query
from pydantic import BaseModel


@dataclass(frozen=True)
class Function:
    name: str
    description: str
    path: str
    input_model: type[BaseModel]
    output_model: type[BaseModel]
    handler: Callable[[BaseModel], BaseModel]
    method: Literal["GET", "PUT"] = "GET"

    def input_schema(self) -> dict:
        return self.input_model.model_json_schema()

    def output_schema(self) -> dict:
        return self.output_model.model_json_schema()


REGISTRY: dict[str, Function] = {}

RESULT_CACHE_SIZE = 512
_results: OrderedDict[tuple[str, str], BaseModel] = OrderedDict()
_results_lock = threading.Lock()


def clear_results() -> None:
    """Forget every remembered result (tests that swap the data call this)."""
    with _results_lock:
        _results.clear()


def _remembered(name: str, handler: Callable[[BaseModel], BaseModel]) -> Callable[[BaseModel], BaseModel]:
    """The data never changes under a request, so one answer per (function, input) is enough.

    The remembered output is shared between callers: treat it as read-only. A handler that
    raises is not remembered.
    """

    def run(q: BaseModel) -> BaseModel:
        key = (name, q.model_dump_json())
        with _results_lock:
            if key in _results:
                _results.move_to_end(key)
                return _results[key]
        out = handler(q)
        with _results_lock:
            _results[key] = out
            if len(_results) > RESULT_CACHE_SIZE:
                _results.popitem(last=False)
        return out

    run.__wrapped__ = handler  # type: ignore[attr-defined]
    return run


def register(
    name: str,
    description: str,
    path: str,
    input_model: type[BaseModel],
    output_model: type[BaseModel],
    method: Literal["GET", "PUT"] = "GET",
    cache: bool = True,
):
    """Decorator: declare a function once. Reads of the dataset are remembered; pass cache=False
    for a function that reads state which changes (the dashboard)."""

    def deco(handler: Callable[[BaseModel], BaseModel]):
        if name in REGISTRY:
            raise ValueError(f"duplicate function {name}")
        wrapped = _remembered(name, handler) if cache and method == "GET" else handler
        REGISTRY[name] = Function(name, description, path, input_model, output_model, wrapped, method)
        return handler

    return deco


def build_router(prefix: str = "/v1") -> APIRouter:
    router = APIRouter(prefix=prefix)
    for fn in REGISTRY.values():
        router.add_api_route(
            fn.path,
            _endpoint(fn),
            methods=[fn.method],
            response_model=fn.output_model,
            name=fn.name,
            summary=fn.description,
            tags=["functions"],
        )
    return router


def _endpoint(fn: Function):
    # No `from __future__ import annotations` here: the annotations are built from fn.
    if fn.method == "GET":

        def endpoint(params: Annotated[fn.input_model, Query()]):  # type: ignore[name-defined]
            return fn.handler(params)

    else:

        def endpoint(params: fn.input_model):  # type: ignore[name-defined]
            return fn.handler(params)

    endpoint.__name__ = fn.name
    return endpoint
