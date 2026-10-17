"""The MCP server at /mcp: same tools and results as the REST routes, and the API key."""

import json

import pytest
from app.config import settings
from app.main import app
from app.registry import REGISTRY
from fastapi.testclient import TestClient

HEADERS = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}


def rpc(client, method, params=None, headers=None, id=1):
    body = {"jsonrpc": "2.0", "id": id, "method": method, "params": params or {}}
    return client.post("/mcp", json=body, headers={**HEADERS, **(headers or {})})


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:  # the lifespan starts the MCP session manager, which can start only once
        yield c


@pytest.fixture
def keyed(monkeypatch):
    monkeypatch.setattr(settings, "api_key", "secret")


def test_lists_the_registry_functions_as_tools(client):
    r = rpc(client, "tools/list")
    assert r.status_code == 200
    tools = {t["name"]: t for t in r.json()["result"]["tools"]}
    expected = {n for n, f in REGISTRY.items() if f.method == "GET" and n != "get_dashboard"}
    assert set(tools) == expected
    assert tools["get_susceptibility"]["inputSchema"]["properties"]["drug"]


def test_a_call_returns_the_same_result_as_the_rest_route(client):
    params = {"ward": "URO", "organism": "Escherichia coli", "drug": "CRO", "specimen": "urine"}
    rest = client.get("/v1/susceptibility", params=params).json()
    r = rpc(client, "tools/call", {"name": "get_susceptibility", "arguments": params})
    result = r.json()["result"]
    assert not result.get("isError")
    assert result["structuredContent"] == rest
    assert json.loads(result["content"][0]["text"]) == rest


def test_a_bad_input_is_a_tool_error_the_client_can_read(client):
    r = rpc(client, "tools/call", {"name": "get_susceptibility", "arguments": {"ward": "NOPE"}})
    result = r.json()["result"]
    assert result["isError"] and "ward" in result["content"][0]["text"]
    r = rpc(client, "tools/call", {"name": "get_dashboard", "arguments": {}})
    assert r.json()["result"]["isError"]


def test_mcp_needs_the_key_when_one_is_set(client, keyed):
    assert rpc(client, "tools/list").status_code == 401
    assert rpc(client, "tools/list", headers={"X-API-Key": "wrong"}).status_code == 401
    assert rpc(client, "tools/list", headers={"X-API-Key": "secret"}).status_code == 200
    assert rpc(client, "tools/list", headers={"Authorization": "Bearer secret"}).status_code == 200


def test_rest_needs_the_key_except_from_the_browser_app_and_the_probes(client, keyed, monkeypatch):
    monkeypatch.setattr(settings, "cors_origins", "https://polite-desert-1.azurestaticapps.net")
    url = "/v1/volume"
    assert client.get(url).status_code == 401
    assert client.get(url, headers={"X-API-Key": "secret"}).status_code == 200
    assert client.get(url, headers={"Origin": "https://polite-desert-1.azurestaticapps.net"}).status_code == 200
    assert client.get(url, headers={"Origin": "https://evil.example"}).status_code == 401
    # another Static Web App is not this app
    assert client.get(url, headers={"Origin": "https://evil-1.azurestaticapps.net"}).status_code == 401
    assert client.get("/healthz").status_code != 401
    assert client.get("/v1/data-status").status_code != 401
    assert client.options(url, headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "GET"}).status_code != 401
