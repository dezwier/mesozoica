"""Public legal HTML pages for app-store policy URLs."""

from __future__ import annotations

import html
import re
from functools import lru_cache
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse

DOCUMENTS_DIR = Path(__file__).resolve().parent / "documents"

PAGES = {
    "privacy": ("privacy-policy.md", "Privacy Policy"),
    "terms": ("terms-and-conditions.md", "Terms and Conditions"),
    "delete-account": ("delete-account.md", "Delete account"),
    "delete-data": ("delete-data.md", "Delete data"),
}

router = APIRouter(tags=["legal"], include_in_schema=False)


def _markdown_to_html(source: str) -> str:
    """Convert a constrained Markdown subset used by the legal documents."""
    text = source.replace("\r\n", "\n").strip("\n")
    blocks = re.split(r"\n\n+", text)
    parts: list[str] = []
    for block in blocks:
        lines = [line.rstrip() for line in block.split("\n") if line.strip() != ""]
        if not lines:
            continue
        if len(lines) == 1 and lines[0].startswith("# "):
            parts.append(f"<h1>{_inline(lines[0][2:])}</h1>")
            continue
        if len(lines) == 1 and lines[0].startswith("## "):
            parts.append(f"<h2>{_inline(lines[0][3:])}</h2>")
            continue
        if len(lines) == 1 and lines[0].startswith("### "):
            parts.append(f"<h3>{_inline(lines[0][4:])}</h3>")
            continue
        if all(line.startswith("- ") for line in lines):
            items = "".join(f"<li>{_inline(line[2:])}</li>" for line in lines)
            parts.append(f"<ul>{items}</ul>")
            continue
        if all(re.match(r"^\d+\.\s", line) for line in lines):
            items = "".join(
                f"<li>{_inline(re.sub(r'^\d+\.\s', '', line))}</li>" for line in lines
            )
            parts.append(f"<ol>{items}</ol>")
            continue
        paragraph = "<br>".join(_inline(line) for line in lines)
        parts.append(f"<p>{paragraph}</p>")
    return "\n".join(parts)


def _inline(text: str) -> str:
    escaped = html.escape(text)

    def _link(match: re.Match[str]) -> str:
        label = match.group(1)
        href = html.escape(match.group(2), quote=True)
        return f'<a href="{href}">{label}</a>'

    linked = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", _link, escaped)
    return re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", linked)


def _page_html(title: str, body: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)} · Mesozoica</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #1c1b1f;
      --fg: #d7ccc8;
      --muted: #bcaaa4;
      --accent: #c4a484;
    }}
    body {{
      margin: 0;
      font-family: Georgia, "Times New Roman", serif;
      background: var(--bg);
      color: var(--fg);
      line-height: 1.6;
    }}
    main {{
      max-width: 46rem;
      margin: 0 auto;
      padding: 2.5rem 1.25rem 4rem;
    }}
    a {{ color: var(--accent); }}
    h1, h2, h3 {{
      font-weight: 700;
      line-height: 1.25;
      color: #f5ebe0;
    }}
    h1 {{ font-size: 2rem; margin-bottom: 0.4rem; }}
    h2 {{ font-size: 1.25rem; margin-top: 2rem; }}
    nav {{
      display: flex;
      flex-wrap: wrap;
      gap: 0.75rem 1.25rem;
      margin: 1.25rem 0 2rem;
      font-family: system-ui, sans-serif;
      font-size: 0.95rem;
    }}
    .brand {{
      font-family: system-ui, sans-serif;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      color: var(--muted);
      font-size: 0.8rem;
    }}
    ul, ol {{ padding-left: 1.3rem; }}
    li {{ margin: 0.25rem 0; }}
    p {{ margin: 0.85rem 0; }}
  </style>
</head>
<body>
  <main>
    <div class="brand">Mesozoica</div>
    <nav>
      <a href="/privacy">Privacy</a>
      <a href="/terms">Terms</a>
      <a href="/delete-account">Delete account</a>
      <a href="/delete-data">Delete data</a>
    </nav>
    {body}
  </main>
</body>
</html>
"""


@lru_cache(maxsize=8)
def render_legal_page(slug: str) -> str:
    spec = PAGES.get(slug)
    if spec is None:
        raise KeyError(slug)
    filename, fallback_title = spec
    path = DOCUMENTS_DIR / filename
    if not path.is_file():
        raise FileNotFoundError(filename)
    source = path.read_text(encoding="utf-8")
    return _page_html(fallback_title, _markdown_to_html(source))


async def _response(slug: str) -> HTMLResponse:
    try:
        return HTMLResponse(render_legal_page(slug))
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Not found") from exc


@router.get("/privacy", response_class=HTMLResponse)
async def privacy_policy() -> HTMLResponse:
    return await _response("privacy")


@router.get("/terms", response_class=HTMLResponse)
async def terms() -> HTMLResponse:
    return await _response("terms")


@router.get("/delete-account", response_class=HTMLResponse)
async def delete_account() -> HTMLResponse:
    return await _response("delete-account")


@router.get("/delete-data", response_class=HTMLResponse)
async def delete_data() -> HTMLResponse:
    return await _response("delete-data")


def register_legal_routes(app) -> None:
    app.include_router(router)
