#!/bin/bash
set -euo pipefail
cd /app
alembic upgrade head
