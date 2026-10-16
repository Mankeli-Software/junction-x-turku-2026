# AEI – ML Model Training & Validation Pipeline

Brief for Claude Code. Scope: **only the ML model, its training and its validation.** No app, no API, no dashboards. The goal is to find out, rigorously, whether a resistance-prediction model is good enough to build a product on, and to produce evidence we can pitch.

Context: JunctionX Turku hackathon, case by Tyks Laboratories × Mylab ("Antibiotic efficacy indicator"). Judges are laboratory professionals, so methodology must be clinically sound and honest.

## 1. Question this pipeline must answer

> Does an ML model predict antibiotic resistance **better and more reliably** than the antibiogram a doctor would otherwise use, without data leakage, across wards and patient groups?

Output: a generated `report.md` with a clear **GO / NO-GO** verdict per task, backed by tables, plots and confidence intervals.

## 2. Data

Synthetic microbiology dataset in `data/raw/` (CSV, UTF-8, comma, ISO dates). Period 2023-10-02 → 2026-09-27.

| File | Key columns |
|---|---|
| `patients.csv` | patient_id, sex (F/M), birth_year, home_area |
| `cultures.csv` | culture_id, patient_id, age_years, sample_date, ward_code, ward_type (in/out), institution, admission_date (inpatients), specimen (urine/blood/wound), result, n_isolates |
| `isolates.csv` | isolate_id, culture_id, organism, quantity, esbl, mrsa, vre, cpe |
| `susceptibility.csv` | isolate_id, culture_id, organism, antibiotic, antibiotic_code, result (S/R), guideline |

Expected row counts: 10,000 patients / 46,792 cultures / 24,571 isolates / 172,381 susceptibility results. Assert these on load.

Antibiotic codes: AMP, MEC, TZP, FOX, CXM, CRO, CAZ, MEM, CIP, TMP, NIT, VAN, CLI. MEC, TMP, NIT are urine only.

Known properties (from prior analysis):
- Urine E. coli resistance differs by sex.
- Two outbreaks exist: URO ESBL E. coli (≈ 2025-05-25 → 2025-07-29) and ICU MRSA (2026-03-03 → 2026-03-27). E. coli trimethoprim resistance drifts up ≈ 2 pp/year.
- Volume is seasonal (summer peak).
- **Feasibility test result:** the generator appears to have **no patient memory**. Prior same-drug resistance did not predict current resistance (urine E. coli CIP: 8.2% vs 8.1%). Quick models gave AUC ≈ 0.53–0.61, mostly from sex and ward. Expect modest gains; the pipeline must measure them honestly, not chase them.

## 3. Prediction tasks

### Task 1 – Isolate-level resistance prediction ("personalized antibiogram")

Unit: one row per `isolate × antibiotic` tested. Target: `R = 1`, `S = 0`.

Two clinical scenarios, evaluated separately:

- **1a. Organism known** (lab has identified the species, susceptibility pending). Features may include organism.
- **1b. Empiric / organism unknown** (doctor prescribes before any lab result). Unit becomes `culture × antibiotic`; target = "antibiotic fails to cover at least one isolate in this culture" (cultures with growth only). Features may not include organism or anything else from the lab result. This is the scenario that matters most clinically.

Train one model per antibiotic or one model with antibiotic as a feature; compare both if time allows.

### Task 2 – Ward-level forecast

Unit: `ward × organism × antibiotic × week t`. Target: resistant proportion among first isolates in `(t, t + 28 days]`. Inputs: only data ≤ `t`.

Purpose: tests whether the 4-week ward view the product shows is a better guide to the near future than the annual report.

Only cells with ≥ 5 first isolates in the target window are evaluated; weight errors by n.

## 4. Leakage rules (non-negotiable)

Everything about the current sample that comes from the lab is **unavailable at prescribing time**.

Never use as features for the current row:
- Any susceptibility result of the same isolate or culture (other antibiotics).
- `esbl`, `mrsa`, `vre`, `cpe` flags of the current isolate.
- `quantity`, `n_isolates`, `result` of the current culture.
- `organism` in Task 1b.
- Anything with a date after the current `sample_date`.

Patient history features may use only cultures with `sample_date <= current sample_date - 2 days` (lab results take time to arrive).

All feature functions take an `as_of` date and must be tested to prove they ignore later data.

## 5. Features

Context:
- age (years, plus age band), sex
- ward_code, ward_type, institution
- specimen
- onset: hospital onset if inpatient and `sample_date - admission_date >= 2 days`, else community
- days since admission (inpatients, capped)
- month (cyclic sin/cos encoding), years since dataset start (trend)
- home_area

Patient history (as_of-safe):
- number of prior positive cultures (any, last 365 days)
- prior resistance to this antibiotic (any organism / same organism), last 365 days
- prior ESBL / MRSA / VRE / CPE ever
- days since last positive culture

Local epidemiology (as_of-safe, computed from other patients only):
- ward resistance rate for this organism × antibiotic, trailing 28 days and 365 days (shrunk, see 6)
- hospital resistance rate, trailing 365 days

Task 1a adds `organism`.

## 6. Models

Baselines (must be implemented first, same evaluation harness):
- **B0** – hospital annual antibiogram: trailing-365-day hospital resistance rate for organism × antibiotic (Task 1a) or syndromic coverage rate per specimen (Task 1b).
- **B1** – ward annual antibiogram: trailing-365-day ward rate.
- **B2** – ward 4-week rate, empirical Bayes beta-binomial shrunk toward the hospital rate. Posterior mean `(R + α) / (n + α + β)`, prior fitted on trailing-12-month hospital data.

Learned models:
- **M1** – Logistic regression (L2, standardized numeric features, one-hot categoricals, sex × organism interaction).
- **M2** – `HistGradientBoostingClassifier` (scikit-learn). LightGBM optional; on macOS run `brew install libomp` first.
- Calibration: compare uncalibrated vs isotonic / Platt calibration fitted on a time-later validation slice inside the training data.

For Task 2, compare B1, B2 and a GBM regressor (Poisson or Tweedie loss) on the same rows.

Hyperparameter tuning only inside training folds, with time-ordered splits. Fixed random seeds. All settings in `config.yaml`.

## 7. Validation design

### 7.1 Splits

- **Final hold-out:** 2026-04-01 → 2026-09-27. Do not touch until the final run. Contains the ICU MRSA outbreak tail and the end-of-data period.
- **Rolling-origin evaluation** on the rest: train on everything before `T`, test on `[T, T + 3 months)`, for T = 2024-10-01, 2025-01-01, 2025-04-01, 2025-07-01, 2025-10-01, 2026-01-01. Report per fold and pooled.
- **Patient grouping:** report results both on all test rows and on test rows from patients **never seen** in training. Real deployment sees both.
- Inner tuning split: last 3 months of each training window as validation.

### 7.2 Metrics

Probabilistic quality:
- Brier score (primary), log loss, AUROC, AUPRC.
- Calibration: reliability plot (10 bins), calibration slope and intercept, expected calibration error.

Clinical usefulness (decision-oriented):
- **Empiric coverage simulation:** for each test row in Task 1b, each method picks the narrowest-spectrum antibiotic with predicted susceptibility ≥ 90% (spectrum order configurable, default urine: NIT, MEC, TMP, CXM, CIP, CRO, TZP, MEM). Report actual coverage rate and share of broad-spectrum picks (CRO, CAZ, TZP, MEM, CIP). A useful model keeps or improves coverage while using less broad-spectrum antibiotics.
- Decision curve (net benefit) for the main antibiotics.

Uncertainty:
- 95% CIs by **patient-cluster bootstrap** (resample patients, 1,000 reps).
- Paired difference model − best baseline with CI.

Subgroups (each metric per subgroup):
- ward, sex, specimen, organism, onset, age band
- outbreak periods vs non-outbreak periods
- small-n wards (ICU, MED-B)

### 7.3 Sanity checks (all must pass)

1. **Label permutation:** shuffle targets within training data; model AUROC on test must be ≈ 0.5.
2. **Leakage canary:** deliberately add a forbidden feature (e.g. ESBL flag of the current isolate) in a separate run; performance must jump. Confirms the harness would expose leakage. Never ship this run.
3. **Future-data test:** unit test that every feature value is identical whether computed on full data or on data truncated at `as_of`.
4. **Learning curve:** performance vs training-set size (10%–100%) to show whether more data would help.
5. **Feature importance:** permutation importance on test data; check top features are clinically plausible.
6. **History-effect check:** report resistance rate given prior same-drug resistance vs none, per organism. Documents the "no patient memory" property of the synthetic data.

## 8. GO / NO-GO criteria

A learned model is **GO** for a task only if all hold on the final hold-out:
1. Brier score better than the best baseline, with the paired-difference 95% CI excluding zero.
2. Better than best baseline in at least 4 of 6 rolling folds.
3. Calibration slope between 0.8 and 1.2.
4. No subgroup with ≥ 100 rows is worse than the best baseline by more than 10% relative Brier.
5. In the empiric coverage simulation (Task 1b), coverage is not lower than the best baseline's by more than 1 percentage point.

Otherwise **NO-GO**: the product uses the best baseline (expected: B2 shrinkage antibiogram), and the report states why. A NO-GO with clean evidence is a valid, pitchable result.

## 9. Repository layout

```
aei-ml/
├── CLAUDE.md                  # this file
├── config.yaml
├── data/raw/                  # CSVs (gitignored)
├── pyproject.toml             # uv
├── aeiml/
│   ├── load.py                # load + row-count assertions + joins
│   ├── derive.py              # onset, first-isolate selection, fingerprints
│   ├── features.py            # as_of-safe feature builders
│   ├── datasets.py            # builds Task 1a, 1b, 2 tables
│   ├── baselines.py           # B0, B1, B2
│   ├── models.py              # M1, M2, calibration
│   ├── splits.py              # rolling origin, hold-out, unseen-patient filter
│   ├── metrics.py             # Brier, calibration, bootstrap, coverage sim
│   ├── sanity.py              # permutation, leakage canary, learning curve
│   └── report.py              # writes report.md + plots
├── scripts/
│   ├── run_all.py             # one command, full pipeline
│   └── run_holdout.py         # final hold-out evaluation (run last)
├── artifacts/                 # trained models, LR coefficients JSON
├── output/                    # report.md, plots, tables (CSV)
└── tests/
```

Commands:
```zsh
uv sync
uv run python scripts/run_all.py        # rolling-origin + sanity checks
uv run python scripts/run_holdout.py    # final verdict
uv run pytest
```

Stack: Python 3.12, uv, DuckDB or pandas/Polars, NumPy, SciPy, scikit-learn, matplotlib, PyYAML, joblib, pytest. Developer machine: macOS Apple Silicon.

## 10. Work order and acceptance criteria

1. **Load & derive.** Done when row counts assert, onset and first-isolate logic have unit tests.
2. **Features & datasets.** Done when Task 1a, 1b and 2 tables build, and the future-data test passes for every feature.
3. **Baselines B0–B2 + evaluation harness.** Done when rolling-origin metrics for baselines are written to `output/`.
4. **Models M1, M2 + calibration.** Done when they run through the same harness.
5. **Sanity checks.** Done when all six pass and results are in the report.
6. **Clinical metrics.** Done when coverage simulation and decision curves are produced.
7. **Report.** Done when `report.md` contains: summary table per task, GO/NO-GO per task with reasons, calibration plots, subgroup table, sanity check results, history-effect check, limitations section.
8. **Hold-out run.** Only after 1–7 are final. Done when the verdict is written.
9. **Export.** If M1 is GO: export coefficients, feature encoding and intercepts as JSON for use in a Dart client. Write a short model card (intended use, data, metrics, limitations, "synthetic data only, not clinically validated").

## 11. Rules for Claude Code

- Do not look at the final hold-out until step 8.
- Never hard-code outbreak dates, wards or known signals into features or models.
- Every feature builder takes `as_of` and has a future-data test.
- Same harness for baselines and models. No metric computed one way for baselines and another for models.
- Report negative results plainly. Do not tune on the hold-out, do not drop subgroups that look bad.
- Keep everything reproducible: seeds and settings in `config.yaml`, one command reruns all.
- Short docstrings explaining the clinical or statistical reason behind each rule.
