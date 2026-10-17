"""POST /v1/agent/screen: the agent's server-sent event stream."""

import asyncio
from collections.abc import AsyncIterator

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from app.agent.llm import LLMClient, make_client
from app.agent.loop import run
from app.agent.schema import PING, AgentRequest, sse

router = APIRouter()

# App Service's front end drops a connection that is silent for about 230 s, so never stay silent
# that long. A comment line is invisible to the client's event parser.
HEARTBEAT_SECONDS = 15.0


async def event_stream(req: AgentRequest, llm: LLMClient) -> AsyncIterator[str]:
    queue: asyncio.Queue[str | None] = asyncio.Queue()

    async def produce() -> None:
        try:
            async for event, data in run(req, llm):
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
    """Build the user's screen from catalog widgets and stream it. See app/agent/schema.py for the events.

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
