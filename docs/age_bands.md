# Age bands

The five bands are fixed in `backend/app/vocab.py` (`AgeBand`) and cut in `backend/app/datalayer/derive.py`
from the patient's age at the culture (`age_years`, 0 to 99): **0-17, 18-44, 45-64, 65-74, 75+**.
The band is part of the API contract (request models, Flutter models and form, widget catalog,
agent tools), so changing it is a change everywhere.

## How much data each band has

First isolates over the 12 months to 2026-09-27 (hospital-wide, first-isolate rule):

| Band | First isolates | Urine | Blood | Wound |
| --- | --- | --- | --- | --- |
| 0-17 | 420 | 324 | 18 | 78 |
| 18-44 | 1,651 | 1,264 | 69 | 318 |
| 45-64 | 1,333 | 1,020 | 41 | 272 |
| 65-74 | 1,428 | 1,023 | 53 | 352 |
| 75+ | 2,158 | 1,525 | 109 | 524 |

- No band is under 30 on its own. The thin spots are children (33 first isolates in the last 4 weeks;
  18 blood isolates in a year, 4 of them E. coli) and age on small wards: GER has 4, 12 and 6 first
  isolates under 65.
- Cutting by age band x ward x specimen leaves 60 of 111 cells under 30. Those estimates are shrunk
  toward the hospital rate and say so (`Estimate.prior_weight`, shown as "Leans mostly on ...").
- The data skews old: 65 and over is about 45% of first isolates, so the hospital rate that small
  cells shrink toward is mostly an older-adult rate. Nothing in the answer says that a thin
  *age group* is the reason; it only says how much the number leans on the prior.

## Why 18-44 stays one band

The band spans 27 years, against 18, 20 and 10 for its neighbours, so a split was considered.
We checked whether the data supports it, with 18-29 (728 first isolates) against 30-44 (923):

| E. coli in urine | 18-29 | 30-44 |
| --- | --- | --- |
| Ampicillin resistant | 32.1% (n=287) | 37.7% (n=377) |
| Trimethoprim resistant | 25.4% | 20.4% |
| Ciprofloxacin resistant | 8.7% | 8.2% |
| Nitrofurantoin resistant | 0.3% | 0.5% |

- The ampicillin and trimethoprim gaps are about 1.5 standard errors each (a back-of-envelope
  check, not a formal test), and they point in opposite directions: no age trend.
- The organism mix is the same in both halves (E. coli, S. aureus, E. faecalis, K. pneumoniae in
  similar proportions), and so is the specimen mix.
- The band is not small: 1,651 first isolates, fewer than 75+ (2,158).
- A split halves the sample in cells that are already often under 30, so more answers would show
  wide ranges for no visible gain.

**Limit of this check.** The dataset is synthetic. If the generator built no age effect into the
18-44 range, none can show here. In real data the two halves might differ (for example through
pregnancy-related urine infections, which this data has no field for). The rule we would apply to
real data: split a band when the data shows a difference *and* each half keeps enough isolates.

**What we say if asked:** 18-44 is wide; no difference between 18-29 and 30-44 was found in this
data. The 0-17 band mixes infants and teenagers and would benefit most from a split, but the data
is too thin for it (137 cultures at age 0, 560 at ages 1 to 4).
