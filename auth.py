# auth.py — Autenticazione multi-utente con Redis

import os
import logging
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

import pyotp
import redis
from werkzeug.security import check_password_hash

from config import REDIS_HOST, REDIS_PORT, REDIS_DB

logger = logging.getLogger(__name__)

_r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)

# Prefisso Redis per gli utenti
_USER_PREFIX = "user:"


def _user_key(username: str) -> str:
    return f"{_USER_PREFIX}{username}"


def _migrate_legacy_user():
    """
    Migra l'utente singolo dalle variabili d'ambiente legacy (AUTH_PASSWORD_HASH,
    AUTH_TOTP_SECRET) a Redis, se non è già presente. Questo garantisce
    retrocompatibilità con la configurazione precedente.
    """
    legacy_hash = os.environ.get("AUTH_PASSWORD_HASH")
    legacy_totp = os.environ.get("AUTH_TOTP_SECRET")
    legacy_username = os.environ.get("AUTH_LEGACY_USERNAME", "itcarmat")

    if not legacy_hash or not legacy_totp:
        return

    key = _user_key(legacy_username)
    if _r.exists(key):
        return  # Già migrato

    _r.hset(key, mapping={
        "password_hash": legacy_hash,
        "totp_secret": legacy_totp,
    })
    logger.info("Utente legacy '%s' migrato in Redis", legacy_username)


# Esegui migrazione all'import del modulo
_migrate_legacy_user()


def verify_user(username: str, password: str) -> bool:
    """Verifica username e password contro Redis."""
    key = _user_key(username)
    password_hash = _r.hget(key, "password_hash")
    if not password_hash:
        return False
    return check_password_hash(password_hash, password)


def verify_totp(username: str, code: str) -> bool:
    """Verifica il codice TOTP per l'utente specificato."""
    key = _user_key(username)
    totp_secret = _r.hget(key, "totp_secret")
    if not totp_secret:
        return False
    totp = pyotp.TOTP(totp_secret)
    return totp.verify(code)


def get_user(username: str) -> dict | None:
    """Restituisce i dati dell'utente (senza esporre il password_hash nei log)."""
    key = _user_key(username)
    data = _r.hgetall(key)
    return data if data else None


def list_users() -> list[str]:
    """Restituisce la lista degli username registrati."""
    keys = _r.keys(f"{_USER_PREFIX}*")
    return sorted(k.removeprefix(_USER_PREFIX) for k in keys)
