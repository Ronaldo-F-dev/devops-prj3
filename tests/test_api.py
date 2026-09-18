from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root():
    response = client.get("/")

    assert response.status_code == 200


def test_health_reports_uptime():
    response = client.get("/health")

    # 200 (base disponible) ou 503 (base injoignable) sont tous les deux
    # des reponses valides du endpoint -- ce test verifie seulement que
    # uptime_seconds est toujours present, quel que soit l'etat de la base.
    assert response.status_code in (200, 503)
    assert response.json()["uptime_seconds"] >= 0