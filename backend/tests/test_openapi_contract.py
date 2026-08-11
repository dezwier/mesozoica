"""Guard the public HTTP contract during internal feature moves."""

import hashlib
import json

from app.main import app


OPENAPI_SHA256 = "74dd5f38ddafcb6cae13165193e825667de1e7d34c3ff86b84c90dfe2209064b"


def test_openapi_contract_is_unchanged() -> None:
    encoded = json.dumps(
        app.openapi(), sort_keys=True, separators=(",", ":")
    ).encode()
    assert hashlib.sha256(encoded).hexdigest() == OPENAPI_SHA256
