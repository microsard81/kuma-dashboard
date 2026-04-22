#!/usr/bin/env python3
"""
Script di test manuale per le notifiche push con soglia.

Invia 6 notifiche push in sequenza:
1. 1 sonda DOWN  — ricevuta da subscription con threshold <= 1
2. 2 sonde DOWN  — ricevuta da subscription con threshold <= 2
3. 3 sonde DOWN  — ricevuta da subscription con threshold <= 3
4. 4 sonde DOWN  — ricevuta da subscription con threshold <= 4
5. 5 sonde DOWN  — ricevuta da TUTTE le subscription
6. Tutto UP      — ricevuta con lo stesso max dell'ultimo DOWN

Uso:
    python3 test_push_threshold_manual.py                    # tutti i dispositivi
    python3 test_push_threshold_manual.py 5ce1bf64           # solo APNs token che contiene "5ce1bf64"
    python3 test_push_threshold_manual.py fcm.googleapis     # solo VAPID endpoint che contiene "fcm.googleapis"
    python3 test_push_threshold_manual.py apns               # solo tutti i dispositivi APNs
    python3 test_push_threshold_manual.py vapid              # solo tutti i dispositivi VAPID
"""

import json
import sys
import time
import logging

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s - %(message)s"
)

import redis
from pywebpush import webpush, WebPushException

from config import (
    PUSH_ENABLED, PUSH_VAPID_PRIVATE_KEY, PUSH_VAPID_CLAIMS,
    PUSH_LOG_FILE, REDIS_HOST, REDIS_PORT, REDIS_DB,
    APNS_KEY_PATH,
)
from push_utils import (
    load_subscriptions, _build_vapid_claims, _build_payload,
    SUBS_HASH_KEY,
)
from apns_utils import load_apns_subscriptions, send_apns_to_all

PAUSE = 10


def _send_vapid_to_filtered(title, body, data, max_down_probes, filter_str=None):
    """Invia VAPID push, opzionalmente filtrando per endpoint parziale."""
    subs = load_subscriptions()
    if filter_str:
        subs = [s for s in subs if filter_str in s.get("endpoint", "")]

    if not subs:
        logging.info("Nessuna subscription VAPID corrispondente al filtro.")
        return

    payload = _build_payload(title, body, data or {})

    for sub in subs:
        endpoint = sub.get("endpoint", "")
        if not endpoint:
            continue
        threshold = sub.get("threshold", 1)
        if max_down_probes is not None and threshold > max_down_probes:
            continue

        claims = _build_vapid_claims(endpoint)
        try:
            webpush(
                subscription_info=sub,
                data=payload,
                vapid_private_key=PUSH_VAPID_PRIVATE_KEY,
                vapid_claims=claims,
            )
            logging.info("VAPID OK → %s...", endpoint[:50])
        except WebPushException as e:
            logging.error("VAPID FAIL → %s... (%s)", endpoint[:50], e)
        except Exception as e:
            logging.error("VAPID errore → %s... (%s)", endpoint[:50], e)


def _send_apns_to_filtered(title, body, data, max_down_probes, filter_str=None):
    """Invia APNs push, opzionalmente filtrando per token parziale."""
    if filter_str:
        # Invio manuale solo ai token che matchano
        from apns_utils import (
            load_apns_subscriptions, _generate_apns_jwt,
            APNS_SUBS_HASH_KEY, APNS_BUNDLE_ID,
        )
        import httpx

        if APNS_KEY_PATH is None:
            logging.warning("APNS_KEY_PATH non configurato — invio APNs saltato")
            return

        subs = [s for s in load_apns_subscriptions() if filter_str in s.get("device_token", "")]
        if not subs:
            logging.info("Nessuna subscription APNs corrispondente al filtro.")
            return

        try:
            apns_jwt = _generate_apns_jwt()
        except Exception as e:
            logging.error("Errore JWT APNs: %s", e)
            return

        from apns_utils import APNS_BUNDLE_ID as default_bundle
        aps = {
            "alert": {"title": title, "body": body},
            "sound": {"critical": 1, "name": "default", "volume": 1.0},
            "badge": 0 if data.get("state") == "GREEN" else 1,
        }
        payload_str = json.dumps({
            "aps": aps,
            "state": data.get("state", ""),
        })

        with httpx.Client(http2=True) as client:
            for sub in subs:
                threshold = sub.get("threshold", 1)
                if max_down_probes is not None and threshold > max_down_probes:
                    logging.info("APNs SKIP → %s... (soglia=%d > max_down=%s)", sub["device_token"][:16], threshold, max_down_probes)
                    continue

                token = sub["device_token"]
                env = sub.get("environment", "production")
                host = "api.sandbox.push.apple.com" if env in ("sandbox", "development") else "api.push.apple.com"
                headers = {
                    "authorization": f"bearer {apns_jwt}",
                    "apns-topic": sub.get("bundle_id", default_bundle),
                    "apns-push-type": "alert",
                    "content-type": "application/json",
                }
                try:
                    resp = client.post(f"https://{host}/3/device/{token}", content=payload_str, headers=headers)
                    logging.info("APNs %s → %s... (status=%d)", "OK" if resp.status_code == 200 else "FAIL", token[:16], resp.status_code)
                except Exception as e:
                    logging.error("APNs errore → %s... (%s)", token[:16], e)
    else:
        # Invio a tutti tramite la funzione standard
        send_apns_to_all(title, body, data, max_down_probes=max_down_probes)


STEPS = [
    {"title": "🟡 Test soglia — 1 sonda DOWN", "body": "Test: 1 sonda DOWN (Aruba)", "data": {"state": "YELLOW"}, "max_down_probes": 1},
    {"title": "🟡 Test soglia — 2 sonde DOWN", "body": "Test: 2 sonde DOWN (Aruba, TIM)", "data": {"state": "YELLOW"}, "max_down_probes": 2},
    {"title": "🟡 Test soglia — 3 sonde DOWN", "body": "Test: 3 sonde DOWN (Aruba, TIM, ILIAD)", "data": {"state": "YELLOW"}, "max_down_probes": 3},
    {"title": "🟡 Test soglia — 4 sonde DOWN", "body": "Test: 4 sonde DOWN (Aruba, TIM, ILIAD, NodePing)", "data": {"state": "YELLOW"}, "max_down_probes": 4},
    {"title": "🔴 Test soglia — 5 sonde DOWN", "body": "Test: TUTTE le sonde DOWN", "data": {"state": "RED"}, "max_down_probes": 5},
    {"title": "🟢 Tutto OK — Test completato", "body": "Tutte le risorse UP.", "data": {"state": "GREEN"}, "max_down_probes": 5},
]


def main():
    filter_str = sys.argv[1] if len(sys.argv) > 1 else None
    send_vapid = True
    send_apns = True

    if filter_str == "apns":
        send_vapid = False
        filter_str = None
    elif filter_str == "vapid":
        send_apns = False
        filter_str = None

    if filter_str:
        logging.info("Filtro attivo: '%s'", filter_str)

    for i, step in enumerate(STEPS, 1):
        mdp = step["max_down_probes"]
        logging.info("=== Step %d/%d: %s (max_down_probes=%s) ===", i, len(STEPS), step["title"], mdp)

        if send_vapid:
            _send_vapid_to_filtered(step["title"], step["body"], step["data"], mdp, filter_str)

        if send_apns:
            try:
                _send_apns_to_filtered(step["title"], step["body"], step["data"], mdp, filter_str)
            except Exception as e:
                logging.error("Errore APNs: %s", e)

        if i < len(STEPS):
            logging.info("Pausa %d secondi...", PAUSE)
            time.sleep(PAUSE)

    logging.info("=== Test completato ===")


if __name__ == "__main__":
    main()
