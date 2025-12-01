#!/usr/bin/env python3

import time
import logging

from config import (
    STATUS_URL,
    STATUS_TOKEN,
    KUMA1,
    KUMA2,
    PUSH_ENABLED,
    PUSH_NOTIFY_ON,
)
from kuma_client import load_monitors
from status_client import load_status
from redis_history import save_point, get_global_state, set_global_state
from push_utils import send_push_to_all

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s - %(message)s"
)

PROBE_BG  = "Bergamo Aruba"
PROBE_TIM = "Sestu TIM"


# ------------------------------------------------------
# Calcolo severità (0 verde, 1 giallo, 2 rosso)
# ------------------------------------------------------
def compute_severity(bg, tim):
    if bg == 1 and tim == 1:
        return 0
    if bg != tim:
        return 1
    return 2


# ------------------------------------------------------
# Determina stato globale: GREEN / YELLOW / RED
# ------------------------------------------------------
def compute_global_state(all_rows):
    if any(sev == 2 for sev in all_rows):
        return "RED"
    if any(sev == 1 for sev in all_rows):
        return "YELLOW"
    return "GREEN"


# ------------------------------------------------------
# Notifiche push basate su transizioni stato globale
# ------------------------------------------------------
def maybe_send_global_push(new_state):
    previous = get_global_state()
    set_global_state(new_state)

    # Primo avvio → niente notifiche
    if previous is None:
        return

    # Push disabilitate
    if not PUSH_ENABLED:
        return

    # 🔴 RED – finale DOWN
    if (
        PUSH_NOTIFY_ON.get("final_down", False)
        and previous != "RED"
        and new_state == "RED"
    ):
        send_push_to_all(
            "🔴 Servizi DOWN",
            "Una o più risorse risultano DOWN su entrambe le sonde.",
            {"state": "RED"},
        )

    # 🟡 YELLOW – mismatch
    if (
        PUSH_NOTIFY_ON.get("probe_mismatch", False)
        and previous != "YELLOW"
        and new_state == "YELLOW"
    ):
        send_push_to_all(
            "🟡 Incongruenza tra sonde",
            "Una o più risorse hanno stato diverso tra le sonde.",
            {"state": "YELLOW"},
        )

    # 🟢 GREEN – ritorno alla normalità
    if (
        PUSH_NOTIFY_ON.get("back_to_green", False)
        and previous in ("RED", "YELLOW")
        and new_state == "GREEN"
    ):
        send_push_to_all(
            "🟢 Tutto OK",
            "Tutte le risorse risultano UP su entrambe le sonde.",
            {"state": "GREEN"},
        )


# ------------------------------------------------------
# Ciclo unico del worker
# ------------------------------------------------------
def loop_once():
    statuses = load_status()

    m1 = load_monitors(KUMA1["host"], KUMA1["slug"])
    m2 = load_monitors(KUMA2["host"], KUMA2["slug"])

    common = sorted(set(m1.keys()) & set(m2.keys()))
    severities = []

    # Nessun dato → tutto green
    if not statuses:
        logging.info("Status vuoto → tutti UP.")

        for name_norm in common:
            save_point(name_norm, 0)
            severities.append(0)
            logging.info(f"[ALL-UP] {m1[name_norm]} → sev=0")

        new_state = compute_global_state(severities)
        maybe_send_global_push(new_state)
        return

    # Processa monitor
    for name_norm in common:
        display_name = m1[name_norm]

        info = None
        for url, data in statuses.items():
            if data.get("last_name") == display_name:
                info = data
                break

        if not info:
            bg = 1
            tim = 1
        else:
            probes = info.get("probes", [])
            bg = 0 if PROBE_BG  in probes else 1
            tim = 0 if PROBE_TIM in probes else 1

        severity = compute_severity(bg, tim)
        severities.append(severity)

        save_point(name_norm, severity)
        logging.info(f"[OK] {display_name} → sev={severity}")

    # Calcola stato globale
    new_state = compute_global_state(severities)
    maybe_send_global_push(new_state)


# ------------------------------------------------------
# MAIN LOOP
# ------------------------------------------------------
def main_loop():
    logging.info("=== Kuma History Worker avviato (con Push) ===")

    while True:
        try:
            loop_once()
        except Exception as e:
            logging.exception(f"Errore worker: {e}")

        time.sleep(10)


if __name__ == "__main__":
    main_loop()