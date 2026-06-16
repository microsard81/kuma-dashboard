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
    PROBE_UPTIME,
    SLEEP,
    INVERTER_TEMP_WARNING,
    INVERTER_TEMP_CRITICAL,
    INVERTER_POWER_WARNING,
    INVERTER_POWER_CRITICAL,
)
from kuma_client import load_monitors
from status_client import load_status
from sensor_client import fetch_inverter_data
from redis_history import (
    save_point,
    get_global_state,
    set_global_state,
    get_anomalous_resources,
    set_anomalous_resources,
    get_last_max_down_probes,
    set_last_max_down_probes,
    clear_last_max_down_probes,
    push_event,
    get_monitor_probes_state,
    set_monitor_probes_state,
)
from push_utils import send_push_to_all
from apns_utils import send_apns_to_all
from severity import compute_severity, compute_global_state, count_down_probes

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
    "uptime": "Uptime",
}


def _compute_max_down_probes(monitor_details: list[dict]) -> int:
    """Calcola il massimo numero di sonde DOWN tra i monitor anomali."""
    max_down = 0
    for m in monitor_details:
        if m["severity"] > 0:
            down = count_down_probes(m["bg"], m["tim"], m["iliad"], m["nodeping"], m["uptime"])
            max_down = max(max_down, down)
    return max_down


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
            down_probes = [PROBE_NAMES[k] for k in ("bg", "tim", "iliad", "nodeping", "uptime") if m[k] == 0]
            if down_probes:
                lines.append(f"⚠ {m['name']} — DOWN su {', '.join(down_probes)}")

    elif new_state == "YELLOW":
        # Solo mismatch
        mismatch_resources = [m for m in monitor_details if m["severity"] == 1]
        for m in mismatch_resources:
            down_probes = [PROBE_NAMES[k] for k in ("bg", "tim", "iliad", "nodeping", "uptime") if m[k] == 0]
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
        push_event("global", "global", "UNKNOWN", new_state, detail="Primo avvio worker")
        return

    # Push disabilitate
    if not PUSH_ENABLED:
        set_anomalous_resources(current_anomalous)
        return

    previous_anomalous = get_anomalous_resources()

    # ⛔ RED – finale DOWN (transizione da non-RED)
    if (
        PUSH_NOTIFY_ON.get("final_down", False)
        and previous != "RED"
        and new_state == "RED"
    ):
        title = "⛔ Servizi DOWN"
        body = _build_detail_body(details, "RED") or "Una o più risorse risultano DOWN."
        data = {"state": "RED"}
        max_down = _compute_max_down_probes(details)
        logging.info("Notifica RED: max_down_probes=%d", max_down)
        send_push_to_all(title, body, data, max_down_probes=max_down)
        try:
            send_apns_to_all(title, body, data, max_down_probes=max_down)
        except Exception:
            logging.exception("Errore nell'invio notifica APNs per stato RED")
        set_last_max_down_probes(max_down)

    # ⛔ RED → RED – nuove risorse DOWN
    if (
        PUSH_NOTIFY_ON.get("final_down", False)
        and previous == "RED"
        and new_state == "RED"
    ):
        newly_anomalous = current_anomalous - previous_anomalous
        if newly_anomalous:
            new_details = [m for m in details if m["name"] in newly_anomalous]
            title = "⛔ Nuova risorsa DOWN"
            body = _build_detail_body(new_details, "RED") or "Nuove risorse risultano DOWN."
            data = {"state": "RED"}
            max_down = _compute_max_down_probes(new_details)

            send_push_to_all(title, body, data, max_down_probes=max_down)
            try:
                send_apns_to_all(title, body, data, max_down_probes=max_down)
            except Exception:
                logging.exception("Errore nell'invio notifica APNs per same-state RED")
            set_last_max_down_probes(max_down)

    # ⚠️ YELLOW – mismatch (transizione da non-YELLOW)
    if (
        PUSH_NOTIFY_ON.get("probe_mismatch", False)
        and previous != "YELLOW"
        and new_state == "YELLOW"
    ):
        title = "⚠️ Incongruenza tra sonde"
        body = _build_detail_body(details, "YELLOW") or "Una o più risorse hanno stato diverso tra le sonde."
        data = {"state": "YELLOW"}
        max_down = _compute_max_down_probes(details)
        logging.info("Notifica YELLOW: max_down_probes=%d", max_down)
        send_push_to_all(title, body, data, max_down_probes=max_down)
        try:
            send_apns_to_all(title, body, data, max_down_probes=max_down)
        except Exception:
            logging.exception("Errore nell'invio notifica APNs per stato YELLOW")
        set_last_max_down_probes(max_down)

    # ⚠️ YELLOW → YELLOW – nuove risorse con mismatch
    if (
        PUSH_NOTIFY_ON.get("probe_mismatch", False)
        and previous == "YELLOW"
        and new_state == "YELLOW"
    ):
        newly_anomalous = current_anomalous - previous_anomalous
        if newly_anomalous:
            new_details = [m for m in details if m["name"] in newly_anomalous]
            title = "⚠️ Nuova incongruenza"
            body = _build_detail_body(new_details, "YELLOW") or "Nuove risorse con incongruenza tra sonde."
            data = {"state": "YELLOW"}
            max_down = _compute_max_down_probes(new_details)

            send_push_to_all(title, body, data, max_down_probes=max_down)
            try:
                send_apns_to_all(title, body, data, max_down_probes=max_down)
            except Exception:
                logging.exception("Errore nell'invio notifica APNs per same-state YELLOW")
            set_last_max_down_probes(max_down)

    # ⚠️⛔ ESCALATION — stesso stato ma più sonde DOWN rispetto all'ultimo invio
    # Permette a chi ha soglia alta di ricevere la notifica quando le sonde
    # peggiorano progressivamente (es. da 2 DOWN a 4 DOWN restando YELLOW)
    if (
        new_state in ("YELLOW", "RED")
        and previous == new_state
    ):
        max_down = _compute_max_down_probes(details)
        last_max_down = get_last_max_down_probes() or 0

        if max_down > last_max_down:
            if new_state == "RED":
                title = "⛔ Peggioramento — più sonde DOWN"
                body = _build_detail_body(details, "RED") or "Più sonde rilevano DOWN."
                data = {"state": "RED"}
            else:
                title = "⚠️ Peggioramento — più sonde DOWN"
                body = _build_detail_body(details, "YELLOW") or "Più sonde rilevano incongruenze."
                data = {"state": "YELLOW"}

            logging.info("Notifica ESCALATION %s: max_down_probes=%d (precedente=%d)", new_state, max_down, last_max_down)
            send_push_to_all(title, body, data, max_down_probes=max_down)
            try:
                send_apns_to_all(title, body, data, max_down_probes=max_down)
            except Exception:
                logging.exception("Errore nell'invio notifica APNs per escalation %s", new_state)
            set_last_max_down_probes(max_down)

        elif max_down < last_max_down and last_max_down > 0:
            # DE-ESCALATION — meno sonde DOWN rispetto all'ultimo invio
            if new_state == "RED":
                title = "⛔ Miglioramento — meno sonde DOWN"
                body = _build_detail_body(details, "RED") or "Alcune sonde si sono riprese."
                data = {"state": "RED"}
            else:
                title = "⚠️ Miglioramento — meno sonde DOWN"
                body = _build_detail_body(details, "YELLOW") or "Alcune sonde si sono riprese."
                data = {"state": "YELLOW"}

            logging.info("Notifica DE-ESCALATION %s: max_down_probes=%d (precedente=%d)", new_state, max_down, last_max_down)
            # Invia a chi aveva ricevuto la notifica precedente (last_max_down)
            send_push_to_all(title, body, data, max_down_probes=last_max_down)
            try:
                send_apns_to_all(title, body, data, max_down_probes=last_max_down)
            except Exception:
                logging.exception("Errore nell'invio notifica APNs per de-escalation %s", new_state)
            set_last_max_down_probes(max_down)

    # ✅ GREEN – ritorno alla normalità
    if (
        PUSH_NOTIFY_ON.get("back_to_green", False)
        and previous in ("RED", "YELLOW")
        and new_state == "GREEN"
    ):
        now_str = datetime.now().strftime("%H:%M")
        title = "✅ Tutto OK"
        body = f"Tutte le risorse risultano UP su tutte le sonde.\nOre {now_str}"
        data = {"state": "GREEN"}

        # Usa lo stesso max_down dell'ultima notifica anomala:
        # chi non ha ricevuto la notifica DOWN non riceve la GREEN.
        # Se last_max_down è None (nessuna notifica anomala salvata), usa 5
        # per raggiungere tutti (retrocompatibilità con subscription senza soglia).
        last_max_down = get_last_max_down_probes()
        if last_max_down is None:
            last_max_down = 5
        logging.info("Notifica GREEN: last_max_down_probes=%s", last_max_down)
        send_push_to_all(title, body, data, max_down_probes=last_max_down)
        try:
            send_apns_to_all(title, body, data, max_down_probes=last_max_down)
        except Exception:
            logging.exception("Errore nell'invio notifica APNs per stato GREEN")
        clear_last_max_down_probes()

    # ✅ Risorse tornate UP durante same-state (YELLOW→YELLOW o RED→RED)
    if (
        PUSH_NOTIFY_ON.get("back_to_green", False)
        and previous == new_state
        and new_state in ("YELLOW", "RED")
    ):
        recovered = previous_anomalous - current_anomalous
        if recovered:
            now_str = datetime.now().strftime("%H:%M")
            names = ", ".join(sorted(recovered))
            title = "✅ Risorsa ripristinata"
            body = f"{names} — tornata UP\nOre {now_str}"
            data = {"state": new_state}

            # Usa lo stesso max_down dell'ultima notifica anomala
            last_max_down = get_last_max_down_probes()
            if last_max_down is None:
                last_max_down = 5
            send_push_to_all(title, body, data, max_down_probes=last_max_down)
            try:
                send_apns_to_all(title, body, data, max_down_probes=last_max_down)
            except Exception:
                logging.exception("Errore nell'invio notifica APNs per risorsa ripristinata")

    # Persisti il set anomalo corrente per il prossimo ciclo
    set_anomalous_resources(current_anomalous)

    # Registra evento di transizione stato globale (indipendente dalle push)
    if new_state != previous:
        detail_lines = []
        if new_state == "RED":
            down_resources = [m["name"] for m in details if m["severity"] == 2]
            if down_resources:
                detail_lines.append(f"DOWN: {', '.join(down_resources)}")
        elif new_state == "YELLOW":
            mismatch_resources = [m["name"] for m in details if m["severity"] == 1]
            if mismatch_resources:
                detail_lines.append(f"Mismatch: {', '.join(mismatch_resources)}")
        sev = 2 if new_state == "RED" else (1 if new_state == "YELLOW" else 0)
        push_event("global", "global", previous, new_state,
                   detail="; ".join(detail_lines), severity=sev)

    # Registra evento di transizione stato globale (per cronologia completa in Redis)
    if new_state != previous:
        detail_lines = []
        if new_state == "RED":
            down_resources = [m["name"] for m in details if m["severity"] == 2]
            if down_resources:
                detail_lines.append(f"DOWN: {', '.join(down_resources)}")
        elif new_state == "YELLOW":
            mismatch_resources = [m["name"] for m in details if m["severity"] == 1]
            if mismatch_resources:
                detail_lines.append(f"Mismatch: {', '.join(mismatch_resources)}")
        sev = 2 if new_state == "RED" else (1 if new_state == "YELLOW" else 0)
        push_event("global", "global", previous, new_state,
                   detail="; ".join(detail_lines), severity=sev)

    # Registra eventi per singoli monitor che hanno cambiato stato
    # Granularità: un evento per ogni monitor E per ogni sonda che cambia stato
    previous_probes = get_monitor_probes_state()
    current_probes: dict[str, set[str]] = {}

    for m in details:
        m_name = m["name"]
        was_anomalous = m_name in previous_anomalous
        is_anomalous = m_name in current_anomalous

        # Calcola sonde DOWN attuali per questo monitor
        current_down = set()
        for probe_key in ("bg", "tim", "iliad", "nodeping", "uptime"):
            if m[probe_key] == 0:
                current_down.add(probe_key)

        if is_anomalous:
            current_probes[m_name] = current_down

        if is_anomalous and not was_anomalous:
            # Monitor appena entrato in stato anomalo: un evento per sonda DOWN
            icon = "⛔" if m["severity"] == 2 else "⚠️"
            for probe_key in current_down:
                probe_name = PROBE_NAMES[probe_key]
                push_event("monitor", f"{icon} {m_name}", "UP", "DOWN" if m["severity"] == 2 else "MISMATCH",
                           detail=f"DOWN su {probe_name}",
                           severity=m["severity"])

        elif was_anomalous and not is_anomalous:
            # Monitor tornato UP: un evento per sonda che era DOWN
            prev_down = previous_probes.get(m_name, set())
            for probe_key in prev_down:
                probe_name = PROBE_NAMES[probe_key]
                push_event("monitor", f"✅ {m_name}", "DOWN", "UP",
                           detail=f"{probe_name} ripristinata", severity=0)
            # Se non conosciamo le sonde precedenti, un evento generico
            if not prev_down:
                push_event("monitor", f"✅ {m_name}", "DOWN", "UP",
                           detail="Ripristinato", severity=0)

        elif is_anomalous and was_anomalous:
            # Monitor resta anomalo — registra cambi di sonde
            prev_down = previous_probes.get(m_name, set())
            newly_down = current_down - prev_down
            newly_up = prev_down - current_down

            icon = "⛔" if m["severity"] == 2 else "⚠️"
            for probe_key in newly_down:
                probe_name = PROBE_NAMES[probe_key]
                push_event("monitor", f"{icon} {m_name}", "UP", "DOWN",
                           detail=f"{probe_name} DOWN",
                           severity=m["severity"])

            for probe_key in newly_up:
                probe_name = PROBE_NAMES[probe_key]
                push_event("monitor", f"✅ {m_name}", "DOWN", "UP",
                           detail=f"{probe_name} ripristinata",
                           severity=0)

    # Salva stato sonde per il prossimo ciclo
    set_monitor_probes_state(current_probes)


# ------------------------------------------------------
# INVERTER SENSOR ALERTS
# ------------------------------------------------------
# Stato precedente dei sensori salvato in Redis: inverter:alert_state:<sensor_name>
# Valori: "normal", "warning", "critical"

def _get_sensor_alert_state(sensor_name):
    """Legge lo stato di alert precedente per un sensore da Redis."""
    from redis_history import r
    return r.get(f"inverter:alert_state:{sensor_name}") or "normal"


def _set_sensor_alert_state(sensor_name, state):
    """Salva lo stato di alert per un sensore in Redis."""
    from redis_history import r
    r.set(f"inverter:alert_state:{sensor_name}", state)


def _classify_sensor(value, category):
    """Classifica il valore di un sensore come normal/warning/critical."""
    if value is None:
        return "normal"
    if category == "temperature":
        if value > INVERTER_TEMP_CRITICAL:
            return "critical"
        if value > INVERTER_TEMP_WARNING:
            return "warning"
    else:  # power
        if value < INVERTER_POWER_CRITICAL:
            return "critical"
        if value < INVERTER_POWER_WARNING:
            return "warning"
    return "normal"


def check_inverter_alerts():
    """Controlla i sensori inverter e invia push alle transizioni di stato."""
    if not PUSH_ENABLED:
        return

    data = fetch_inverter_data()
    if data.get("error"):
        logging.warning("Inverter alert check: %s", data["error"])
        return

    now_str = datetime.now().strftime("%H:%M")
    sensors = data.get("sensors", [])

    for sensor in sensors:
        name = sensor.get("name", "")
        value = sensor.get("value")
        category = sensor.get("category", "temperature")
        unit = sensor.get("unit", "")

        new_state = _classify_sensor(value, category)
        prev_state = _get_sensor_alert_state(name)

        # Invia push solo alle transizioni (non a ogni ciclo)
        if new_state != prev_state:
            _set_sensor_alert_state(name, new_state)

            # Registra evento nel log con icona appropriata
            sev = 2 if new_state == "critical" else (1 if new_state == "warning" else 0)
            detail = f"{value} {unit}" if value is not None else ""

            # Emoji in base allo stato di arrivo
            if new_state == "normal":
                event_name = f"✅ {name}"
            elif new_state == "warning":
                event_name = f"⚠️ {name}"
            elif new_state == "critical":
                event_name = f"🔴 {name}"
            else:
                event_name = name

            push_event("sensor", event_name, prev_state, new_state,
                       detail=detail, severity=sev)

            # Transizione verso warning
            if new_state == "warning" and prev_state == "normal":
                title = f"⚠️ {name}"
                if category == "temperature":
                    body = f"Temperatura {value} {unit} (soglia warning: >{INVERTER_TEMP_WARNING} {unit})\nOre {now_str}"
                else:
                    body = f"Potenza {value} {unit} (soglia warning: <{INVERTER_POWER_WARNING} {unit})\nOre {now_str}"
                _send_inverter_push(title, body)

            # Transizione verso critical
            elif new_state == "critical":
                title = f"⛔ {name}"
                if category == "temperature":
                    body = f"Temperatura {value} {unit} (soglia critical: >{INVERTER_TEMP_CRITICAL} {unit})\nOre {now_str}"
                else:
                    body = f"Potenza {value} {unit} (soglia critical: <{INVERTER_POWER_CRITICAL} {unit})\nOre {now_str}"
                _send_inverter_push(title, body)

            # Ritorno a normal da warning/critical
            elif new_state == "normal" and prev_state in ("warning", "critical"):
                title = f"✅ {name}"
                body = f"Valore rientrato nella norma: {value} {unit}\nOre {now_str}"
                _send_inverter_push(title, body)


def _send_inverter_push(title, body):
    """Invia notifica push inverter a tutti i dispositivi (bypassa soglia sonde)."""
    data = {"type": "inverter_alert"}
    logging.info("Notifica inverter: %s — %s", title, body.replace('\n', ' | '))
    # max_down_probes=None bypassa il filtro soglia: tutti ricevono la notifica
    send_push_to_all(title, body, data, max_down_probes=None)
    try:
        send_apns_to_all(title, body, data, max_down_probes=None)
    except Exception:
        logging.exception("Errore invio APNs per alert inverter")


# ------------------------------------------------------
# Ciclo unico del worker
# ------------------------------------------------------
def loop_once():
    statuses = load_status()

    m2 = load_monitors(KUMA2["host"], KUMA2["slug"])
    # TIM (KUMA2) è la sorgente primaria per la lista monitor.
    # Le altre sonde sono opzionali: se non rispondono, il worker funziona lo stesso.
    m1 = load_monitors(KUMA1["host"], KUMA1["slug"]) or {}
    m3 = load_monitors(KUMA3["host"], KUMA3["slug"]) or {}

    common = sorted(m2.keys())
    severities = []
    monitor_details = []

    # Nessun dato → tutto green
    if not statuses:
        logging.info("Status vuoto → tutti UP.")

        for name_norm in common:
            save_point(name_norm, 0, k1=0, k2=0, k3=0, n1=0, u1=0)
            severities.append(0)
            monitor_details.append({
                "name": m2[name_norm], "bg": 1, "tim": 1, "iliad": 1, "nodeping": 1, "uptime": 1, "severity": 0
            })
            logging.info(f"[ALL-UP] {m2[name_norm]} → sev=0")

        new_state = compute_global_state(severities)
        maybe_send_global_push(new_state, monitor_details)
        check_inverter_alerts()
        return

    # Processa monitor
    for name_norm in common:
        display_name = m2[name_norm]

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
            uptime = 1
        else:
            probes = info.get("probes", [])
            bg = 0 if PROBE_BG  in probes else 1
            tim = 0 if PROBE_TIM in probes else 1
            iliad = 0 if PROBE_ILIAD in probes else 1
            nodeping = 0 if PROBE_NODEPING in probes else 1
            uptime = 0 if PROBE_UPTIME in probes else 1

        severity = compute_severity(bg, tim, iliad, nodeping, uptime)
        severities.append(severity)
        monitor_details.append({
            "name": display_name,
            "bg": bg,
            "tim": tim,
            "iliad": iliad,
            "nodeping": nodeping,
            "uptime": uptime,
            "severity": severity,
        })

        save_point(name_norm, severity, k1=bg, k2=tim, k3=iliad, n1=nodeping, u1=uptime)
        logging.info(f"[OK] {display_name} → sev={severity}")

    # Calcola stato globale
    new_state = compute_global_state(severities)
    maybe_send_global_push(new_state, monitor_details)

    # Check soglie sensori inverter
    check_inverter_alerts()


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
