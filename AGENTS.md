# AGENTS.md

Hackathon project (Junction x Turku 2026): **AMRight**, a continuously updated antimicrobial resistance (AMR) monitoring tool. A doctor describes a patient and sees which antibiotics are likely to cover it (with honest ranges), the likely organisms, the last 4 weeks beside the last 12 months, and anomaly alerts. Everything is also exposed as an API, an MCP server and a chat agent.

## Read first

- [CHALLENGE.md](CHALLENGE.md) — the challenge description, insight, resources and judging criteria. Source of truth for what to build.
- GitHub issue #1 (`gh issue view 1`) — the project plan: users, features, API, architecture, AI → UI, build order and risks. Issue #3 holds the Azure and agent spec. Work is split into the numbered issues (DATA, ALERT, PLAT, UI); check `gh issue list` for what is open.
- [docs/azure.md](docs/azure.md) — Azure runbook (deploy, secrets, CI).
- [docs/age_bands.md](docs/age_bands.md) — the five age bands, how thin the data is per band, and why 18-44 is not split.

## Data

Fully synthetic microbiology dataset in [data/synthetic_microbiology_dataset/](data/synthetic_microbiology_dataset/). Read its [README.md](data/synthetic_microbiology_dataset/README.md) before working with the data. ML pipeline notes: [data/AEI_ML_PIPELINE.md](data/AEI_ML_PIPELINE.md).

Files (CSV, UTF-8): `patients.csv`, `cultures.csv` (urine, blood, wound), `isolates.csv`, `susceptibility.csv` (S/R only), `antibiotics.csv`, `wards.csv`. Structure: patients → cultures → isolates → susceptibility, joined on `patient_id`, `culture_id`, `isolate_id`.

Rules that every number must follow:

- Resistance and coverage use the **first isolate per patient**, deduplicated within each rolling window.
- Require at least 30 isolates; below that, shrink toward the hospital rate (beta-binomial, `backend/app/shrinkage.py`) and report the sample size and how much the estimate leans on the prior.
- Every query takes an `as_of` date (default 2026-09-27, the end of the data; range 2023-10-02 to 2026-09-27). Nothing after `as_of` may influence a result; `test_datalayer.py` asserts that.
- No diagnoses and no respiratory samples in the data: specimen stands in for infection type. Call the output "local susceptibility coverage", never a prescribing recommendation, and give no dosing.
- Carry S, I and R everywhere even though the data has only S and R. Aggregates only, no patient identifiers, except the optional patient-context endpoint.

## Layout

- `backend/app/` — FastAPI app (Python 3.12, pandas, scipy, pydantic v2).
  - `registry.py` — **declare each function once** with `@register(name, description, path, input_model, output_model)`; REST routes are generated from it, and the MCP server and the Claude agent tools will read the same registry (one set of functions, three callers). `GET /v1/functions` and `GET /v1/widgets` expose the registry and widget catalog as data.
  - `functions/` — handlers (`data.py`, `alerts.py`, `dashboard.py`). `models/` — request/response pydantic models. `vocab.py` — shared literals (wards, specimens, organisms, WHONET drug codes, age bands, windows, `MIN_ISOLATES`). `widgets/catalog.py` — widget names → parameter schemas; the AI picks widgets and params, it never writes a number.
  - `datalayer/` — `store.py` (load CSVs, isolate frame, first-isolate rule, `as_of` cut, window dates, `sir_rows`: S/I/R rows by integer-coded filters, small results remembered), `derive.py` (age band, onset, week start), `susceptibility.py` (shrunk estimates, outbreak-inflation flag, weekly series), `coverage.py` (organism mix, WISCA coverage per drug and pair, narrowest effective drug). `volume.py` (weekly culture counts per ward and specimen, seasonal baseline, `get_volume`), `alerts.py` (alert detectors in `DETECTORS`, alert list and detail; add new detectors there), `signals.py` (ward x organism cells clearly above the hospital rate, per day, cached; built on `susceptibility.py`), `trend.py` (monthly Mann-Kendall + Sen slope for slow drift). `spreading.py` (flag counts per ward against the ward's own year, ward links by shared patients within 30 days, cross-ward warnings from active alerts on linked wards). `shrinkage.py` — the shrinkage maths.
  - `agent/` — the chat agent (`POST /v1/agent/screen`, server-sent events). `schema.py` (request and the event vocabulary, which mirrors the Flutter `AgentEvent` types), `prompt.py` (frozen system prompt; the widget catalog in it is generated from `widgets/catalog.py`), `tools.py` (registry functions as read-only data tools, plus `render_widget`, `in_short`, `ask_user`; every input is validated), `llm.py` (`ClaudeClient` over `AsyncAnthropic`, and a scripted `FakeClient`; set `AGENT_FAKE=true` for a fixed screen without a key), `loop.py` (manual tool loop, 8 iterations at most, widgets sent as soon as their input is complete, summary checked by `numbers.py`), `route.py` (SSE with a `: ping` every 15 s; 503 without a key).
  - `fixtures/` — canned responses that keep the contract stable while real implementations land.
  - `db.py` — tiny psycopg connection and `ping()`. `schema.sql` — Postgres schema.
  - `config.py` — settings from env / `backend/.env`; the dataset ships in the deploy zip; `WARM_UP` (default true) computes the alert signals in a background thread at startup (about 12 s on a laptop).
- `frontend/` — Flutter web app (flutter_bloc, go_router); structure and rules in [frontend/README.md](frontend/README.md). `lib/ds/` is the design system with the exact tokens from the design canvas (Sora + Inter bundled in `assets/google_fonts`). `lib/core/` holds the transport (HTTP or `assets/fixtures`), typed models mirroring `backend/app/models`, the cached `AmrRepository` and `QueryView`. `lib/session/` holds the demo users and the replay `as_of`. `lib/catalog/` holds the widgets placed by name + params: same names as `widgets/catalog.py`, and a GenUI `CatalogItem` wraps each entry. `lib/features/` holds the screens (login, doctor, hygiene, lab, research, chat, dashboard, components). `--dart-define=API_BASE=...` or `--dart-define=FIXTURES=true`.
- `infra/` — Bicep (Key Vault, Postgres, App Service, Static Web App, monitoring). `scripts/` — deploy, OIDC bootstrap, Anthropic key, DB helpers. `.github/workflows/` — backend, frontend, infra what-if.

## Status

Real (computed from the data): data layer (#5), `GET /v1/susceptibility` and `/v1/susceptibility/series` with shrinkage (#6), Azure infrastructure and CI (#3), Postgres schema, CSV loader, DB-backed `/healthz` and `/v1/dashboard` (#11), `GET /v1/volume`, `/v1/alerts` and `/v1/alerts/detail` with sentinel (every CPE and VRE isolate) and missing-data alerts (#8). Statistical alerts (ESBL/MRSA flags and multi-drug rises above the hospital rate) and the hospital-wide trend alert (#9); `Alert.ward` is `None` for a trend. `GET /v1/spreading` and `/v1/ward-links` with cross-ward warnings (#10): a link is a patient sampled on both wards within 30 days (ED: PHC-N 413, GER 325, URO 291), a warning needs an active statistical or sentinel alert on the linked ward and a link of at least 5% of the smaller ward's patients. Rule scores: `docs/alert_evaluation.md`.

Chat agent (#12): `POST /v1/agent/screen` streams widgets built by Claude from the catalog; tested offline with the fake client and live with `pytest -m live` (needs `ANTHROPIC_API_KEY`). The Flutter app still uses its `ScriptedAgent`; the remote agent that reads these events is not written yet.

No endpoint returns a canned response any more; `fixtures/data.py` only supplies the `window_out` helper (`fixtures/alerts.py` is unused).

Flutter app (#14–#18 UI side): every screen and component in the design canvas, desktop and phone. Demo login with roles, replay slider, typed API client and fixture mode, the doctor flow (patient form → answer page), infection control (`/hygiene`, care workers see their wards first), lab inbox and investigation (`/lab`, `/lab/alerts/:id`), research Explore with chart, table, CSV export and API link (`/research`), chat (`/chat?q=`), pinned widgets on `/v1/dashboard`, and a live component gallery (`/components`). The 17 catalog widgets match `widgets/catalog.py`. Every "Ask" field opens the chat. The chat runs on a rule-based `ScriptedAgent` (`frontend/lib/features/chat/agent/`) that places the same catalog widgets; the Claude agent (#12) replaces it behind the `ChatAgent` interface. "In short" shows a placeholder until the agent writes it. Patient history reads a fixture (no endpoint yet); "Mark as reviewed" and "Send heads-up" are local only (no backend endpoints).

Not started: MCP server (#13). The app still reads the CSVs; Postgres holds a copy of the dataset (`backend/schema.sql`, loaded by `scripts/load_data.py --dsn ...`, idempotent) plus app tables such as `user_dashboards`. `/healthz` returns 503 unless the database answers (`backend/app/db.py`).

When you replace a fixture with a real implementation, keep the input/output models unchanged (the frontend codes against them), drop the `fx.` call from the handler, and add tests.

Build order (from #1): data and `as_of` → coverage/organisms/filters → alerts (sentinel, statistical, trend, missing data; four planted signals in the data, measure weeks-to-detect and false alarms) → replay slider → API + MCP → chat agent and dashboard → lab extras. Protect the non-AI steps first.

## Commands

```bash
python -m venv .venv && source .venv/bin/activate && pip install -e ".[dev]"
ruff check backend && pytest                     # CI runs both
cp backend/.env.example backend/.env             # leave ANTHROPIC_API_KEY empty: agent route returns 503, rest works
uvicorn app.main:app --reload --app-dir backend  # API on :8000, docs at /docs
ANTHROPIC_API_KEY=... .venv/bin/pytest -m live -s backend/tests/test_agent_live.py   # the real Claude API, a few cents
.venv/bin/python scripts/evaluate_alerts.py --quick   # weeks-to-detect and false alarms per ward-year for every alert rule (--out FILE writes markdown)
docker compose up -d db                          # optional local Postgres
cd frontend && flutter pub get && flutter analyze && flutter test
flutter run -d chrome --web-port 8080 --dart-define=API_BASE=http://localhost:8000  # CORS allows :8080
flutter run -d chrome --dart-define=FIXTURES=true                                   # no backend needed
```

## Conventions

- Python: ruff, line length 100. Pydantic models for every input and output; no `from __future__ import annotations` in `registry.py` (annotations are built dynamically).
- Models: the Claude API (`ANTHROPIC_MODEL`, set in env); the key lives in Key Vault in Azure and never reaches the client.
- Secrets and `.env` are gitignored; do not commit keys. Infra and deploy specifics are in [docs/azure.md](docs/azure.md).
- Commits and PRs reference the issue they close (e.g. `(#6)`).
- **Keep this file current.** Update AGENTS.md in the same change whenever something new is added or something changes that it documents: a fixture replaced by a real implementation (update Status), a new function, module, directory, command or env variable, a changed rule or convention, a finished or newly opened issue. Do not leave it for later; an outdated AGENTS.md is a bug.
