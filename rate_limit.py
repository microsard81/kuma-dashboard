# rate_limit.py — Rate limiting a finestra fissa su Redis
#
# Chiave: rl:{scope}:{kind}:{sha256(identificatore)[:32]}:{finestra}
# Gli identificatori (IP, username, token) non compaiono mai in chiaro in Redis.
# Redis non disponibile -> fail-open (richiesta consentita) con log ERROR.

import hashlib
import logging
import time
from dataclasses import dataclass

import redis

from config import REDIS_HOST, REDIS_PORT, REDIS_DB

logger = logging.getLogger("kuma.security")

_r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)


@dataclass(frozen=True)
class Rule:
    scope: str      # "login", "totp", "bio", "chpw", "pwreq", "pwreset"
    kind: str       # "ip", "user", "token"
    limit: int
    window: int     # secondi


@dataclass(frozen=True)
class Result:
    allowed: bool
    retry_after: int        # secondi alla fine della finestra (0 se allowed)
    rule: Rule | None       # regola che ha bloccato


LOGIN_IP      = Rule("login", "ip", 10, 900)
LOGIN_USER    = Rule("login", "user", 5, 900)
TOTP_USER     = Rule("totp", "user", 5, 900)
BIO_IP        = Rule("bio", "ip", 10, 900)
CHPW_USER     = Rule("chpw", "user", 10, 900)
PWREQ_IP      = Rule("pwreq", "ip", 10, 3600)
PWREQ_USER    = Rule("pwreq", "user", 3, 3600)
PWRESET_IP    = Rule("pwreset", "ip", 10, 900)
PWRESET_TOKEN = Rule("pwreset", "token", 5, 900)

_ALLOWED = Result(allowed=True, retry_after=0, rule=None)


def _key(rule: Rule, identifier: str, now: float) -> str:
    digest = hashlib.sha256(str(identifier).strip().lower().encode("utf-8")).hexdigest()[:32]
    return f"rl:{rule.scope}:{rule.kind}:{digest}:{int(now // rule.window)}"


def hit(rule: Rule, identifier: str) -> Result:
    """Conta un tentativo per (rule, identifier). Blocca quando il conteggio supera il limite."""
    now = time.time()
    key = _key(rule, identifier, now)
    try:
        pipe = _r.pipeline(transaction=True)
        pipe.incr(key)
        pipe.expire(key, rule.window + 5)
        count = int(pipe.execute()[0])
    except redis.RedisError:
        logger.error("rate limit non disponibile")
        return _ALLOWED
    if count > rule.limit:
        retry_after = max(1, rule.window - int(now % rule.window))
        return Result(allowed=False, retry_after=retry_after, rule=rule)
    return _ALLOWED


def check(*pairs: tuple[Rule, str]) -> Result:
    """Applica le regole in ordine; al primo blocco si ferma senza incrementare le successive."""
    for rule, identifier in pairs:
        result = hit(rule, identifier)
        if not result.allowed:
            return result
    return _ALLOWED
