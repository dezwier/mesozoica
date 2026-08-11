"""Guard the public HTTP contract during internal feature moves."""

import hashlib
import json

from app.main import app


OPENAPI_SHA256 = "c6daca8d714d9fe4275d349ea6010eba7756be29ab8ead0b1dfcae00c0f1b5fa"


def test_openapi_contract_is_unchanged() -> None:
    encoded = json.dumps(
        app.openapi(), sort_keys=True, separators=(",", ":")
    ).encode()
    assert hashlib.sha256(encoded).hexdigest() == OPENAPI_SHA256
