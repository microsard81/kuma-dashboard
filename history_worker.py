#!/usr/bin/env python3

import time
import logging
from datetime import datetime

from config import (
    STATUS_URL,
    STATUS_TOKEN,
    KUMA1,
    KUMA2,
    KUMA3,
    NODEPING,
    PUSH_ENABLED,
    PUSH_NOTIFY_ON,
    PROBE_BG,
    PROBE_TIM,
    PROBE_ILIAD,
    PROBE_NODEPING,
    SLEEP,
)
from kuma_client import load_monitors
from status_client import load_status
from redis_history import (
    save_point,
    get_global_state,
    set_global_state,
    get_anomalous_resources,
    set_anomalous_resources,
)
from push_utils import send_push_to_all
from apns_utils import send_apns_to_all
from severity import compute_severity, compute_global_state

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s - %(message)s"
)

# Mappa nomi sonde per le notifiche
PROBE_NAMES = {
    "bg": "Aruba",
    "tim": "TIM",
    "iliad": "ILIAD",
    "nodeping": "NodePing",
}


def _build_detail_body(monitor_details, new_state):
    """
    Costruisce il corpo dettagliato della notifica push.
    monitor_details: lista di dict con chiavi name, bg, tim, iliad, nodeping, severity
    Convenzione: 0 = DOWN, 1 = UP
    """
    now_str = datetime.now().strftime("%H:%M")
    lines = []

    if new_state == "RED":
        # Risorse completamente DOWN (severity 2)
        down_resources = [m for m in monitor_details if m["severity"] == 2]
        mismatch_resources = [m for m in monitor_details if m["severity"] == 1]

        for m in down_resources:
            lines.append(f"{m['name']} — DOWN su tutte le sonde")

        for m in mismatch_resources:
            down_probes = [PROBE_NAMES[k] for k in ("bg", "tim", "iliad", "nodeping") if m[k] == 0]
            if down_probes:
                lines.append(f"⚠ {m['name']} — DOWN su {', '.join(down_probes)}")

    elif new_state == "YELLOW":
        # Solo mismatch
        mismatch_resources = [m for m in monitor_details if m["severity"] == 1]
        for m in mismatch_resources:
            down_probes = [PROBE_NAMES[k] for k in ("bg", "tim", "iliad", "nodeping") if m[k] == 0]
            if down_probes:
                lines.append(f"{m['name']} — DOWN su {', '.join(down_probes)}")

    elif new_state == "GREEN":
        lines.append("Tutte le risorse risultano UP su tutte le sonde.")

    if lines:
        lines.append(f"Ore {now_str}")

    return "\n".join(lines) if lines else None


# ------------------------------------------------------
# Notifiche push basate su transizioni stato globale
# ------------------------------------------------------
def maybe_send_global_push(new_state, monitor_details=None):
    previous = get_global_state()
    set_global_state(new_state)

    details = monitor_details or []
    current_anomalous = {m["name"] for m in details if m["severity"] > 0}

    # Primo avvio → niente notifiche, ma persisti il set anomalo
    if previous is None:
        set_anomalous_resources(current_anomalous)
        return

    # Push disabilitate
    if not PUSH_ENABLED:
        set_anomalous_resources(current_anomalous)
        return

    previous_anomalous = get_anomalous_resources()

    # 🔴 RED – finale DOWN (transizione da non-RED)
    if (
        PUSH_NOTIFY_ON.get("final_down", False)
        and previous != "RED"
        and new_state == "RED"
    ):
        title = "🔴 Servizi DOWN"
        body = _build_detail_body(details, "RED") or "Una o più risorse risultano DOWN."
        data = {"state": "RED"}

        send_push_to_all(title, body, data)
        try:
            send_apns_to_all(title, body, data)
        except Exception:
            logging.exception("Errore nell'invio notifica APNs per stato RED")

    # 🔴 RED → RED – nuove risorse DOWN
    if (
        PUSH_NOTIFY_ON.get("final_down", False)
        and previous == "RED"
        and new_state == "RED"
    ):
        newly_anomalous = current_anomalous - previous_anomalous
        if newly_anomalous:
            new_details = [m for m in details if m["name"] in newly_anomalous]
            title = "🔴 Nuova risorsa DOWN"
            body = _build_detail_body(new_details, "RED") or "Nuove risorse risultano DOWN."
            data = {"state": "RED"}

            send_push_to_all(title, body, data)
            try:
                send_apns_to_all(title, body, data)
            except Exception:
                logging.exception("Errore nell'invio notifica APNs per same-state RED")

    # 🟡 YELLOW – mismatch (transizione da non-YELLOW)
    if (
        PUSH_NOTIFY_ON.get("probe_mismatch", False)
        and previous != "YELLOW"
        and new_state == "YELLOW"
    ):
        title = "🟡 Incongruenza tra sonde"
        body = _build_detail_body(details, "YELLOW") or "Una o più risorse hanno stato diverso tra le sonde."
        data = {"state": "YELLOW"}

        send_push_to_all(title, body, data)
        try:
            send_apns_to_all(title, body, data)
        except Exception:
            logging.exception("Errore nell'invio notifica APNs per stato YELLOW")

    # 🟡 YELLOW → YELLOW – nuove risorse con mismatch
    if (
        PUSH_NOTIFY_ON.get("probe_mismatch", False)
        and previous == "YELLOW"
        and new_state == "YELLOW"
    ):
        newly_anomalous = current_anomalous - previous_anomalous
        if newly_anomalous:
            new_details = [m for m in details if m["name"] in newly_anomalous]
            title = "🟡 Nuova incongruenza"
            body = _build_detail_body(new_details, "YELLOW") or "Nuove risorse con incongruenza tra sonde."
            data = {"state": "YELLOW"}

            send_push_to_all(title, body, data)
            try:
                send_apns_to_all(title, body, data)
            except Exception:
                logging.exception("Errore nell'invio notifica APNs per same-state YELLOW")

    # 🟢 GREEN – ritorno alla normalità
    if (
        PUSH_NOTIFY_ON.get("back_to_green", False)
        and previous in ("RED", "YELLOW")
        and new_state == "GREEN"
    ):
        now_str = datetime.now().strftime("%H:%M")
        title = "🟢 Tutto OK"
        body = f"Tutte le risorse risultano UP su tutte le sonde.\nOre {now_str}"
        data = {"state": "GREEN"}

        send_push_to_all(title, body, data)
        try:
            send_apns_to_all(title, body, data)
        except Exception:
            logging.exception("Errore nell'invio notifica APNs per stato GREEN")

    # Persisti il set anomalo corrente per il prossimo ciclo
    set_anomalous_resources(current_anomalous)


# ------------------------------------------------------
# Ciclo unico del worker
# ------------------------------------------------------
def loop_once():
    statuses = load_status()

    m1 = load_monitors(KUMA1["host"], KUMA1["slug"])
    m2 = load_monitors(KUMA2["host"], KUMA2["slug"])
    m3 = load_monitors(KUMA3["host"], KUMA3["slug"])

    common = sorted(set(m1.keys()) & set(m2.keys()) & set(m3.keys()))
    severities = []
    monitor_details = []

    # Nessun dato → tutto green
    if not statuses:
        logging.info("Status vuoto → tutti UP.")

        for name_norm in common:
            save_point(name_norm, 0, k1=0, k2=0, k3=0, n1=0)
            severities.append(0)
            monitor_details.append({
                "name": m1[name_norm], "bg": 1, "tim": 1, "iliad": 1, "nodeping": 1, "severity": 0
            })
            logging.info(f"[ALL-UP] {m1[name_norm]} → sev=0")

        new_state = compute_global_state(severities)
        maybe_send_global_push(new_state, monitor_details)
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
            iliad = 1
            nodeping = 1
        else:
            probes = info.get("probes", [])
            bg = 0 if PROBE_BG  in probes else 1
            tim = 0 if PROBE_TIM in probes else 1
            iliad = 0 if PROBE_ILIAD in probes else 1
            nodeping = 0 if PROBE_NODEPING in probes else 1

        severity = compute_severity(bg, tim, iliad, nodeping)
        severities.append(severity)
        monitor_details.append({
            "name": display_name,
            "bg": bg,
            "tim": tim,
            "iliad": iliad,
            "nodeping": nodeping,
            "severity": severity,
        })

        save_point(name_norm, severity, k1=bg, k2=tim, k3=iliad, n1=nodeping)
        logging.info(f"[OK] {display_name} → sev={severity}")

    # Calcola stato globale
    new_state = compute_global_state(severities)
    maybe_send_global_push(new_state, monitor_details)


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

        time.sleep(SLEEP)


if __name__ == "__main__":
    main_loop()
