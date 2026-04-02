# status_client.py

import logging

import requests
from requests.exceptions import Timeout, ConnectionError, HTTPError

from config import STATUS_URL, STATUS_TOKEN, PROBE_BG, PROBE_TIM, PROBE_ILIAD, PROBE_NODEPING
from redis_history import load_history
from severity import compute_severity

logger = logging.getLogger(__name__)


def load_status():
    try:
        r = requests.post(
            STATUS_URL,
            headers={"Authorization": f"Bearer {STATUS_TOKEN}"},
            timeout=8,
        )
        r.raise_for_status()
        return r.json() or {}
    except Timeout:
        logger.error("Timeout contattando %s", STATUS_URL)
        return {}
    except ConnectionError:
        logger.error("Errore di connessione verso %s", STATUS_URL)
        return {}
    except HTTPError as e:
        logger.error("Errore HTTP %s da %s", e.response.status_code, STATUS_URL)
        return {}


def process_monitor(monitor_name, status_dict, name_norm):
    history = load_history(name_norm)

    if not status_dict:
        return {
            "bg": 1,
            "tim": 1,
            "iliad": 1,
            "nodeping": 1,
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
            "nodeping": 1,
            "final": 1,
            "severity": 0,
            "history": history,
        }

    probes = info.get("probes", [])

    bg_state  = 0 if PROBE_BG  in probes else 1
    tim_state = 0 if PROBE_TIM in probes else 1
    iliad_state = 0 if PROBE_ILIAD in probes else 1
    nodeping_state = 0 if PROBE_NODEPING in probes else 1

    final_state = 0 if (bg_state == 0 and tim_state == 0 and iliad_state == 0 and nodeping_state == 0) else 1

    severity = compute_severity(bg_state, tim_state, iliad_state, nodeping_state)

    return {
        "bg": bg_state,
        "tim": tim_state,
        "iliad": iliad_state,
        "nodeping": nodeping_state,
        "final": final_state,
        "severity": severity,
        "history": history,
    }
