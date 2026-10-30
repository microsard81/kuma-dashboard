# auth.py — Autenticazione multi-utente con Redis

import os
import re
import json
import hashlib
import logging
import secrets
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

import pyotp
import redis
from werkzeug.security import check_password_hash, generate_password_hash

import config
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
# Username ed email
# ----------------------------------------------------------------------

USERNAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")

_EMAIL_RE = re.compile(
    r"^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\.[A-Za-z]{2,63}$"
)
_EMAIL_MAX_LEN = 254


def is_valid_username(s) -> bool:
    """True se s è uno username nel formato ammesso (lettere, cifre, . _ -, max 64)."""
    return isinstance(s, str) and USERNAME_RE.fullmatch(s) is not None


def validate_email(s) -> str:
    """Valida un indirizzo email e lo restituisce normalizzato (strip + minuscolo)."""
    if not isinstance(s, str):
        raise ValueError("Formato email non valido.")
    value = s.strip()
    if len(value) > _EMAIL_MAX_LEN or _EMAIL_RE.fullmatch(value) is None:
        raise ValueError("Formato email non valido.")
    return value.lower()


def set_user_email(username: str, email: str) -> None:
    """Salva l'email (validata) dell'utente. KeyError se l'utente non esiste."""
    normalized = validate_email(email)
    key = _user_key(username)
    if not _r.exists(key):
        raise KeyError(username)
    _r.hset(key, "email", normalized)


def get_user_email(username: str) -> str | None:
    """Restituisce l'email salvata dell'utente, oppure None."""
    value = _r.hget(_user_key(username), "email")
    return value or None


def get_session_epoch(username: str) -> int | None:
    """
    Epoch di sessione dell'utente: None se l'utente non esiste, 0 se mai
    impostato. ValueError se il valore salvato non è un intero.
    """
    password_hash, epoch = _r.hmget(_user_key(username), ["password_hash", "session_epoch"])
    if not password_hash:
        return None
    if epoch is None:
        return 0
    return int(epoch)


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


def _build_password_history(username: str, new_hash: str) -> str:
    """Restituisce lo storico password (JSON) con new_hash in coda, max 5 entry."""
    key = _user_key(username)
    history_json = _r.hget(key, "password_history")
    try:
        history = json.loads(history_json) if history_json else []
    except (json.JSONDecodeError, TypeError):
        history = []
    if not isinstance(history, list):
        history = []
    history.append(new_hash)
    # Mantieni solo le ultime 5
    history = history[-_PASSWORD_HISTORY_MAX:]
    return json.dumps(history)


PASSWORD_MAX_LEN = 128


def validate_new_password(username: str, new_password: str, check_history: bool = True) -> None:
    """Lunghezza + complessità + storico. Solleva PasswordValidationError."""
    if len(new_password) > PASSWORD_MAX_LEN:
        raise PasswordValidationError("La password non può superare 128 caratteri.")
    validate_password_complexity(new_password)
    if check_history and check_password_history(username, new_password):
        raise PasswordValidationError("La password è già stata usata di recente. Scegline una diversa.")


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
    validate_new_password(username, new_password, check_history=not skip_history_check)

    key = _user_key(username)
    new_hash = generate_password_hash(new_password)
    _r.hset(key, mapping={
        "password_hash": new_hash,
        "must_change_password": "0",
        "password_history": _build_password_history(username, new_hash),
    })


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
    keys = _r.scan_iter(match=f"{_USER_PREFIX}*", count=100)
    return sorted({k.removeprefix(_USER_PREFIX) for k in keys})


# ----------------------------------------------------------------------
# Token di reset password
# ----------------------------------------------------------------------
# In Redis si salva solo lo SHA-256 del token: il token in chiaro esiste
# solo in memoria, nell'email e nella form. Mai salvato né loggato.

RESET_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{43}$")
_RESET_PREFIX = "pwreset:"
_RESET_USER_PREFIX = "pwreset_user:"
_MAX_TX_RETRIES = 3


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def _reset_key(token_hash: str) -> str:
    return f"{_RESET_PREFIX}{token_hash}"


def _reset_user_key(username: str) -> str:
    return f"{_RESET_USER_PREFIX}{username}"


def _is_valid_token_format(token) -> bool:
    return isinstance(token, str) and RESET_TOKEN_RE.fullmatch(token) is not None


def create_password_reset_token(username: str) -> tuple[str, str] | None:
    """
    Crea un token di reset per l'utente e invalida l'eventuale precedente.
    Restituisce (token, email) oppure None (utente assente o senza email
    valida), senza scrivere nulla in quel caso.
    """
    if not is_valid_username(username):
        return None
    stored_hash, stored_email = _r.hmget(_user_key(username), ["password_hash", "email"])
    if not stored_hash or not stored_email:
        return None
    try:
        email = validate_email(stored_email)
    except ValueError:
        return None

    ttl = int(config.PASSWORD_RESET_TOKEN_TTL_MINUTES) * 60
    token = secrets.token_urlsafe(32)
    new_hash = _token_hash(token)
    pointer = _reset_user_key(username)

    for _ in range(_MAX_TX_RETRIES):
        with _r.pipeline() as pipe:
            try:
                pipe.watch(pointer)
                old_hash = pipe.get(pointer)
                pipe.multi()
                if old_hash:
                    pipe.delete(_reset_key(old_hash))
                pipe.set(_reset_key(new_hash), username, ex=ttl)
                pipe.set(pointer, new_hash, ex=ttl)
                pipe.execute()
                return token, email
            except redis.WatchError:
                continue
    raise redis.RedisError("create_password_reset_token: troppi conflitti concorrenti")


def peek_reset_token(token) -> str | None:
    """Restituisce lo username associato a un token valido, senza consumarlo."""
    if not _is_valid_token_format(token):
        return None
    token_hash = _token_hash(token)
    username = _r.get(_reset_key(token_hash))
    if not username:
        return None
    if _r.get(_reset_user_key(username)) != token_hash:
        return None
    if not _r.exists(_user_key(username)):
        return None
    return username


def consume_reset_token(token) -> str | None:
    """
    Consuma il token (monouso, GETDEL atomico) e restituisce lo username,
    oppure None se il token non è valido o è già stato usato.
    """
    if not _is_valid_token_format(token):
        return None
    token_hash = _token_hash(token)
    username = _r.getdel(_reset_key(token_hash))
    if not username:
        return None

    # Rimuove il puntatore solo se punta ancora a questo token
    pointer = _reset_user_key(username)
    for _ in range(_MAX_TX_RETRIES):
        with _r.pipeline() as pipe:
            try:
                pipe.watch(pointer)
                if pipe.get(pointer) != token_hash:
                    pipe.unwatch()
                    break
                pipe.multi()
                pipe.delete(pointer)
                pipe.execute()
                break
            except redis.WatchError:
                continue
    return username


def delete_password_reset_for_user(username: str) -> None:
    """Cancella l'eventuale token di reset attivo dell'utente."""
    pointer = _reset_user_key(username)
    token_hash = _r.get(pointer)
    if token_hash:
        _r.delete(_reset_key(token_hash), pointer)
    else:
        _r.delete(pointer)


def revoke_biometric_tokens(username: str) -> int:
    """Cancella tutti i token biometrici dell'utente. Best effort: ritorna il numero cancellato."""
    deleted = 0
    try:
        for key in _r.scan_iter(match=f"biometric:{username}:*", count=100):
            deleted += _r.delete(key)
    except redis.RedisError as e:
        logger.error("revoke_biometric_tokens: Redis non disponibile (%s)", type(e).__name__)
    return deleted


def complete_password_reset(username: str, new_password: str) -> int:
    """
    Completa il reset: nuova password, 2FA reimpostato (nuovo secret, da
    riconfigurare), must_change_password=0, session_epoch+1 (revoca tutte le
    sessioni). Restituisce il nuovo epoch. KeyError se l'utente non esiste.
    """
    validate_new_password(username, new_password)

    key = _user_key(username)
    new_hash = generate_password_hash(new_password)
    new_epoch = None
    for _ in range(_MAX_TX_RETRIES):
        with _r.pipeline() as pipe:
            try:
                pipe.watch(key)
                if not pipe.exists(key):
                    pipe.unwatch()
                    raise KeyError(username)
                history = _build_password_history(username, new_hash)
                pipe.multi()
                pipe.hset(key, mapping={
                    "password_hash": new_hash,
                    "must_change_password": "0",
                    "totp_secret": pyotp.random_base32(),
                    "totp_enrolled": "0",
                    "password_history": history,
                })
                pipe.hincrby(key, "session_epoch", 1)
                results = pipe.execute()
                new_epoch = int(results[-1])
                break
            except redis.WatchError:
                continue
    if new_epoch is None:
        raise redis.RedisError("complete_password_reset: troppi conflitti concorrenti")

    # Fuori dalla transazione, best effort: i token restano comunque
    # inutilizzabili perché legati all'epoch
    revoke_biometric_tokens(username)
    return new_epoch
