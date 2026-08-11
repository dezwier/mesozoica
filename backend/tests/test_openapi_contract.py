"""Guard the public HTTP contract during internal feature moves."""

import hashlib
import json

from app.main import app


OPENAPI_SHA256 = "387f5808265ed1e53387bf0f0e45bd44e68ff555ace96be47a5b61af25a821bc"


def test_openapi_contract_is_unchanged() -> None:
    encoded = json.dumps(
        app.openapi(), sort_keys=True, separators=(",", ":")
    ).encode()
    assert hashlib.sha256(encoded).hexdigest() == OPENAPI_SHA256
