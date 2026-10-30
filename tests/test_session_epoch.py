"""
Test della revoca sessioni (id Flask-Login "username:epoch"), del flusso pending
e dei token biometrici legati all'epoch. Tutto su FakeRedis: nessun accesso al
Redis di produzione.
"""
import secrets
from unittest.mock import patch

import fakeredis
import pyotp
import pytest
import redis
from werkzeug.security import generate_password_hash

import app as app_module
import auth
import rate_limit
from app import app as flask_app

PASSWORD = "Abcdef1!"


@pytest.fixture
def r(monkeypatch):
    """FakeRedis condiviso da auth, rate_limit e app."""
    fake = fakeredis.FakeRedis(server=fakeredis.FakeServer(), decode_responses=True)
    monkeypatch.setattr(auth, "_r", fake)
    monkeypatch.setattr(rate_limit, "_r", fake)
    monkeypatch.setattr(app_module, "_redis", fake)
    return fake


@pytest.fixture
def client(r):
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as c:
        # Richieste https://localhost (FlaskClient 3.1 non accetta base_url)
        c.environ_base["wsgi.url_scheme"] = "https"
        yield c


def make_user(r, username="mario", epoch=None, enrolled="1", must_change="0"):
    secret = pyotp.random_base32()
    mapping = {
        "password_hash": generate_password_hash(PASSWORD),
        "totp_secret": secret,
        "totp_enrolled": enrolled,
        "must_change_password": must_change,
    }
    if epoch is not None:
        mapping["session_epoch"] = str(epoch)
    r.hset(f"user:{username}", mapping=mapping)
    return secret


def set_session(client, **values):
    with client.session_transaction() as sess:
        sess.update(values)


def get_session(client):
    with client.session_transaction() as sess:
        return dict(sess)


# ---------------------------------------------------------------------------
# load_user
# ---------------------------------------------------------------------------

def test_load_user_legacy_with_epoch_zero(r):
    make_user(r)
    user = app_module.load_user("mario")
    assert user is not None
    assert user.id == "mario"
    assert user.get_id() == "mario:0"


def test_load_user_legacy_rejected_after_reset(r):
    make_user(r, epoch=1)
    assert app_module.load_user("mario") is None


def test_load_user_epoch_match_and_mismatch(r):
    make_user(r, epoch=1)
    user = app_module.load_user("mario:1")
    assert user is not None and user.id == "mario" and user.get_id() == "mario:1"
    assert app_module.load_user("mario:0") is None


def test_load_user_removed_user(r):
    assert app_module.load_user("mario:0") is None
    assert app_module.load_user("mario") is None


def test_redis_error_gives_503_json_not_redirect(client, r):
    make_user(r)
    set_session(client, _user_id="mario:0", _fresh=True)
    with patch("app.get_session_epoch", side_effect=redis.RedisError("down")):
        resp = client.get("/api/dashboard-data")
    assert resp.status_code == 503
    assert resp.get_json() == {"ok": False, "error": "service unavailable"}


def test_redis_error_gives_503_text_on_web(client, r):
    make_user(r)
    set_session(client, _user_id="mario:0", _fresh=True)
    with patch("app.get_session_epoch", side_effect=redis.RedisError("down")):
        resp = client.get("/")
    assert resp.status_code == 503
    assert resp.mimetype == "text/plain"
    assert "Servizio temporaneamente non disponibile" in resp.get_data(as_text=True)


def test_revoked_session_redirects_to_login(client, r):
    make_user(r, epoch=1)
    set_session(client, _user_id="mario:0", _fresh=True)
    resp = client.get("/api/dashboard-data")
    assert resp.status_code == 302
    assert "/login" in resp.headers["Location"]


# ---------------------------------------------------------------------------
# Flusso pending
# ---------------------------------------------------------------------------

def test_pending_session_before_reset_rejected_on_totp_setup(client, r):
    make_user(r, epoch=1, enrolled="0")
    set_session(client, pending_user="mario", pending_epoch=0, totp_setup_pending=True)
    resp = client.get("/totp-setup")
    assert resp.status_code == 302
    assert "/login" in resp.headers["Location"]
    sess = get_session(client)
    assert "pending_user" not in sess
    assert "totp_setup_pending" not in sess


def test_2fa_without_flag_keeps_pending_state(client, r):
    make_user(r, enrolled="0")
    set_session(client, pending_user="mario", pending_epoch=0, totp_setup_pending=True)
    resp = client.get("/2fa")
    assert resp.status_code == 302
    assert "/login" in resp.headers["Location"]
    sess = get_session(client)
    assert sess.get("pending_user") == "mario"
    assert sess.get("totp_setup_pending") is True


def test_stale_2fa_flag_cleared_by_login(client, r):
    """2fa_pending stantio + login di un utente con must_change_password=1 -> /2fa rifiutato."""
    make_user(r, username="other")
    secret = make_user(r, must_change="1")
    set_session(client, pending_user="other", pending_epoch=0, **{"2fa_pending": True})

    resp = client.post("/login", data={"username": "mario", "password": PASSWORD})
    assert resp.status_code == 302
    assert "/change-password" in resp.headers["Location"]

    resp = client.post("/2fa", data={"code": pyotp.TOTP(secret).now()})
    assert resp.status_code == 302
    assert "/login" in resp.headers["Location"]


def test_2fa_wrong_code_shows_error(client, r):
    make_user(r)
    set_session(client, pending_user="mario", pending_epoch=0, **{"2fa_pending": True})
    resp = client.post("/2fa", data={"code": "000000"})
    assert resp.status_code == 200
    assert "Codice 2FA non valido." in resp.get_data(as_text=True)


def test_2fa_rate_limited_on_sixth_attempt(client, r):
    make_user(r)
    set_session(client, pending_user="mario", pending_epoch=0, **{"2fa_pending": True})
    for _ in range(5):
        assert client.post("/2fa", data={"code": "000000"}).status_code == 200
    resp = client.post("/2fa", data={"code": "000000"})
    assert resp.status_code == 429
    assert "Troppi tentativi" in resp.get_data(as_text=True)
    assert int(resp.headers["Retry-After"]) >= 1


def test_2fa_success_logs_in_with_epoch(client, r):
    secret = make_user(r, epoch=2)
    set_session(client, pending_user="mario", pending_epoch=2, **{"2fa_pending": True})
    resp = client.post("/2fa", data={"code": pyotp.TOTP(secret).now()})
    assert resp.status_code == 302
    assert resp.headers["Location"].endswith("/")
    sess = get_session(client)
    assert sess["_user_id"] == "mario:2"
    assert "pending_user" not in sess


def test_login_wrong_credentials_shows_error(client, r):
    make_user(r)
    resp = client.post("/login", data={"username": "mario", "password": "Sbagliata1!"})
    assert resp.status_code == 200
    assert "Credenziali non valide." in resp.get_data(as_text=True)


def test_api_2fa_issues_epoch_bound_biometric_token(client, r):
    secret = make_user(r, epoch=3)
    resp = client.post("/api/login", json={"username": "mario", "password": PASSWORD})
    assert resp.get_json()["next"] == "2fa"
    resp = client.post("/api/2fa", json={"code": pyotp.TOTP(secret).now()})
    assert resp.status_code == 200
    raw = resp.get_json()["biometric_token"].rsplit(".", 1)[0]
    assert r.get(f"biometric:mario:{raw}") == "e3"


# ---------------------------------------------------------------------------
# Token biometrici legati all'epoch
# ---------------------------------------------------------------------------

def _bio_token(r, username, value):
    raw = secrets.token_urlsafe(32)
    r.setex(f"biometric:{username}:{raw}", 3600, value)
    return raw, f"{raw}.{app_module._sign_biometric_token(raw)}"


def test_biometric_legacy_value_rejected_after_reset(client, r):
    make_user(r, epoch=1)
    raw, token = _bio_token(r, "mario", "1")
    resp = client.post("/auth/biometric/login", json={"username": "mario", "biometric_token": token})
    assert resp.status_code == 401
    assert resp.get_json()["error"] == "expired"
    assert not r.exists(f"biometric:mario:{raw}")


def test_biometric_epoch_value_accepted(client, r):
    make_user(r, epoch=1)
    _, token = _bio_token(r, "mario", "e1")
    resp = client.post("/auth/biometric/login", json={"username": "mario", "biometric_token": token})
    assert resp.status_code == 200
    assert resp.get_json() == {"ok": True}
    assert get_session(client)["_user_id"] == "mario:1"


def test_biometric_legacy_value_accepted_with_epoch_zero(client, r):
    make_user(r)
    _, token = _bio_token(r, "mario", "1")
    resp = client.post("/auth/biometric/login", json={"username": "mario", "biometric_token": token})
    assert resp.status_code == 200


def test_biometric_redis_error_gives_503(client, r):
    make_user(r)
    _, token = _bio_token(r, "mario", "e0")
    with patch("app.get_session_epoch", side_effect=redis.RedisError("down")):
        resp = client.post("/auth/biometric/login", json={"username": "mario", "biometric_token": token})
    assert resp.status_code == 503
    assert resp.get_json() == {"ok": False, "error": "service unavailable"}


# ---------------------------------------------------------------------------
# Header di sicurezza globali
# ---------------------------------------------------------------------------

def test_global_security_headers(client, r):
    resp = client.get("/login")
    assert resp.headers["X-Content-Type-Options"] == "nosniff"
    assert resp.headers["X-Frame-Options"] == "DENY"
    assert resp.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"
    assert resp.headers["Strict-Transport-Security"] == "max-age=31536000"
    assert "Content-Security-Policy" not in resp.headers
