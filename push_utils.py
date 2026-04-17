import json
import logging
from typing import List, Dict, Any

import redis
from pywebpush import webpush, WebPushException

from config import (
    PUSH_ENABLED,
    PUSH_VAPID_PRIVATE_KEY,
    PUSH_VAPID_CLAIMS,
    PUSH_LOG_FILE,
    REDIS_HOST,
    REDIS_PORT,
    REDIS_DB,
)

logger = logging.getLogger(__name__)

# Logger dedicato per il log delle push inviate
_push_logger = logging.getLogger("push_log")
_push_logger.propagate = False
if PUSH_LOG_FILE:
    _push_handler = logging.FileHandler(PUSH_LOG_FILE, encoding="utf-8")
    _push_handler.setFormatter(logging.Formatter("[%(asctime)s] %(message)s"))
    _push_logger.addHandler(_push_handler)
    _push_logger.setLevel(logging.INFO)

_redis = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    db=REDIS_DB,
    decode_responses=True,
)

SUBS_HASH_KEY = "push:subs_by_endpoint"


# ----------------------------------------------------------------------
#  CARICA / AGGIUNGI / RIMUOVI SUBSCRIPTIONS (Redis Hash)
# ----------------------------------------------------------------------

def load_subscriptions() -> List[Dict[str, Any]]:
    """Carica tutte le subscription da Redis."""
    vals = _redis.hvals(SUBS_HASH_KEY)
    return [json.loads(v) for v in vals]


def add_subscription(sub: Dict[str, Any]) -> None:
    """Aggiunge una subscription se l'endpoint non è già presente."""
    if not sub or "endpoint" not in sub:
        logger.warning("Subscription ignorata (endpoint mancante)")
        return

    endpoint = sub["endpoint"]
    if _redis.hexists(SUBS_HASH_KEY, endpoint):
        logger.info("Subscription già presente: %s", endpoint[:50])
        return

    logger.info("Aggiunta subscription: %s...", endpoint[:50])
    _redis.hset(SUBS_HASH_KEY, endpoint, json.dumps(sub))


def remove_subscription(endpoint: str) -> None:
    """Rimuove la subscription con l'endpoint specificato."""
    _redis.hdel(SUBS_HASH_KEY, endpoint)


# ----------------------------------------------------------------------
#  VAPID CLAIMS adattati automaticamente (Apple / Google)
# ----------------------------------------------------------------------

def _build_vapid_claims(endpoint: str) -> Dict[str, Any]:
    """Crea i vapid_claims corretti per Apple, Chrome, Firefox, Android (FCM)."""
    claims = dict(PUSH_VAPID_CLAIMS or {})

    if "fcm.googleapis.com" in endpoint:
        claims["aud"] = "https://fcm.googleapis.com"

    if "web.push.apple.com" in endpoint:
        claims.pop("aud", None)

    return claims


# ----------------------------------------------------------------------
#  BUILD PAYLOAD cross-browser (Apple richiede "aps")
# ----------------------------------------------------------------------

def _build_payload(title: str, body: str, data: Dict[str, Any]) -> str:
    """Genera un payload compatibile sia Apple WebPush sia altri browser."""
    payload = {
        "title": title,
        "body": body,
        "data": data or {},
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
        },
    }
    return json.dumps(payload)


# ----------------------------------------------------------------------
#  INVIO PUSH
# ----------------------------------------------------------------------

def send_push_to_all(title: str, body: str, data: Dict[str, Any] | None = None) -> None:
    """Invia una push a TUTTE le subscription valide."""
    if not PUSH_ENABLED:
        logger.info("PUSH disabilitate in config")
        return

    subs = load_subscriptions()
    if not subs:
        logger.info("Nessuna subscription salvata.")
        return

    payload = _build_payload(title, body, data or {})
    dead_endpoints: List[str] = []

    for sub in subs:
        endpoint = sub.get("endpoint", "")
        if not endpoint:
            continue

        if "permanently-removed.invalid" in endpoint:
            logger.warning("Rimossa subscription Edge Android finta.")
            dead_endpoints.append(endpoint)
            continue

        vapid_claims = _build_vapid_claims(endpoint)
        logger.info("Invio push → %s...", endpoint[:70])

        try:
            webpush(
                subscription_info=sub,
                data=payload,
                vapid_private_key=PUSH_VAPID_PRIVATE_KEY,
                vapid_claims=vapid_claims,
            )
            logger.info("   OK")
            if PUSH_LOG_FILE:
                _push_logger.info("VAPID OK → %s... | title=%s", endpoint[:50], title)

        except WebPushException as e:
            status = getattr(e.response, "status_code", None)
            logger.error("   Errore WebPush: %s (status=%s)", e, status)
            if PUSH_LOG_FILE:
                _push_logger.info("VAPID FAIL → %s... | status=%s | title=%s", endpoint[:50], status, title)
            if status in (404, 410):
                dead_endpoints.append(endpoint)

        except Exception as e:
            logger.error("   Errore generico: %s", e)

    # Pulizia subscription morte
    for ep in dead_endpoints:
        remove_subscription(ep)
    if dead_endpoints:
        logger.info("Rimosse %d subscription invalide.", len(dead_endpoints))
