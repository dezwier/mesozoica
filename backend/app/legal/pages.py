"""Public legal routes that redirect to learnfromdata.ai/mesozoica."""

from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import RedirectResponse

CANONICAL_BASE = "https://learnfromdata.ai/mesozoica"

PAGES = {
    "privacy": f"{CANONICAL_BASE}/privacy",
    "terms": f"{CANONICAL_BASE}/terms",
    "delete-account": f"{CANONICAL_BASE}/delete-account",
    "delete-data": f"{CANONICAL_BASE}/delete-data",
}

router = APIRouter(tags=["legal"], include_in_schema=False)


def _redirect(slug: str) -> RedirectResponse:
    return RedirectResponse(PAGES[slug], status_code=301)


@router.get("/privacy")
async def privacy_policy() -> RedirectResponse:
    return _redirect("privacy")


@router.get("/terms")
async def terms() -> RedirectResponse:
    return _redirect("terms")


@router.get("/delete-account")
async def delete_account() -> RedirectResponse:
    return _redirect("delete-account")


@router.get("/delete-data")
async def delete_data() -> RedirectResponse:
    return _redirect("delete-data")


def register_legal_routes(app) -> None:
    app.include_router(router)
