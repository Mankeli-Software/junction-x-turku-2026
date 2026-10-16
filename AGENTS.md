# AGENTS.md

Hackathon project (Junction x Turku 2026): a continuously updated antimicrobial resistance (AMR) monitoring tool.

## Read first

- [CHALLENGE.md](CHALLENGE.md) — the challenge description, insight, resources and judging criteria. Treat it as the source of truth for what to build.

## Data

Fully synthetic microbiology dataset in [data/synthetic_microbiology_dataset/](data/synthetic_microbiology_dataset/). Read its [README.md](data/synthetic_microbiology_dataset/README.md) before working with the data.

Files (CSV, UTF-8, comma-separated):

- `patients.csv`
- `cultures.csv` — samples (urine, blood, wound)
- `isolates.csv` — organisms found
- `susceptibility.csv` — S/R results
- `antibiotics.csv`
- `wards.csv`

Structure: patients → cultures → isolates → susceptibility. Join on `patient_id`, `culture_id` and `isolate_id`.

Tips from the challenge: compute resistance percentages from the first isolate per patient, and require at least 30 isolates.

Additional notes on the ML pipeline: [data/AEI_ML_PIPELINE.md](data/AEI_ML_PIPELINE.md).
