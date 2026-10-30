"""
Test delle route di reset password self-service (/forgot-password,
/api/password-reset/request, /reset-password). FakeRedis condiviso da auth,
rate_limit e app; mailer sincrono con invio catturato (nessuna email reale).
"""
import json
import re

import fakeredis
import pyotp
import pytest
from werkzeug.security import generate_password_hash

import app as app_module
import auth
import config
import mailer
import rate_limit
from app import app as flask_app

OLD_PASSWORD = "Vecchia1!"
NEW_PASSWORD = "Nuova123!x"
GENERIC_MSG = "Se l'account esiste ed ha un'email associata, riceverai un link a breve."
TOKEN_IN_LINK = re.compile(r"token=([A-Za-z0-9_-]{43})")


@pytest.fixture
def r(monkeypatch):
    fake = fakeredis.FakeRedis(server=fakeredis.FakeServer(), decode_responses=True)
    monkeypatch.setattr(auth, "_r", fake)
    monkeypatch.setattr(rate_limit, "_r", fake)
    monkeypatch.setattr(app_module, "_redis", fake)
    return fake


@pytest.fixture
def sent(monkeypatch):
    """Email catturate al posto dell'invio SMTP; mailer configurato e sincrono."""
    outbox = []

    def fake_send_email(to, subject, text, html_body, log_ref):
        outbox.append({"to": to, "subject": subject, "text": text, "html": html_body, "ref": log_ref})
        return True

    monkeypatch.setattr(mailer, "submit", lambda fn, *args: fn(*args))
    monkeypatch.setattr(mailer, "send_email", fake_send_email)
    monkeypatch.setattr(config, "SMTP_HOST", "smtp.example.com")
    monkeypatch.setattr(config, "SMTP_PORT", 587)
    monkeypatch.setattr(config, "SMTP_STARTTLS", True)
    monkeypatch.setattr(config, "SMTP_FROM", "noreply@example.com")
    monkeypatch.setattr(config, "PUBLIC_BASE_URL", "https://dash.example.com")
    monkeypatch.setattr(config, "PASSWORD_RESET_TOKEN_TTL_MINUTES", 30)
    monkeypatch.setattr(config, "ADMIN_NOTIFY_EMAIL", "")
    monkeypatch.setattr(app_module, "PUBLIC_BASE_URL", "https://dash.example.com")
    return outbox


@pytest.fixture
def client(r, sent):
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as c:
        # Richieste https://localhost (FlaskClient 3.1 non accetta base_url)
        c.environ_base["wsgi.url_scheme"] = "https"
        yield c


def make_user(r, username="mario", email="mario@example.com"):
    old_hash = generate_password_hash(OLD_PASSWORD)
    mapping = {
        "password_hash": old_hash,
        "totp_secret": pyotp.random_base32(),
        "totp_enrolled": "1",
        "must_change_password": "0",
        "password_history": json.dumps([old_hash]),
    }
    if email:
        mapping["email"] = email
    r.hset(f"user:{username}", mapping=mapping)


def new_token(username="mario"):
    token, _ = auth.create_password_reset_token(username)
    return token


def post_reset(client, token, pw=NEW_PASSWORD, confirm=None):
    return client.post("/reset-password", data={
        "token": token, "new_password": pw, "confirm_password": pw if confirm is None else confirm,
    })


def token_still_valid(client, token):
    return client.get(f"/reset-password?token={token}").status_code == 200


# ---------------------------------------------------------------------------
# Richiesta del link
# ---------------------------------------------------------------------------

def test_api_request_identical_responses(client, r, sent):
    make_user(r, "mario")
    make_user(r, "senzamail", email=None)
    responses = [
        client.post("/api/password-reset/request", json={"username": u})
        for u in ("mario", "senzamail", "inesistente")
    ]
    bodies = {(resp.status_code, resp.get_data()) for resp in responses}
    assert len(bodies) == 1
    assert responses[0].status_code == 200
    assert responses[0].get_json() == {"ok": True, "message": GENERIC_MSG}

    # Una sola email: quella dell'utente con email, con la durata interpolata
    assert len(sent) == 1
    assert sent[0]["to"] == "mario@example.com"
    assert "30 minuti" in sent[0]["text"]
    assert TOKEN_IN_LINK.search(sent[0]["text"])


def test_web_request_identical_responses(client, r, sent):
    make_user(r, "mario")
    make_user(r, "senzamail", email=None)
    responses = [
        client.post("/forgot-password", data={"username": u})
        for u in ("mario", "senzamail", "inesistente")
    ]
    assert {(resp.status_code, resp.get_data()) for resp in responses} == {
        (responses[0].status_code, responses[0].get_data())
    }
    assert responses[0].status_code == 200
    assert "riceverai un link a breve" in responses[0].get_data(as_text=True)
    assert len(sent) == 1


def test_api_request_non_object_body(client):
    resp = client.post("/api/password-reset/request", data="[1]", content_type="application/json")
    assert resp.status_code == 400
    assert resp.get_json() == {"ok": False, "error": "invalid request"}


def test_only_hash_and_pointer_stored(client, r, sent):
    make_user(r)
    client.post("/api/password-reset/request", json={"username": "mario"})
    token = TOKEN_IN_LINK.search(sent[0]["text"]).group(1)
    keys = sorted(k for k in r.scan_iter("pwreset*"))
    assert len(keys) == 2
    assert "pwreset_user:mario" in keys
    for k in keys:
        assert token not in k
        assert token not in r.get(k)
        assert 0 < r.ttl(k) <= 1800


def test_new_request_invalidates_previous(client, r, sent):
    make_user(r)
    client.post("/api/password-reset/request", json={"username": "mario"})
    client.post("/api/password-reset/request", json={"username": "mario"})
    t1, t2 = (TOKEN_IN_LINK.search(m["text"]).group(1) for m in sent)
    assert client.get(f"/reset-password?token={t1}").status_code == 400
    assert client.get(f"/reset-password?token={t2}").status_code == 200


def test_request_rate_limited_on_fourth_for_same_user(client, r, sent):
    for _ in range(3):
        resp = client.post("/api/password-reset/request", json={"username": "inesistente"})
        assert resp.status_code == 200
    resp = client.post("/api/password-reset/request", json={"username": "inesistente"})
    assert resp.status_code == 429
    assert resp.get_json() == {"ok": False, "error": "Troppi tentativi, riprova più tardi"}
    assert int(resp.headers["Retry-After"]) >= 1


# ---------------------------------------------------------------------------
# Pagina di reset
# ---------------------------------------------------------------------------

def test_invalid_or_malformed_token(client, r):
    make_user(r)
    for url in ("/reset-password", "/reset-password?token=abc",
                "/reset-password?token=" + "A" * 43):
        resp = client.get(url)
        assert resp.status_code == 400
        assert "non valido" in resp.get_data(as_text=True)
    resp = post_reset(client, "A" * 43)
    assert resp.status_code == 400
    assert "non valido" in resp.get_data(as_text=True)


def test_rejected_passwords_keep_token_valid(client, r):
    make_user(r)
    token = new_token()
    cases = [
        ("debole", None, "almeno 8 caratteri"),
        (OLD_PASSWORD, None, "già stata usata"),
        ("Aa1!" + "x" * 130, None, "128 caratteri"),
        (NEW_PASSWORD, "Diversa123!", "Le password non corrispondono."),
    ]
    for pw, confirm, message in cases:
        resp = post_reset(client, token, pw, confirm)
        assert resp.status_code == 400
        assert message in resp.get_data(as_text=True)
        assert 'name="token"' in resp.get_data(as_text=True)
    assert token_still_valid(client, token)


def test_successful_reset(client, r, sent):
    make_user(r)
    r.setex("biometric:mario:abc", 3600, "e0")
    old_secret = r.hget("user:mario", "totp_secret")
    token = new_token()

    resp = post_reset(client, token)
    assert resp.status_code == 200
    assert "Password aggiornata" in resp.get_data(as_text=True)

    user = r.hgetall("user:mario")
    assert user["totp_enrolled"] == "0"
    assert user["totp_secret"] != old_secret
    assert user["session_epoch"] == "1"
    assert user["must_change_password"] == "0"
    assert auth.verify_user("mario", NEW_PASSWORD)
    assert list(r.scan_iter("biometric:mario:*")) == []
    assert list(r.scan_iter("pwreset*")) == []

    confirmations = [m for m in sent if m["ref"] == "reset_confirmation"]
    assert len(confirmations) == 1
    assert confirmations[0]["to"] == "mario@example.com"


def test_admin_alert_sent_when_configured(client, r, sent, monkeypatch):
    monkeypatch.setattr(config, "ADMIN_NOTIFY_EMAIL", "admin@example.com")
    make_user(r)
    assert post_reset(client, new_token()).status_code == 200
    alerts = [m for m in sent if m["ref"] == "admin_alert"]
    assert len(alerts) == 1
    assert alerts[0]["to"] == "admin@example.com"
    assert "mario" in alerts[0]["text"]


def test_reset_strips_password_and_login_works(client, r):
    make_user(r)
    padded = " Abcdef1!x "
    assert post_reset(client, new_token(), padded).status_code == 200
    resp = client.post("/api/login", json={"username": "mario", "password": padded})
    assert resp.status_code == 200
    assert resp.get_json()["next"] == "totp_setup"


def test_token_reuse_is_invalid(client, r):
    make_user(r)
    token = new_token()
    assert post_reset(client, token).status_code == 200
    resp = post_reset(client, token, "Altra123!y")
    assert resp.status_code == 400
    assert "non valido" in resp.get_data(as_text=True)


def test_user_removed_between_consume_and_complete(client, r, monkeypatch):
    make_user(r)
    token = new_token()
    real_consume = app_module.consume_reset_token

    def consume_then_remove(t):
        username = real_consume(t)
        r.delete(f"user:{username}")
        return username

    monkeypatch.setattr(app_module, "consume_reset_token", consume_then_remove)
    resp = post_reset(client, token)
    assert resp.status_code == 400
    assert "non valido" in resp.get_data(as_text=True)
    assert not r.exists("user:mario")


def test_reset_rate_limited_on_sixth_post_same_token(client, r):
    make_user(r)
    token = new_token()
    for _ in range(5):
        assert post_reset(client, token, "debole").status_code == 400
    resp = post_reset(client, token)
    body = resp.get_data(as_text=True)
    assert resp.status_code == 429
    assert "Troppi tentativi" in body
    assert 'name="new_password"' in body   # token ben formato -> form
    assert int(resp.headers["Retry-After"]) >= 1
    assert r.hget("user:mario", "session_epoch") is None


def test_reset_rate_limited_malformed_token_is_invalid(client, r):
    for _ in range(5):
        assert post_reset(client, "malformato").status_code == 400
    resp = post_reset(client, "malformato")
    body = resp.get_data(as_text=True)
    assert resp.status_code == 429
    assert "Troppi tentativi" in body
    assert 'name="new_password"' not in body


def test_reset_pages_security_headers(client, r):
    make_user(r)
    for resp in (client.get("/forgot-password"), client.get(f"/reset-password?token={new_token()}"),
                 client.get("/reset-password?token=bad")):
        csp = resp.headers["Content-Security-Policy"]
        assert "default-src 'none'" in csp
        assert "img-src 'self' data:" in csp
        assert "frame-ancestors 'none'" in csp
        assert resp.headers["Cache-Control"] == "no-store"
        assert resp.headers["Referrer-Policy"] == "no-referrer"
        assert resp.headers["X-Frame-Options"] == "DENY"


def test_login_page_links_forgot_password(client):
    body = client.get("/login").get_data(as_text=True)
    assert 'href="/forgot-password"' in body
    assert "Password dimenticata?" in body
