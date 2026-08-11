"""HTTP adapter owned by the assistant feature."""

from app.features.assistant.api_ask import router as ask_router
from app.features.assistant.api_knowledge import router as knowledge_router

routers = (ask_router, knowledge_router)

__all__ = ["routers"]
