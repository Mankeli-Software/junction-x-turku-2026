# AMRight

**Bringing antimicrobial resistance (AMR) data in real-time to be used widely across the whole healthcare ecosystem.**

Live demo: [amright.mankeli.co](https://amright.mankeli.co).

## The problem

Resistance is reported once a year, at hospital level. That is too coarse and too late for a doctor who has to pick an antibiotic **right now**, and too slow to catch an outbreak on a single ward.

## What it does

We present a solution that has its own UI and features for multiple job roles:

- **Doctor:** describe the patient (ward, sex, age, infection type, onset) and see which drugs are likely to cover it grounded in WISCA-based analytics.
- **Infection control and care workers:** which resistant organisms are showing up on which ward, and heads-up warnings for wards that share patients with an affected ward.
- **Lab and microbiologists:** an alert inbox with an investigation page for each alert, to tell a real change from sampling noise.
- **Researchers:** explore any filter and time period, compare periods, export CSV.
- **Anyone:** ask in plain language. The chat agent builds a screen from verified widgets and pins the ones you want to your home page.

Everything is also available as an open REST API and as an MCP server, so other systems and AI assistants can use the same numbers.

## Analytics

What it found from the dataset
- An ESBL outbreak on the urology ward and an MRSA cluster in the ICU, plus 17 CPE and VRE isolates flagged as sentinel events.
- Both outbreaks were detected about 2.3 weeks after onset, with 0 false alarms.
- One ward (PHC-S) stopped sending cultures for a week (8 to 14 December 2025). The missing-data alert flagged it 6 days after the gap began, with no false alarms.

Why this beats the alternatives we tested
- A yearly, hospital-level report shows none of the above.
- The shrunk estimate is 6.9% more accurate than the raw ward rate and matches the hospital antibiogram in normal weeks.

## Tech Stack
- **Backend:** Python with FastAPI & MCP Server wrapper, running on App Service in Azure
- **Database:** PostgreSQL on Azure
- **LLM:** Anthropic Claude (Sonnet 5.5)
- **Frontend:** Flutter Web running on Azure Static Web Apps

<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/e1814524-eaca-455a-b76a-2e062f12f798" />
