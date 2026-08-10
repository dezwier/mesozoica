"""Guard the public HTTP contract during internal feature moves."""

import hashlib
import json

from app.main import app


OPENAPI_SHA256 = "6cdc4ef6e6120751421725cb4f7e69c8e8f8d68f371efe5572db7d49b507183e"


def test_openapi_contract_is_unchanged() -> None:
    encoded = json.dumps(
        app.openapi(), sort_keys=True, separators=(",", ":")
    ).encode()
    assert hashlib.sha256(encoded).hexdigest() == OPENAPI_SHA256
