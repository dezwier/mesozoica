FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY rag/pyproject.toml ./rag/pyproject.toml
COPY rag/src/ ./rag/src/
RUN pip install --no-cache-dir ./rag

# tiktoken otherwise downloads encoding assets on first use. Cache every encoding
# shipped by the installed version so any validated configuration is startup-safe.
ENV TIKTOKEN_CACHE_DIR=/opt/tiktoken-cache
RUN mkdir -p "$TIKTOKEN_CACHE_DIR" && python -c "import tiktoken; [tiktoken.get_encoding(name) for name in tiktoken.list_encoding_names()]"

COPY app/ ./app/
COPY scripts/ ./scripts/
COPY alembic/ ./alembic/
COPY alembic.ini .
COPY migrate.sh .
COPY docker-entrypoint.sh .

RUN chmod +x migrate.sh docker-entrypoint.sh

# OSM masks live on a Railway volume (/data), not in the image. docker-entrypoint.sh
# fetches once on first boot when files are missing.
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD sh -c "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"
