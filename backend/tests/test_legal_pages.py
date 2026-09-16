"""Public legal HTML pages used by App Store and Play Store listings."""

from app.main import app


def test_privacy_policy_page(client):
    response = client.get("/privacy")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "Privacy Policy" in response.text
    assert "contact@mesozoica.app" in response.text


def test_terms_page(client):
    response = client.get("/terms")
    assert response.status_code == 200
    assert "Terms and Conditions" in response.text


def test_delete_account_page(client):
    response = client.get("/delete-account")
    assert response.status_code == 200
    assert "Delete account" in response.text
    assert "Profile" in response.text


def test_delete_data_page(client):
    response = client.get("/delete-data")
    assert response.status_code == 200
    assert "Delete data" in response.text


def test_legal_pages_are_not_in_openapi():
    schema = app.openapi()
    paths = schema.get("paths", {})
    for path in ("/privacy", "/terms", "/delete-account", "/delete-data"):
        assert path not in paths


def test_legal_documents_match_flutter_assets():
    from pathlib import Path

    backend_dir = Path(__file__).resolve().parents[1] / "app" / "legal" / "documents"
    flutter_dir = (
        Path(__file__).resolve().parents[2] / "flutter" / "assets" / "policies"
    )
    names = sorted(path.name for path in backend_dir.glob("*.md"))
    assert names
    assert names == sorted(path.name for path in flutter_dir.glob("*.md"))
    for name in names:
        assert (backend_dir / name).read_text(encoding="utf-8") == (
            flutter_dir / name
        ).read_text(encoding="utf-8")
