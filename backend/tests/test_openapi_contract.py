"""Guard the public HTTP contract during internal feature moves."""

import hashlib
import json

from app.main import app


OPENAPI_SHA256 = "0cec141ddaa963ffae1be9bf56f54e2c2a17f81a89364d7c6fa5cb4f8e6bf0e7"


def test_openapi_contract_is_unchanged() -> None:
    encoded = json.dumps(
        app.openapi(), sort_keys=True, separators=(",", ":")
    ).encode()
    assert hashlib.sha256(encoded).hexdigest() == OPENAPI_SHA256

