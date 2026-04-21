#!/usr/bin/env python3
"""
Script di test manuale per le notifiche push con soglia.

Invia 6 notifiche push in sequenza:
1. 1 sonda DOWN  (max_down_probes=1) — ricevuta da subscription con threshold <= 1
2. 2 sonde DOWN  (max_down_probes=2) — ricevuta da subscription con threshold <= 2
3. 3 sonde DOWN  (max_down_probes=3) — ricevuta da subscription con threshold <= 3
4. 4 sonde DOWN  (max_down_probes=4) — ricevuta da subscription con threshold <= 4
5. 5 sonde DOWN  (max_down_probes=5) — ricevuta da TUTTE le subscription
6. Tutto UP       (max_down_probes=None) — ricevuta da TUTTE le subscription

Tra ogni invio c'è una pausa di 10 secondi.

Uso: python3 test_push_threshold_manual.py
"""

import time
import logging

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s - %(message)s"
)

from push_utils import send_push_to_all
from apns_utils import send_apns_to_all

PAUSE = 10  # secondi tra ogni notifica

STEPS = [
    {
        "title": "🟡 Test soglia — 1 sonda DOWN",
        "body": "Test: 1 sonda DOWN su una risorsa (Aruba)",
        "data": {"state": "YELLOW"},
        "max_down_probes": 1,
    },
    {
        "title": "🟡 Test soglia — 2 sonde DOWN",
        "body": "Test: 2 sonde DOWN su una risorsa (Aruba, TIM)",
        "data": {"state": "YELLOW"},
        "max_down_probes": 2,
    },
    {
        "title": "🟡 Test soglia — 3 sonde DOWN",
        "body": "Test: 3 sonde DOWN su una risorsa (Aruba, TIM, ILIAD)",
        "data": {"state": "YELLOW"},
        "max_down_probes": 3,
    },
    {
        "title": "🟡 Test soglia — 4 sonde DOWN",
        "body": "Test: 4 sonde DOWN su una risorsa (Aruba, TIM, ILIAD, NodePing)",
        "data": {"state": "YELLOW"},
        "max_down_probes": 4,
    },
    {
        "title": "🔴 Test soglia — 5 sonde DOWN",
        "body": "Test: TUTTE le sonde DOWN su una risorsa",
        "data": {"state": "RED"},
        "max_down_probes": 5,
    },
    {
        "title": "🟢 Tutto OK — Test completato",
        "body": "Tutte le risorse risultano UP su tutte le sonde.",
        "data": {"state": "GREEN"},
        "max_down_probes": 5,  # usa lo stesso max dell'ultimo DOWN, come fa il worker
    },
]


def main():
    for i, step in enumerate(STEPS, 1):
        mdp = step["max_down_probes"]
        mdp_str = str(mdp) if mdp is not None else "None (bypass)"
        logging.info(
            "=== Step %d/%d: %s (max_down_probes=%s) ===",
            i, len(STEPS), step["title"], mdp_str,
        )

        send_push_to_all(
            title=step["title"],
            body=step["body"],
            data=step["data"],
            max_down_probes=step["max_down_probes"],
        )

        try:
            send_apns_to_all(
                title=step["title"],
                body=step["body"],
                data=step["data"],
                max_down_probes=step["max_down_probes"],
            )
        except Exception as e:
            logging.error("Errore APNs: %s", e)

        if i < len(STEPS):
            logging.info("Pausa %d secondi...", PAUSE)
            time.sleep(PAUSE)

    logging.info("=== Test completato ===")


if __name__ == "__main__":
    main()
