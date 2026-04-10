import json
import logging
import time
from datetime import datetime, timezone
from typing import Any

import jwt
import httpx
import redis

from config import (
    REDIS_HOST, REDIS_PORT, REDIS_DB,
    APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID,
)
import os

# Usa il server sandbox per app installate via Xcode (development)
# Imposta APNS_SANDBOX=true nel .env per lo sviluppo
APNS_SANDBOX = os.environ.get("APNS_SANDBOX", "false").lower() == "true"
APNS_HOST = "api.sandbox.push.apple.com" if APNS_SANDBOX else "api.push.apple.com"

logger = logging.getLogger(__name__)

_redis = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    db=REDIS_DB,
    decode_responses=True,
)

# Namespace separato da push:subs_by_endpoint (VAPID)
APNS_SUBS_HASH_KEY = "apns:subs_by_token"


def add_apns_subscription(device_token: str, device_id: str, environment: str = "production") -> None:
    """Registra un device token APNs in Redis.

    Usa HSET con chiave apns:subs_by_token per mantenere il namespace
    separato dal namespace VAPID (push:).
    environment: 'sandbox' per app Xcode/debug, 'production' per TestFlight/AppStore
    """
    if not device_token or not device_id:
        logger.warning("add_apns_subscription: device_token o device_id mancante, ignorato")
        return

    record: dict[str, Any] = {
        "device_token": device_token,
        "device_id": device_id,
        "environment": environment,
        "registered_at": datetime.now(timezone.utc).isoformat(),
    }
    _redis.hset(APNS_SUBS_HASH_KEY, device_token, json.dumps(record))
    logger.info("APNs subscription aggiunta (%s): %s...", environment, device_token[:16])


def remove_apns_subscription(device_token: str) -> None:
    """Rimuove un device token APNs da Redis tramite HDEL."""
    if not device_token:
        logger.warning("remove_apns_subscription: device_token mancante, ignorato")
        return

    _redis.hdel(APNS_SUBS_HASH_KEY, device_token)
    logger.info("APNs subscription rimossa: %s...", device_token[:16])


def load_apns_subscriptions() -> list[dict]:
    """Carica tutte le subscription APNs da Redis tramite HVALS."""
    vals = _redis.hvals(APNS_SUBS_HASH_KEY)
    return [json.loads(v) for v in vals]


def _generate_apns_jwt() -> str:
    """Genera un JWT APNs firmato con ES256 valido 60 minuti."""
    with open(APNS_KEY_PATH, "r") as f:
        private_key = f.read()

    now = int(time.time())
    token = jwt.encode(
        payload={"iss": APNS_TEAM_ID, "iat": now},
        key=private_key,
        algorithm="ES256",
        headers={"alg": "ES256", "kid": APNS_KEY_ID},
    )
    return token


def send_apns_to_all(title: str, body: str, data: dict) -> None:
    """Invia una notifica APNs a tutti i device token registrati in Redis.

    - Genera un JWT APNs con ES256 (scadenza 60 min)
    - Invia richieste HTTP/2 ad APNs tramite httpx
    - Rimuove automaticamente i token non validi (410 / BadDeviceToken)
    - Se APNS_KEY_PATH non è configurato, logga WARNING e ritorna
    """
    if APNS_KEY_PATH is None:
        logger.warning("APNS_KEY_PATH non configurato — invio APNs saltato")
        return

    subscriptions = load_apns_subscriptions()
    if not subscriptions:
        logger.info("Nessuna subscription APNs registrata.")
        return

    try:
        apns_jwt = _generate_apns_jwt()
    except Exception as exc:
        logger.error("Errore nella generazione del JWT APNs: %s", exc)
        return

    payload = json.dumps({
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": {
                "critical": 1,
                "name": "default",
                "volume": 1.0
            },
            "badge": 1,
        },
        "state": data.get("state", "") if data else "",
    })

    headers = {
        "authorization": f"bearer {apns_jwt}",
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "content-type": "application/json",
    }

    invalid_tokens: list[str] = []

    try:
        with httpx.Client(http2=True) as client:
            for sub in subscriptions:
                device_token = sub.get("device_token", "")
                if not device_token:
                    continue

                # Determina l'host: prova prima quello salvato, poi l'altro come fallback
                env = sub.get("environment", "production")
                primary_host = "api.sandbox.push.apple.com" if env == "sandbox" else "api.push.apple.com"
                fallback_host = "api.push.apple.com" if env == "sandbox" else "api.sandbox.push.apple.com"

                try:
                    url = f"https://{primary_host}/3/device/{device_token}"
                    response = client.post(url, content=payload, headers=headers)

                    # Se l'ambiente è sbagliato, riprova con l'altro
                    if response.status_code == 403 and "BadEnvironmentKeyInToken" in response.text:
                        logger.info("Ambiente errato per %s..., riprovo con %s", device_token[:16], fallback_host)
                        url = f"https://{fallback_host}/3/device/{device_token}"
                        response = client.post(url, content=payload, headers=headers)
                        # Aggiorna l'ambiente salvato in Redis per le prossime volte
                        correct_env = "production" if fallback_host == "api.push.apple.com" else "sandbox"
                        sub["environment"] = correct_env
                        _redis.hset(APNS_SUBS_HASH_KEY, device_token, json.dumps(sub))
                        logger.info("Ambiente aggiornato a '%s' per token %s...", correct_env, device_token[:16])

                    if response.status_code in (400, 410) or "BadDeviceToken" in response.text:
                        logger.warning(
                            "Token APNs non valido (status=%s, body=%s): %s...",
                            response.status_code,
                            response.text,
                            device_token[:16],
                        )
                        invalid_tokens.append(device_token)
                    elif response.status_code != 200:
                        logger.error(
                            "APNs errore (status=%s, body=%s) per token %s...",
                            response.status_code,
                            response.text,
                            device_token[:16],
                        )
                    else:
                        logger.info(
                            "APNs inviato a %s... (status=%s)",
                            device_token[:16],
                            response.status_code,
                        )

                except httpx.ConnectError as exc:
                    logger.error(
                        "Errore di connessione APNs per token %s...: %s",
                        device_token[:16],
                        exc,
                    )
                except Exception as exc:
                    logger.error(
                        "Errore APNs per token %s...: %s",
                        device_token[:16],
                        exc,
                    )

    except Exception as exc:
        logger.error("Errore nella creazione del client httpx APNs: %s", exc)

    for token in invalid_tokens:
        remove_apns_subscription(token)
