"""Test unitari per le funzioni di auth.py legate a email, epoch e reset password."""
import json

import fakeredis
import pytest
from werkzeug.security import check_password_hash, generate_password_hash

import auth
import config
from auth import PasswordValidationError


OLD_PW = "Vecchia!Pass1"
NEW_PW = "Nuova!Pass2x"


@pytest.fixture
def fr(monkeypatch):
    client = fakeredis.FakeRedis(decode_responses=True)
    monkeypatch.setattr(auth, "_r", client)
    monkeypatch.setattr(config, "PASSWORD_RESET_TOKEN_TTL_MINUTES", 30)
    return client


def _make_user(fr, username="mario", email="mario@example.com", **extra):
    old_hash = generate_password_hash(OLD_PW)
    mapping = {
        "password_hash": old_hash,
        "totp_secret": "JBSWY3DPEHPK3PXP",
        "totp_enrolled": "1",
        "must_change_password": "1",
        "password_history": json.dumps([old_hash]),
    }
    if email is not None:
        mapping["email"] = email
    mapping.update(extra)
    fr.hset(f"user:{username}", mapping=mapping)
    return username


# --- username / email -------------------------------------------------

@pytest.mark.parametrize("value", ["mario", "a.b_c-d", "A1", "x" * 64])
def test_valid_usernames(value):
    assert auth.is_valid_username(value)


@pytest.mark.parametrize("value", ["", "x" * 65, "mario:1", "ma rio", "mario\n", "è", None, "a*"])
def test_invalid_usernames(value):
    assert not auth.is_valid_username(value)


def test_validate_email_normalizes():
    assert auth.validate_email("  Mario.Rossi@Example.COM ") == "mario.rossi@example.com"


@pytest.mark.parametrize("value", [
    "", "senza-chiocciola", "a@b", "a@-b.it", "a@b.c", "a b@c.it",
    "a@b.it\r\nBcc: x@y.it", "x" * 65 + "@example.com",
    "a@" + "b" * 250 + ".it", None,
])
def test_validate_email_rejects(value):
    with pytest.raises(ValueError, match="Formato email non valido."):
        auth.validate_email(value)


def test_set_and_get_user_email(fr):
    _make_user(fr, email=None)
    assert auth.get_user_email("mario") is None
    auth.set_user_email("mario", " Mario@Example.com ")
    assert auth.get_user_email("mario") == "mario@example.com"


def test_set_user_email_unknown_user(fr):
    with pytest.raises(KeyError):
        auth.set_user_email("ghost", "ghost@example.com")
    assert not fr.exists("user:ghost")


def test_set_user_email_invalid(fr):
    _make_user(fr)
    with pytest.raises(ValueError):
        auth.set_user_email("mario", "invalid")


# --- session epoch ----------------------------------------------------

def test_session_epoch(fr):
    assert auth.get_session_epoch("ghost") is None
    _make_user(fr)
    assert auth.get_session_epoch("mario") == 0
    fr.hset("user:mario", "session_epoch", "3")
    assert auth.get_session_epoch("mario") == 3
    fr.hset("user:mario", "session_epoch", "abc")
    with pytest.raises(ValueError):
        auth.get_session_epoch("mario")


# --- token di reset ---------------------------------------------------

def test_create_token_stores_only_hash(fr):
    _make_user(fr)
    token, email = auth.create_password_reset_token("mario")
    assert email == "mario@example.com"
    assert auth.RESET_TOKEN_RE.fullmatch(token)
    keys = set(fr.keys("*"))
    reset_keys = [k for k in keys if k.startswith("pwreset:")]
    assert len(reset_keys) == 1
    assert token not in "".join(keys)
    for k in keys:
        if fr.type(k) == "string":
            assert token not in fr.get(k)
    h = reset_keys[0].removeprefix("pwreset:")
    assert len(h) == 64
    assert fr.get(reset_keys[0]) == "mario"
    assert fr.get("pwreset_user:mario") == h
    for k in (reset_keys[0], "pwreset_user:mario"):
        assert 0 < fr.ttl(k) <= 1800


def test_new_request_invalidates_previous(fr):
    _make_user(fr)
    t1, _ = auth.create_password_reset_token("mario")
    t2, _ = auth.create_password_reset_token("mario")
    assert t1 != t2
    assert auth.peek_reset_token(t1) is None
    assert auth.peek_reset_token(t2) == "mario"
    assert len([k for k in fr.keys("pwreset:*")]) == 1


@pytest.mark.parametrize("email", [None, "", "non-valida"])
def test_create_token_without_valid_email(fr, email):
    _make_user(fr, email=email)
    assert auth.create_password_reset_token("mario") is None
    assert fr.keys("pwreset*") == []


def test_create_token_unknown_user(fr):
    assert auth.create_password_reset_token("ghost") is None
    assert auth.create_password_reset_token("bad:name") is None
    assert fr.keys("pwreset*") == []


def test_peek_does_not_consume(fr):
    _make_user(fr)
    token, _ = auth.create_password_reset_token("mario")
    assert auth.peek_reset_token(token) == "mario"
    assert auth.peek_reset_token(token) == "mario"


@pytest.mark.parametrize("token", ["", "short", "A" * 42, "A" * 44, "A" * 42 + "!", "A" * 43 + "\n", None])
def test_peek_rejects_bad_format(fr, token):
    assert auth.peek_reset_token(token) is None
    assert auth.consume_reset_token(token) is None


def test_peek_user_removed(fr):
    _make_user(fr)
    token, _ = auth.create_password_reset_token("mario")
    fr.delete("user:mario")
    assert auth.peek_reset_token(token) is None


def test_consume_is_single_use(fr):
    _make_user(fr)
    token, _ = auth.create_password_reset_token("mario")
    assert auth.consume_reset_token(token) == "mario"
    assert auth.consume_reset_token(token) is None
    assert auth.peek_reset_token(token) is None
    assert fr.keys("pwreset*") == []


def test_consume_keeps_newer_pointer(fr):
    _make_user(fr)
    token, _ = auth.create_password_reset_token("mario")
    h = fr.get("pwreset_user:mario")
    # simula un puntatore già aggiornato da una richiesta successiva
    fr.set("pwreset_user:mario", "f" * 64)
    assert auth.consume_reset_token(token) == "mario"
    assert fr.get("pwreset_user:mario") == "f" * 64
    assert not fr.exists(f"pwreset:{h}")


def test_delete_password_reset_for_user(fr):
    _make_user(fr)
    token, _ = auth.create_password_reset_token("mario")
    auth.delete_password_reset_for_user("mario")
    assert fr.keys("pwreset*") == []
    assert auth.peek_reset_token(token) is None


# --- completamento reset ----------------------------------------------

def test_complete_password_reset(fr):
    _make_user(fr)
    fr.setex("biometric:mario:abc", 3600, "1")
    fr.setex("biometric:mario:def", 3600, "e0")
    fr.setex("biometric:luigi:xyz", 3600, "1")
    old_secret = fr.hget("user:mario", "totp_secret")

    epoch = auth.complete_password_reset("mario", NEW_PW)

    assert epoch == 1
    data = fr.hgetall("user:mario")
    assert check_password_hash(data["password_hash"], NEW_PW)
    assert data["totp_enrolled"] == "0"
    assert data["totp_secret"] != old_secret
    assert len(data["totp_secret"]) >= 16
    assert data["must_change_password"] == "0"
    assert data["session_epoch"] == "1"
    history = json.loads(data["password_history"])
    assert len(history) == 2
    assert check_password_hash(history[-1], NEW_PW)
    assert fr.keys("biometric:mario:*") == []
    assert fr.exists("biometric:luigi:xyz")
    assert auth.get_session_epoch("mario") == 1

    assert auth.complete_password_reset("mario", "Terza!Pass3") == 2


def test_complete_password_reset_unknown_user(fr):
    with pytest.raises(KeyError):
        auth.complete_password_reset("ghost", NEW_PW)
    assert not fr.exists("user:ghost")


def test_complete_password_reset_validates(fr):
    _make_user(fr)
    with pytest.raises(PasswordValidationError):
        auth.complete_password_reset("mario", OLD_PW)
    assert fr.hget("user:mario", "session_epoch") is None


def test_revoke_biometric_tokens(fr):
    _make_user(fr)
    for i in range(5):
        fr.set(f"biometric:mario:{i}", "1")
    assert auth.revoke_biometric_tokens("mario") == 5
    assert auth.revoke_biometric_tokens("mario") == 0


# --- validate_new_password / change_password --------------------------

def test_validate_new_password_too_long(fr):
    _make_user(fr)
    pw = "Aa1!" + "x" * 125
    assert len(pw) == 129
    with pytest.raises(PasswordValidationError, match="128 caratteri"):
        auth.validate_new_password("mario", pw)
    auth.validate_new_password("mario", pw[:128])


def test_validate_new_password_weak(fr):
    _make_user(fr)
    with pytest.raises(PasswordValidationError, match="almeno 8 caratteri"):
        auth.validate_new_password("mario", "Aa1!")


def test_validate_new_password_history(fr):
    _make_user(fr)
    with pytest.raises(PasswordValidationError, match="già stata usata"):
        auth.validate_new_password("mario", OLD_PW)
    auth.validate_new_password("mario", OLD_PW, check_history=False)


def test_change_password_same_semantics(fr):
    _make_user(fr)
    old_secret = fr.hget("user:mario", "totp_secret")
    with pytest.raises(PasswordValidationError, match="già stata usata"):
        auth.change_password("mario", OLD_PW)
    auth.change_password("mario", NEW_PW)
    data = fr.hgetall("user:mario")
    assert check_password_hash(data["password_hash"], NEW_PW)
    assert data["must_change_password"] == "0"
    assert data["totp_secret"] == old_secret
    assert data["totp_enrolled"] == "1"
    assert "session_epoch" not in data
    assert len(json.loads(data["password_history"])) == 2
    # skip_history_check consente il riuso
    auth.change_password("mario", OLD_PW, skip_history_check=True)
    assert check_password_hash(fr.hget("user:mario", "password_hash"), OLD_PW)


def test_password_history_keeps_last_five(fr):
    _make_user(fr)
    for i in range(7):
        auth.change_password("mario", f"Passw0rd!{i}")
    assert len(json.loads(fr.hget("user:mario", "password_history"))) == 5


def test_list_users_uses_scan(fr):
    _make_user(fr, "zeta")
    _make_user(fr, "alfa")
    assert auth.list_users() == ["alfa", "zeta"]
