from datetime import date
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

DATASET = "data/synthetic_microbiology_dataset"


def _default_data_dir() -> str:
    """The repo root in a checkout (backend/app/config.py), or the folder holding app/ in the deploy zip."""
    here = Path(__file__).resolve()
    candidates = [here.parents[2] / DATASET, here.parents[1] / DATASET]
    return str(next((c for c in candidates if c.is_dir()), candidates[0]))


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://aei:aei@localhost:5432/aei"
    api_key: str = ""
    cors_origins: str = "http://localhost:3000,http://localhost:8080"
    as_of_default: date = date(2026, 9, 27)
    data_dir: str = _default_data_dir()

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()
