import asyncio
import logging

from sqlalchemy import text
from sqlmodel import Session, SQLModel, create_engine

from app.core.config import settings

logger = logging.getLogger(__name__)

db_url = settings.database_url
if db_url.startswith("postgres://"):
    db_url = db_url.replace("postgres://", "postgresql://", 1)

if db_url.startswith("sqlite"):
    engine = create_engine(
        db_url,
        echo=False,
        connect_args={"check_same_thread": False},
    )
else:
    engine = create_engine(
        db_url,
        echo=False,
        pool_pre_ping=True,
        pool_size=10,
        max_overflow=20,
        pool_recycle=3600,
    )


def get_session():
    """FastAPI dependency for database sessions."""
    with Session(engine) as session:
        yield session


def init_db() -> None:
    """Create tables for registered SQLModel metadata."""
    SQLModel.metadata.create_all(engine)


def _ping_db() -> None:
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))


async def check_connection() -> tuple[bool, str]:
    """Verify database connectivity for readiness probes."""
    if not db_url or db_url.startswith("sqlite"):
        return True, ""
    try:
        await asyncio.wait_for(
            asyncio.get_event_loop().run_in_executor(None, _ping_db),
            timeout=3.0,
        )
        return True, ""
    except asyncio.TimeoutError:
        return False, "database timeout"
    except Exception as exc:
        return False, str(exc)
