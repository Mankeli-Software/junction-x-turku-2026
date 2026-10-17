"""POST /v1/agent/screen: the agent's server-sent event stream."""

import asyncio
import logging
from collections.abc import AsyncIterator
from typing import Annotated

import anthropic
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from app.agent import summary
from app.agent.a2ui import to_a2ui
from app.agent.llm import LLMClient, make_client
from app.agent.loop import run
from app.agent.schema import PING, AgentRequest, sse
from app.agent.summary import InShortOut, SpreadingInShortQuery
from app.models.alerts import AlertDetailQuery
from app.models.data import CoverageQuery

log = logging.getLogger("uvicorn.error")

router = APIRouter()

# App Service's front end drops a connection that is silent for about 230 s, so never stay silent
# that long. A comment line is invisible to the client's event parser.
HEARTBEAT_SECONDS = 15.0


async def event_stream(req: AgentRequest, llm: LLMClient) -> AsyncIterator[str]:
    queue: asyncio.Queue[str | None] = asyncio.Queue()

    async def produce() -> None:
        try:
            async for event, data in to_a2ui(run(req, llm)):
                await queue.put(sse(event, data))
        finally:
            await queue.put(None)

    task = asyncio.create_task(produce())
    try:
        while True:
            try:
                item = await asyncio.wait_for(queue.get(), HEARTBEAT_SECONDS)
            except TimeoutError:
                yield PING
                continue
            if item is None:
                break
            yield item
    finally:
        task.cancel()  # the browser went away: stop paying for the model


@router.post("/v1/agent/screen", tags=["agent"])
async def screen(req: AgentRequest) -> StreamingResponse:
    """Build the user's screen from catalog widgets and stream it as A2UI. See app/agent/schema.py for the events.

    Answers 503 when there is no API key; the rest of the API is unaffected and the app falls back
    to the quick patient form.
    """
    llm = make_client()
    if llm is None:
        raise HTTPException(status_code=503, detail="AI answers are paused: no API key is configured.")
    return StreamingResponse(
        event_stream(req, llm),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"},
    )


async def _line(kind: summary.Kind, q: BaseModel) -> InShortOut:
    llm = summary.make_summary_client()
    if llm is None:
        raise HTTPException(status_code=503, detail="AI answers are paused: no API key is configured.")
    try:
        return await summary.in_short(kind, q, llm)
    except anthropic.APIError as e:
        log.error("in_short %s: %s", kind.name, type(e).__name__)  # never the message: a header error carries the key
        raise HTTPException(status_code=503, detail="The AI service is not answering right now.") from e


@router.get("/v1/agent/in-short", tags=["agent"], response_model=InShortOut)
async def get_in_short(q: Annotated[CoverageQuery, Query()]) -> InShortOut:
    """"In short" for the doctor's answer page: one or two sentences over the same numbers the page shows.

    Takes the query of /v1/coverage. Every number in the line is checked against those results; text is
    null when no checked line came back. 503 without an API key or when the AI service fails, so the
    app keeps its placeholder.
    """
    return await _line(summary.COVERAGE, q)


@router.get("/v1/agent/in-short/alert", tags=["agent"], response_model=InShortOut)
async def get_alert_in_short(q: Annotated[AlertDetailQuery, Query()]) -> InShortOut:
    """"In short" for the lab's alert page: real or more testing, how the ward compares, the next step.

    Built from /v1/alerts/detail and the ward's /v1/ward-links; checked like the answer page's line.
    """
    return await _line(summary.ALERT, q)


@router.get("/v1/agent/in-short/spreading", tags=["agent"], response_model=InShortOut)
async def get_spreading_in_short(q: Annotated[SpreadingInShortQuery, Query()]) -> InShortOut:
    """"In short" for infection control: the ward the page leads with against its usual, and whom to warn.

    Built from /v1/spreading, /v1/spreading/series and the ward's /v1/ward-links; checked like the
    answer page's line. Without a ward (none is above its usual level), the line says so.
    """
    return await _line(summary.SPREADING, q)
