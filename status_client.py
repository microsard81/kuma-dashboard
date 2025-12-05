# status_client.py

import requests
from config import STATUS_URL, STATUS_TOKEN, PROBE_BG, PROBE_TIM, PROBE_ILIAD
from redis_history import load_history


def load_status():
    try:
        r = requests.post(
            STATUS_URL,
            headers={"Authorization": f"Bearer {STATUS_TOKEN}"},
            timeout=8,
        )
        r.raise_for_status()
        return r.json() or {}
    except:
        return {}


def process_monitor(monitor_name, status_dict, name_norm):
    history = load_history(name_norm)

    if not status_dict:
        return {
            "bg": 1,
            "tim": 1,
            "iliad": 1,
            "final": 1,
            "severity": 0,
            "history": history,
        }

    info = None
    for url, data in status_dict.items():
        if data.get("last_name") == monitor_name:
            info = data
            break

    if not info:
        return {
            "bg": 1,
            "tim": 1,
            "iliad": 1,
            "final": 1,
            "severity": 0,
            "history": history,
        }

    probes = info.get("probes", [])

    bg_state  = 0 if PROBE_BG  in probes else 1
    tim_state = 0 if PROBE_TIM in probes else 1
    iliad_state = 0 if PROBE_ILIAD in probes else 1

    final_state = 0 if (bg_state == 0 and tim_state == 0 and iliad_state == 0) else 1

    if bg_state == 1 and tim_state == 1 and iliad_state == 1:
        severity = 0
    elif bg_state != tim_state or bg_state != iliad_state or tim_state != iliad_state:
        severity = 1
    else:
        severity = 2

    return {
        "bg": bg_state,
        "tim": tim_state,
        "iliad": iliad_state,
        "final": final_state,
        "severity": severity,
        "history": history,
    }
