#!/usr/bin/env python3
import json
from pywebpush import webpush, WebPushException
from push_utils import load_subscriptions, save_subscriptions
from config import PUSH_VAPID_PRIVATE_KEY, PUSH_VAPID_PUBLIC_KEY, PUSH_VAPID_CLAIMS

# --------------------------------------------------------------
# Helper: genera vapid_claims corretti per ogni endpoint Chrome
# --------------------------------------------------------------
def build_claims(endpoint: str):
    claims = dict(PUSH_VAPID_CLAIMS or {})

    # Chrome Android / Desktop → FCM
    if "fcm.googleapis.com" in endpoint:
        claims["aud"] = "https://fcm.googleapis.com"

    # Apple WebPush → NO aud
    if "web.push.apple.com" in endpoint:
        claims.pop("aud", None)

    return claims


# --------------------------------------------------------------
# Main
# --------------------------------------------------------------
def main():
    subs = load_subscriptions()
    if not subs:
        print("❌ Nessuna subscription trovata.")
        return

    print(f"📬 Trovate {len(subs)} subscription\n")

    payload = {
        "title": "TEST PUSH",
        "body": "Questa è una notifica di test dalla dashboard.",
        "data": {"test": True},
    }

    dead = []

    for sub in subs:
        endpoint = sub.get("endpoint")
        if not endpoint:
            continue

        print(f"\n----------------------------------------")
        print(f"Invio a:\n{endpoint}")
        print("----------------------------------------")

        try:
            claims = build_claims(endpoint)

            print("VAPID CLAIMS:", claims)
            print("Payload:", payload)

            webpush(
                subscription_info=sub,
                data=json.dumps(payload),
                vapid_private_key=PUSH_VAPID_PRIVATE_KEY,
                vapid_claims=claims,
            )

            print("✅ OK – notifica inviata!")

        except WebPushException as e:
            print("❌ Errore WebPush:", repr(e))

            if getattr(e, "response", None) is not None:
                print("→ HTTP", e.response.status_code, e.response.text)

                if e.response.status_code in (404, 410):
                    print("⚠ La subscription è morta → la elimino.")
                    dead.append(sub)

        except Exception as e:
            print("❌ Errore generico:", repr(e))

    # Pulizia subscription non valide
    if dead:
        print(f"\n🗑 Rimuovo {len(dead)} subscription morte.")
        save_subscriptions([s for s in subs if s not in dead])


if __name__ == "__main__":
    main()
