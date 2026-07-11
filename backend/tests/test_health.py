def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_ready(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_api_root(client):
    response = client.get("/api/v1/")
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "mesozoica-api"
    assert "version" in body
