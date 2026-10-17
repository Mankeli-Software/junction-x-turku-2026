from datetime import date

import pandas as pd
from app.datalayer.store import Tables

AS_OF_DATES = [date(2024, 6, 30), date(2025, 1, 15), date(2025, 8, 31), date(2025, 12, 31), date(2026, 5, 20)]


def cut_tables(t: Tables, as_of: date) -> Tables:
    """The data as it would have existed on as_of: no culture after it."""
    cultures = t.cultures[t.cultures["sample_date"] <= pd.Timestamp(as_of)]
    ids = set(cultures["culture_id"])
    return Tables(
        patients=t.patients,
        cultures=cultures,
        isolates=t.isolates[t.isolates["culture_id"].isin(ids)],
        susceptibility=t.susceptibility[t.susceptibility["culture_id"].isin(ids)],
        antibiotics=t.antibiotics,
        wards=t.wards,
    )
