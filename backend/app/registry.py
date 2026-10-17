"""Function registry: each function is declared once with input and output models.

REST routes are generated from it now. The MCP server and the agent tools read
the same registry later (name, description, input/output JSON Schema, handler).
"""

from dataclasses import dataclass
from typing import Annotated, Callable, Literal

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


def register(
    name: str,
    description: str,
    path: str,
    input_model: type[BaseModel],
    output_model: type[BaseModel],
    method: Literal["GET", "PUT"] = "GET",
):
    """Decorator: declare a function once."""

    def deco(handler: Callable[[BaseModel], BaseModel]):
        if name in REGISTRY:
            raise ValueError(f"duplicate function {name}")
        REGISTRY[name] = Function(name, description, path, input_model, output_model, handler, method)
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
