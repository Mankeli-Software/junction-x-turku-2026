from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.functions import alerts, dashboard, data  # noqa: F401  (registers functions)
from app.registry import REGISTRY, build_router
from app.widgets.catalog import catalog_schemas

app = FastAPI(title="AMRight API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_origin_regex=r"https://.*\.azurestaticapps\.net",
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(build_router("/v1"))


@app.get("/healthz")
def healthz():
    # The database check arrives with the Postgres issue.
    return {"status": "ok"}


@app.get("/v1/functions", tags=["meta"])
def functions():
    """The registry as data: what the MCP server and the agent will expose as tools."""
    return [
        {
            "name": f.name,
            "description": f.description,
            "method": f.method,
            "path": f"/v1{f.path}",
            "input_schema": f.input_schema(),
        }
        for f in REGISTRY.values()
    ]


@app.get("/v1/widgets", tags=["meta"])
def widgets():
    return catalog_schemas()
