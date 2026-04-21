#!/usr/bin/env python3
"""
CLI per gestire e testare le notifiche push (VAPID + APNs).

Uso:
    python manage_push.py list                  # Lista tutte le subscription
    python manage_push.py list vapid            # Solo VAPID (browser/PWA)
    python manage_push.py list apns             # Solo APNs (iOS/Mac)
    python manage_push.py test                  # Invia push di test a tutti
    python manage_push.py test vapid            # Solo VAPID
    python manage_push.py test apns             # Solo APNs
    python manage_push.py remove <endpoint>     # Rimuove una subscription VAPID per endpoint (parziale)
    python manage_push.py remove-apns <token>   # Rimuove una subscription APNs per token (parziale)
"""

import json
import sys
from datetime import datetime

from push_utils import load_subscriptions, send_push_to_all, remove_subscription
from apns_utils import load_apns_subscriptions, send_apns_to_all, remove_apns_subscription


def _classify_endpoint(endpoint: str) -> str:
    """Classifica un endpoint VAPID per tipo di dispositivo."""
    if "fcm.googleapis.com" in endpoint:
        return "Android (FCM)"
    if "web.push.apple.com" in endpoint:
        return "Safari/macOS (Apple)"
    if "mozilla.com" in endpoint or "push.services.mozilla.com" in endpoint:
        return "Firefox"
    if "windows.com" in endpoint or "notify.windows.com" in endpoint:
        return "Edge/Windows"
    return "Sconosciuto"


def cmd_list(filter_type: str = "all"):
    """Lista tutte le subscription registrate."""
    if filter_type in ("all", "vapid"):
        subs = load_subscriptions()
        print(f"\n=== VAPID (Web Push) — {len(subs)} subscription ===\n")
        for i, sub in enumerate(subs, 1):
            endpoint = sub.get("endpoint", "?")
            device_type = _classify_endpoint(endpoint)
            threshold = sub.get("threshold", 1)
            # Mostra i primi 60 caratteri dell'endpoint
            short_ep = endpoint[:60] + "..." if len(endpoint) > 60 else endpoint
            print(f"  {i}. [{device_type}] soglia={threshold}  {short_ep}")

    if filter_type in ("all", "apns"):
        apns_subs = load_apns_subscriptions()
        print(f"\n=== APNs (iOS/Mac) — {len(apns_subs)} subscription ===\n")
        for i, sub in enumerate(apns_subs, 1):
            token = sub.get("device_token", "?")
            env = sub.get("environment", "?")
            device_id = sub.get("device_id", "?")
            bundle_id = sub.get("bundle_id", "—")
            registered = sub.get("registered_at", "?")
            threshold = sub.get("threshold", 1)
            print(f"  {i}. token={token[:16]}...  soglia={threshold}  env={env}  bundle={bundle_id}  device={device_id[:8]}...  registered={registered}")

    print()


def cmd_test(filter_type: str = "all"):
    """Invia una notifica push di test."""
    now_str = datetime.now().strftime("%H:%M:%S")
    title = "🔔 Test Push"
    body = f"Notifica di test inviata alle {now_str}"
    data = {"state": "TEST"}

    if filter_type in ("all", "vapid"):
        print(f"Invio push VAPID di test...")
        send_push_to_all(title, body, data)
        print("VAPID: fatto.\n")

    if filter_type in ("all", "apns"):
        print(f"Invio push APNs di test...")
        try:
            send_apns_to_all(title, body, data)
            print("APNs: fatto.\n")
        except Exception as e:
            print(f"APNs: errore — {e}\n")


def cmd_remove(partial_endpoint: str):
    """Rimuove una subscription VAPID il cui endpoint contiene la stringa data."""
    subs = load_subscriptions()
    removed = 0
    for sub in subs:
        endpoint = sub.get("endpoint", "")
        if partial_endpoint in endpoint:
            remove_subscription(endpoint)
            print(f"Rimossa: {endpoint[:60]}...")
            removed += 1
    if removed == 0:
        print(f"Nessuna subscription VAPID trovata con '{partial_endpoint}'")
    else:
        print(f"\nRimosse {removed} subscription.")


def cmd_remove_apns(partial_token: str):
    """Rimuove una subscription APNs il cui token contiene la stringa data."""
    subs = load_apns_subscriptions()
    removed = 0
    for sub in subs:
        token = sub.get("device_token", "")
        if partial_token in token:
            remove_apns_subscription(token)
            print(f"Rimossa: {token[:16]}...")
            removed += 1
    if removed == 0:
        print(f"Nessuna subscription APNs trovata con '{partial_token}'")
    else:
        print(f"\nRimosse {removed} subscription.")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "list":
        filter_type = sys.argv[2] if len(sys.argv) > 2 else "all"
        cmd_list(filter_type)

    elif cmd == "test":
        filter_type = sys.argv[2] if len(sys.argv) > 2 else "all"
        cmd_test(filter_type)

    elif cmd == "remove":
        if len(sys.argv) < 3:
            print("Uso: python manage_push.py remove <endpoint_parziale>")
            sys.exit(1)
        cmd_remove(sys.argv[2])

    elif cmd == "remove-apns":
        if len(sys.argv) < 3:
            print("Uso: python manage_push.py remove-apns <token_parziale>")
            sys.exit(1)
        cmd_remove_apns(sys.argv[2])

    else:
        print(f"Comando sconosciuto: {cmd}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
