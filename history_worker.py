#!/usr/bin/env python3

import time
import logging
from config import STATUS_URL, STATUS_TOKEN, KUMA1, KUMA2
from kuma_client import load_monitors
from status_client import load_status
from redis_history import save_point

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s - %(message)s"
)

PROBE_BG  = "Bergamo Aruba"
PROBE_TIM = "Sestu TIM"


def compute_severity(bg, tim):
    if bg == 1 and tim == 1:
        return 0
    if bg != tim:
        return 1
    return 2


def loop_once():
    statuses = load_status()

    m1 = load_monitors(KUMA1["host"], KUMA1["slug"])
    m2 = load_monitors(KUMA2["host"], KUMA2["slug"])

    common = sorted(set(m1.keys()) & set(m2.keys()))

    # Caso: nessun dato → tutto UP
    if not statuses:
        logging.info("Status vuoto → tutti UP.")

        for name_norm in common:
            save_point(name_norm, 0)
            logging.info(f"[ALL-UP] {m1[name_norm]} → sev=0")

        return

    # Processa ogni monitor
    for name_norm in common:
        display_name = m1[name_norm]

        # Trova eventuale record /status
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

        save_point(name_norm, severity)

        logging.info(f"[OK] {display_name} → sev={severity}")


def main_loop():
    logging.info("=== Kuma History Worker avviato ===")

    while True:
        try:
            loop_once()
        except Exception as e:
            logging.exception(f"Errore worker: {e}")

        time.sleep(10)


if __name__ == "__main__":
    main_loop()