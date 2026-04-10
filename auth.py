# auth.py — Autenticazione multi-utente con Redis

import os
import re
import json
import logging
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

import pyotp
import redis
from werkzeug.security import check_password_hash, generate_password_hash

from config import REDIS_HOST, REDIS_PORT, REDIS_DB

logger = logging.getLogger(__name__)

_r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)

# Prefisso Redis per gli utenti
_USER_PREFIX = "user:"
# Numero massimo di password precedenti da conservare
_PASSWORD_HISTORY_MAX = 5


def _user_key(username: str) -> str:
    return f"{_USER_PREFIX}{username}"


# ----------------------------------------------------------------------
# Validazione complessità password
# ----------------------------------------------------------------------

class PasswordValidationError(Exception):
    """Errore di validazione password con messaggio leggibile."""
    pass


def validate_password_complexity(password: str) -> None:
    """
    Verifica che la password rispetti i requisiti di complessità.
    Lancia PasswordValidationError se non li rispetta.

    Requisiti:
    - Almeno 8 caratteri
    - Almeno una lettera maiuscola
    - Almeno una lettera minuscola
    - Almeno un numero
    - Almeno un carattere speciale (!@#$%^&*()_+-=[]{}|;:,.<>?)
    """
    if len(password) < 8:
        raise PasswordValidationError("La password deve avere almeno 8 caratteri.")
    if not re.search(r"[A-Z]", password):
        raise PasswordValidationError("La password deve contenere almeno una lettera maiuscola.")
    if not re.search(r"[a-z]", password):
        raise PasswordValidationError("La password deve contenere almeno una lettera minuscola.")
    if not re.search(r"\d", password):
        raise PasswordValidationError("La password deve contenere almeno un numero.")
    if not re.search(r"[!@#$%^&*()\-_+=\[\]{}|;:,.<>?/\\~`]", password):
        raise PasswordValidationError("La password deve contenere almeno un carattere speciale.")


def check_password_history(username: str, new_password: str) -> bool:
    """
    Verifica che la nuova password non sia tra le ultime 5 usate.
    Restituisce True se la password è già stata usata, False altrimenti.
    """
    key = _user_key(username)
    history_json = _r.hget(key, "password_history")
    if not history_json:
        return False
    try:
        history = json.loads(history_json)
    except (json.JSONDecodeError, TypeError):
        return False
    return any(check_password_hash(h, new_password) for h in history)


def _push_password_history(username: str, password_hash: str) -> None:
    """Aggiunge un hash allo storico password, mantenendo max 5 entry."""
    key = _user_key(username)
    history_json = _r.hget(key, "password_history")
    try:
        history = json.loads(history_json) if history_json else []
    except (json.JSONDecodeError, TypeError):
        history = []
    history.append(password_hash)
    # Mantieni solo le ultime 5
    history = history[-_PASSWORD_HISTORY_MAX:]
    _r.hset(key, "password_history", json.dumps(history))


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
        "totp_enrolled": "1",
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


def is_totp_enrolled(username: str) -> bool:
    """Verifica se l'utente ha completato l'enrollment TOTP."""
    key = _user_key(username)
    return _r.hget(key, "totp_enrolled") == "1"


def must_change_password(username: str) -> bool:
    """Verifica se l'utente deve cambiare la password al prossimo login."""
    key = _user_key(username)
    return _r.hget(key, "must_change_password") == "1"


def change_password(username: str, new_password: str, skip_history_check: bool = False):
    """
    Aggiorna la password dell'utente e rimuove il flag di cambio obbligatorio.
    Valida la complessità e verifica che non sia tra le ultime 5 usate.
    skip_history_check=True bypassa il controllo storico (usato da manage_users.py reset-password).
    Lancia PasswordValidationError se la password non è valida.
    """
    validate_password_complexity(new_password)

    if not skip_history_check and check_password_history(username, new_password):
        raise PasswordValidationError("La password è già stata usata di recente. Scegline una diversa.")

    key = _user_key(username)
    new_hash = generate_password_hash(new_password)
    _r.hset(key, mapping={
        "password_hash": new_hash,
        "must_change_password": "0",
    })
    _push_password_history(username, new_hash)


def get_totp_secret(username: str) -> str | None:
    """Restituisce il TOTP secret dell'utente."""
    key = _user_key(username)
    return _r.hget(key, "totp_secret")


def enroll_totp(username: str, code: str) -> bool:
    """
    Verifica il codice TOTP e, se corretto, segna l'utente come enrolled.
    Restituisce True se l'enrollment è riuscito.
    """
    key = _user_key(username)
    totp_secret = _r.hget(key, "totp_secret")
    if not totp_secret:
        return False
    totp = pyotp.TOTP(totp_secret)
    if totp.verify(code):
        _r.hset(key, "totp_enrolled", "1")
        return True
    return False


def list_users() -> list[str]:
    """Restituisce la lista degli username registrati."""
    keys = _r.keys(f"{_USER_PREFIX}*")
    return sorted(k.removeprefix(_USER_PREFIX) for k in keys)
