FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY rag/pyproject.toml ./rag/pyproject.toml
COPY rag/src/ ./rag/src/
RUN pip install --no-cache-dir ./rag

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
