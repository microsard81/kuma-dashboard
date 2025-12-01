import json
import os
from typing import List, Dict, Any

from pywebpush import webpush, WebPushException

from config import (
    PUSH_ENABLED,
    PUSH_VAPID_PRIVATE_KEY,
    PUSH_VAPID_CLAIMS,
)

SUBS_FILE = "push_subscriptions.json"


# ----------------------------------------------------------------------
#  CARICA / SALVA SUBSCRIPTIONS (file JSON)
# ----------------------------------------------------------------------

def load_subscriptions() -> List[Dict[str, Any]]:
    """Carica le subscription dal file JSON."""
    if not os.path.exists(SUBS_FILE):
        return []
    try:
        with open(SUBS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return []


def save_subscriptions(subs: List[Dict[str, Any]]) -> None:
    """Salva le subscription nel file JSON."""
    with open(SUBS_FILE, "w", encoding="utf-8") as f:
        json.dump(subs, f)


# ----------------------------------------------------------------------
#  AGGIUNTA o RIMOZIONE SUBSCRIPTION — evita duplicati
# ----------------------------------------------------------------------

def add_subscription(sub: Dict[str, Any]) -> None:
    """
    Aggiunge una subscription se non presente.
    Use case:
    - Safari iOS → endpoint unico per ogni device
    - Chrome/Firefox → endpoint diverso per ogni sessione
    """
    if not sub or "endpoint" not in sub:
        print("❌ Subscription ignorata (endpoint mancante)")
        return

    subs = load_subscriptions()
    endpoints = {s.get("endpoint") for s in subs}

    if sub["endpoint"] in endpoints:
        print(f"ℹ Subscription già presente: {sub['endpoint'][:50]}")
        return

    print(f"➕ Aggiunta subscription: {sub['endpoint'][:50]}...")
    subs.append(sub)
    save_subscriptions(subs)


def remove_subscription(endpoint: str) -> None:
    subs = load_subscriptions()
    new_subs = [s for s in subs if s.get("endpoint") != endpoint]
    save_subscriptions(new_subs)


# ----------------------------------------------------------------------
#  VAPID CLAIMS adattati automaticamente (Apple / Google)
# ----------------------------------------------------------------------

def _build_vapid_claims(endpoint: str) -> Dict[str, Any]:
    """
    Crea i vapid_claims corretti per Apple, Chrome, Firefox, Android (FCM).
    """
    claims = dict(PUSH_VAPID_CLAIMS or {})

    # Android / Chrome mobile → FCM
    if "fcm.googleapis.com" in endpoint:
        claims["aud"] = "https://fcm.googleapis.com"

    # Apple WebPush → NON vuole "aud"
    if "web.push.apple.com" in endpoint:
        if "aud" in claims:
            claims.pop("aud", None)

    return claims


# ----------------------------------------------------------------------
#  BUILD PAYLOAD cross-browser (Apple richiede "aps")
# ----------------------------------------------------------------------

def _build_payload(title: str, body: str, data: Dict[str, Any]) -> str:
    """
    Genera un payload compatibile sia Apple WebPush sia altri browser.
    Safari richiede obbligatoriamente la chiave 'aps'.
    """
    payload = {
        "title": title,
        "body": body,
        "data": data or {},
        # Per Safari:
        "aps": {
            "alert": {
                "title": title,
                "body": body
            },
            "sound": "default"
        }
    }

    return json.dumps(payload)


# ----------------------------------------------------------------------
#  INVIO PUSH
# ----------------------------------------------------------------------

def send_push_to_all(title: str, body: str, data: Dict[str, Any] | None = None) -> None:
    """
    Invia una push a TUTTE le subscription valide.
    Filtro:
    - Safari iOS
    - Chrome Desktop
    - Firefox
    - Android FCM
    Gestisce:
    - rimozione subscription morte (404/410)
    - endpoint finti Edge Android
    """
    if not PUSH_ENABLED:
        print("🔕 PUSH disabilitate in config.py")
        return

    subs = load_subscriptions()
    if not subs:
        print("ℹ Nessuna subscription salvata.")
        return

    payload = _build_payload(title, body, data or {})

    dead: List[Dict[str, Any]] = []

    for sub in subs:
        endpoint = sub.get("endpoint", "")
        if not endpoint:
            continue

        # Edge Android ha endpoint finti → ignorare
        if "permanently-removed.invalid" in endpoint:
            print("⚠ Rimossa subscription Edge Android finta.")
            dead.append(sub)
            continue

        vapid_claims = _build_vapid_claims(endpoint)

        print(f"📤 Invio push → {endpoint[:70]}...")

        try:
            webpush(
                subscription_info=sub,
                data=payload,
                vapid_private_key=PUSH_VAPID_PRIVATE_KEY,
                vapid_claims=vapid_claims,
            )
            print("   ✓ OK")

        except WebPushException as e:
            status = getattr(e.response, "status_code", None)
            print(f"   ✗ Errore WebPush: {e} (status={status})")

            # subscription non valida → rimuovere
            if status in (404, 410):
                dead.append(sub)

        except Exception as e:
            print(f"   ✗ Errore generico: {e}")

    # Pulizia subscription morte
    if dead:
        alive = [s for s in subs if s not in dead]
        save_subscriptions(alive)
        print(f"🧹 Rimosse {len(dead)} subscription invalide.")