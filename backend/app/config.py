from datetime import date
from pathlib import Path
from typing import Literal

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
    warm_up: bool = True  # compute the alert signals in the background at startup
    # Chat agent (PLAT-2). The key comes from Key Vault in Azure; without it the agent route returns 503.
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-sonnet-5-5"
    agent_effort: Literal["low", "medium", "high"] = "medium"
    agent_fake: bool = False  # stream a fixed screen from a scripted client, no API call
    agent_fallbacks: bool = True  # server-side refusal fallback beta (works with streaming; set false if the API rejects it)
    data_dir: str = _default_data_dir()

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()
