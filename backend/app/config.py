from datetime import date
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://aei:aei@localhost:5432/aei"
    api_key: str = ""
    cors_origins: str = "http://localhost:3000,http://localhost:8080"
    as_of_default: date = date(2026, 9, 27)
    data_dir: str = str(REPO_ROOT / "data/synthetic_microbiology_dataset")

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()
