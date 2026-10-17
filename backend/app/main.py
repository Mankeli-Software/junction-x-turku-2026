import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware

from app import db, mcp_server, warmup
from app.agent.route import router as agent_router
from app.auth import ApiKeyMiddleware
from app.config import settings
from app.functions import alerts, dashboard, data  # noqa: F401  (registers functions)
from app.ratelimit import RateLimitMiddleware
from app.registry import REGISTRY, build_router
from app.widgets.catalog import catalog_schemas


@asynccontextmanager
async def lifespan(_: FastAPI):
    # The alert signals take about 12 s to compute once; do it in the background at startup, unless the
    # preload below already did everything before the workers forked.
    if settings.warm_up and warmup.result is None:
        from app.datalayer import alerts as alert_engine
        from app.datalayer.store import get_store

        threading.Thread(target=lambda: alert_engine.warm_up(get_store()), daemon=True, name="alert-warm-up").start()
    async with mcp_server.server.session_manager.run():  # the mounted /mcp app has no lifespan of its own here
        yield


if settings.preload_warm:
    # Under `gunicorn --preload` this runs once in the master process; the workers inherit the caches.
    warmup.run()

app = FastAPI(title="AMRight API", version="0.1.0", lifespan=lifespan)

# Inside CORS, so the browser app can read a 429.
app.add_middleware(RateLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(build_router("/v1"))
app.include_router(agent_router)
app.add_middleware(ApiKeyMiddleware)


@app.get("/healthz")
def healthz(response: Response):
    """200 only when the database answers SELECT 1; App Service uses this as its health check."""
    if db.ping():
        return {"status": "ok"}
    response.status_code = 503
    return {"status": "database unavailable"}


@app.get("/v1/data-status", tags=["meta"])
def data_status(response: Response):
    """Dataset table row counts against the CSVs. CI calls this after each deploy."""
    try:
        actual = db.table_counts()
    except db.psycopg.Error:
        response.status_code = 503
        return {"ok": False, "error": "database unavailable"}
    tables = {t: {"expected": n, "actual": actual[t]} for t, n in db.DATASET_ROWS.items()}
    from app.datalayer import signals
    from app.datalayer.store import get_store

    return {
        "ok": all(v["expected"] == v["actual"] for v in tables.values()),
        "tables": tables,
        "signals": signals.cache_status(get_store()),
        "warm_up": warmup.result,
    }


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


# Last, so that every route above matches first: the mounted app answers /mcp only.
app.mount("/", mcp_server.app)
