"""Configuration for the isolated Deep Sec administrator console."""

from dataclasses import dataclass
import os
from pathlib import Path


def _required(name: str) -> str:
    value = os.getenv(name, "")
    if not value:
        raise RuntimeError(f"{name} must be configured")
    return value


@dataclass(frozen=True)
class AdminSettings:
    host: str
    port: int
    secret_key: str
    dsn: str
    wallet_location: str
    database_dir: str
    vibe_executable: Path
    vibe_project_root: Path


def load_admin_settings() -> AdminSettings:
    return AdminSettings(
        host=os.getenv("ADMIN_FLASK_HOST", "0.0.0.0"),
        port=int(os.getenv("ADMIN_FLASK_PORT", "7778")),
        secret_key=_required("ADMIN_FLASK_SECRET_KEY"),
        dsn=_required("ADMIN_DB_DSN"),
        wallet_location=_required("ADMIN_WALLET_LOCATION"),
        database_dir=_required("DEEP_SEC_DATABASE_DIR"),
        vibe_executable=Path(os.getenv("ADMIN_VIBE_EXECUTABLE", "/home/opc/bin/vibe")),
        vibe_project_root=Path(os.getenv("ADMIN_VIBE_PROJECT_ROOT", "/opt/deep-sec-customer-sales")),
    )
