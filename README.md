# AMRight

**A continuously updated antimicrobial resistance (AMR) monitor that tells a doctor which antibiotics are likely to work, and warns the lab and the wards when resistance changes unusually.**

Built for the Tyks Laboratories challenge at Junction x Turku 2026. Live demo: [amright.mankeli.co](https://amright.mankeli.co) (synthetic data only).

## The problem

Resistance is reported once a year, at hospital level. That is too coarse and too late for a doctor who has to pick an antibiotic before the culture result comes back, and too slow to catch an outbreak on a single ward. The challenge asked for a tool that shows the last four weeks beside the annual picture, filters on the dataset's parameters, and detects deviations, without being "just another BI dashboard".

## What it does

A personal dashboard with a chat box on top. Different people get different starting screens:

- **Doctor:** describe the patient (ward, sex, age, infection type, hospital or community onset) and see which drugs are likely to cover it, with honest ranges, the likely organisms, and the last 4 weeks next to the last 12 months. The chat can answer follow-up questions for that patient.
- **Infection control and care workers:** which resistant organisms (MRSA, ESBL, VRE, CPE) are showing up on which ward, how that compares with the ward's own year, and heads-up warnings for wards that share patients with an affected ward.
- **Lab and microbiologists:** an alert inbox with an investigation page for each alert, to tell a real change from sampling noise.
- **Researchers:** explore any filter and time period, compare periods, export CSV.
- **Anyone:** ask in plain language. The chat agent builds a screen from verified widgets and pins the ones you want to your home page.

Everything is also available as an open REST API and as an MCP server, so other systems and AI assistants can use the same numbers.

## Why you can trust the numbers

- **First isolate per patient only**, deduplicated within each rolling window, so one long infection does not count many times.
- **At least 30 isolates, or shrinkage.** Small samples are pulled toward the hospital rate (beta-binomial) and the tool says how many isolates there were and how much the estimate leans on that prior. Small samples hide percentages, never alerts.
- **Ranges, not single numbers.** Coverage across likely organisms is weighted by what actually causes the infection (WISCA-style), and untested or intrinsically resistant drugs are not counted as susceptible.
- **Replay without peeking.** Every query takes an `as_of` date, and nothing after that date can influence a result. A slider replays the three years of data week by week, which is how the demo shows alerts firing as they would have.
- **S, I and R everywhere**, even though the dataset has only S and R.
- **The AI never writes a number.** The chat agent can only call the same read-only functions as the API and choose widgets and their parameters. Every widget loads its own numbers from the API, and the one-line summary is checked so it cannot quote a figure that no tool returned.
- **Not a prescribing recommendation.** There are no diagnoses or respiratory samples in the data, so specimen stands in for infection type. The output is called local susceptibility coverage, and it gives no dosing.

## Detecting anomalies

Four kinds of alert run over the data, and each one is measured for how many weeks it takes to detect the planted signals and how many false alarms it raises per ward-year (see [docs/alert_evaluation.md](docs/alert_evaluation.md)):

- **Sentinel:** every carbapenemase-producing or vancomycin-resistant isolate is reported at once.
- **Statistical:** a ward whose 4-week rate of ESBL, MRSA or a drug is clearly above the hospital rate, with several drugs rising together before it fires.
- **Trend:** slow hospital-wide drift (Mann-Kendall test and Sen slope).
- **Missing data:** a ward that suddenly stops sending cultures.

## How it is built

- **Data:** a fully synthetic dataset of 10,000 patients and about 47,000 urine, blood and wound cultures over three years from nine wards and health centres. It is stored in PostgreSQL on Azure and read into memory at start.
- **Backend:** Python 3.12 and FastAPI with pandas and scipy. Each function is declared once in a registry that generates the REST routes, the MCP tools (`/mcp`, streamable HTTP) and the chat agent's tools, so there is one set of functions with three callers. Results are remembered and the screens' default queries are warmed before the first request.
- **Chat agent:** Claude through the Anthropic API, streaming widgets to the browser over server-sent events. The key stays in Azure Key Vault and never reaches the client.
- **Frontend:** Flutter web, with a design system taken from the design canvas, a widget catalog shared by name with the backend, and demo logins with a default screen for each role.
- **Azure:** App Service (API), Static Web Apps (frontend), Postgres Flexible Server, Key Vault and Application Insights, defined in Bicep and deployed by GitHub Actions with OIDC. Only a change to the app code redeploys the backend.

## Status

Working: the data layer and `as_of` replay, susceptibility with shrinkage, organism mix and coverage ranges, all four alert types, spreading and cross-ward warnings, every role's screens, the chat agent, the MCP server, and the Azure deployment.

Not built: a live feed from a hospital LIS (the data is replayed from a dataset), and real authentication. The API key is demo-grade protection and the data is synthetic, so real patient data would need private networking and proper login first.

## Where to read more

- [CHALLENGE.md](CHALLENGE.md): the challenge, the resources and the judging criteria.
- Issue [#1](../../issues/1): the full project plan, users, interview findings and data review.
- [docs/azure.md](docs/azure.md): how it is hosted and operated.
- [docs/age_bands.md](docs/age_bands.md) and [docs/alert_evaluation.md](docs/alert_evaluation.md): how age is split and how the alerts score.
- [data/synthetic_microbiology_dataset/README.md](data/synthetic_microbiology_dataset/README.md): the dataset.
- [AGENTS.md](AGENTS.md): the code layout and conventions, for contributors and coding agents.
