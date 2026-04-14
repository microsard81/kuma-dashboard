"""
Test per gli endpoint APNs Flask — Proprietà 14 + test unitari.

Proprietà 14: Validazione payload subscribe APNs (backend)
  Per qualsiasi payload JSON inviato a POST /push/apns/subscribe che non contenga
  il campo device_token, il backend deve restituire HTTP 400.

  **Valida: Requisiti 10.3**

Test unitari (task 3.3):
  - Subscribe con payload valido → 201
  - Subscribe senza sessione autenticata → 401 o redirect
  - Unsubscribe con token valido → 200
  - Unsubscribe senza device_token → 400
"""
import pytest
from unittest.mock import patch
from hypothesis import given, settings
from hypothesis import strategies as st

from app import app as flask_app


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    flask_app.config["TESTING"] = True
    flask_app.config["WTF_CSRF_ENABLED"] = False
    # Disabilita il redirect HTTPS per i test
    flask_app.config["SESSION_COOKIE_SECURE"] = False
    with flask_app.test_client() as c:
        yield c


def _authenticate(client):
    """Inietta una sessione autenticata nel test client Flask."""
    with client.session_transaction() as sess:
        sess["_user_id"] = "testuser"
        sess["_fresh"] = True
    return client


# ---------------------------------------------------------------------------
# Proprietà 14 — Feature: ios-native-app, Property 14: Validazione payload subscribe APNs
# ---------------------------------------------------------------------------

# Strategia: dizionari con chiavi testo che escludono "device_token"
_keys_without_device_token = st.text(
    alphabet=st.characters(blacklist_categories=("Cs",)),
    min_size=1,
    max_size=30,
).filter(lambda k: k != "device_token")

_payload_without_token = st.dictionaries(
    keys=_keys_without_device_token,
    values=st.one_of(st.text(), st.integers(), st.booleans(), st.none()),
    max_size=5,
)


@given(payload=_payload_without_token)
@settings(max_examples=100)
def test_apns_subscribe_missing_token_returns_400(payload):
    """
    Proprietà 14: Validazione payload subscribe APNs — HTTP 400 senza device_token.

    Per qualsiasi payload JSON che non contenga il campo device_token,
    POST /push/apns/subscribe deve restituire HTTP 400.

    **Valida: Requisiti 10.3**
    """
    flask_app.config["TESTING"] = True
    flask_app.config["WTF_CSRF_ENABLED"] = False
    flask_app.config["SESSION_COOKIE_SECURE"] = False

    with flask_app.test_client() as c:
        _authenticate(c)
        with patch("apns_utils.add_apns_subscription"), \
             patch("apns_utils.remove_apns_subscription"):
            response = c.post(
                "/push/apns/subscribe",
                json=payload,
                content_type="application/json",
            )

    assert response.status_code == 400, (
        f"Atteso HTTP 400 per payload senza device_token, "
        f"ricevuto {response.status_code}. Payload: {payload}"
    )


# ---------------------------------------------------------------------------
# Test unitari — task 3.3
# ---------------------------------------------------------------------------

VALID_TOKEN = "a" * 64  # 64 caratteri hex-like, valido per i test


def test_apns_subscribe_valid_payload(client):
    """Subscribe con payload valido → 201."""
    _authenticate(client)
    with patch("app.add_apns_subscription") as mock_add:
        response = client.post(
            "/push/apns/subscribe",
            json={"device_token": VALID_TOKEN, "device_id": "550e8400-e29b-41d4-a716-446655440000"},
            content_type="application/json",
        )

    assert response.status_code == 201
    data = response.get_json()
    assert data["ok"] is True
    mock_add.assert_called_once_with(
        VALID_TOKEN,
        "550e8400-e29b-41d4-a716-446655440000",
        "production",
    )


def test_apns_subscribe_unauthenticated(client):
    """Subscribe senza sessione autenticata → 401 o redirect a /login."""
    with patch("apns_utils.add_apns_subscription"):
        response = client.post(
            "/push/apns/subscribe",
            json={"device_token": VALID_TOKEN},
            content_type="application/json",
        )

    # flask_login può restituire 401 oppure redirect 302 verso /login
    assert response.status_code in (401, 302), (
        f"Atteso 401 o 302 per richiesta non autenticata, ricevuto {response.status_code}"
    )
    if response.status_code == 302:
        assert "/login" in response.headers.get("Location", "")


def test_apns_unsubscribe_valid(client):
    """Unsubscribe con token valido → 200."""
    _authenticate(client)
    with patch("app.remove_apns_subscription") as mock_remove:
        response = client.post(
            "/push/apns/unsubscribe",
            json={"device_token": VALID_TOKEN},
            content_type="application/json",
        )

    assert response.status_code == 200
    data = response.get_json()
    assert data["ok"] is True
    mock_remove.assert_called_once_with(VALID_TOKEN)


def test_apns_unsubscribe_missing_token(client):
    """Unsubscribe senza device_token → 400."""
    _authenticate(client)
    with patch("apns_utils.remove_apns_subscription"):
        response = client.post(
            "/push/apns/unsubscribe",
            json={},
            content_type="application/json",
        )

    assert response.status_code == 400
    data = response.get_json()
    assert data["ok"] is False
