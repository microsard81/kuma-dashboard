# ------------------------------------------------------------
# SENSOR CLIENT – Fetch dati inverter da invadcstatus endpoint
# ------------------------------------------------------------

import logging

import requests

from config import INVERTER_STATUS_URL, STATUS_TOKEN, HTTP_TIMEOUT

logger = logging.getLogger(__name__)


def _empty_response(error_msg):
    """Ritorna struttura di risposta vuota con messaggio di errore."""
    return {
        "sensors": [],
        "history": {},
        "timestamp": None,
        "error": error_msg,
    }


def fetch_inverter_data():
    """
    POST a INVERTER_STATUS_URL con STATUS_TOKEN.

    Returns:
        dict con chiavi: sensors, history, timestamp, error
        - error è None in caso di successo
        - error è una stringa descrittiva in caso di fallimento
    """
    try:
        resp = requests.post(
            INVERTER_STATUS_URL,
            json={"token": STATUS_TOKEN},
            timeout=HTTP_TIMEOUT,
        )
    except requests.exceptions.Timeout:
        logger.warning("Timeout connessione a invadcstatus")
        return _empty_response("Timeout connessione a invadcstatus")
    except requests.exceptions.ConnectionError as exc:
        logger.warning("Errore di connessione a invadcstatus: %s", exc)
        return _empty_response(f"Errore di connessione: {exc}")
    except requests.exceptions.RequestException as exc:
        logger.warning("Errore richiesta invadcstatus: %s", exc)
        return _empty_response(f"Errore di connessione: {exc}")

    if resp.status_code != 200:
        logger.warning("Errore HTTP %d da invadcstatus", resp.status_code)
        return _empty_response(f"Errore HTTP {resp.status_code}")

    try:
        data = resp.json()
    except (ValueError, requests.exceptions.JSONDecodeError):
        logger.warning("Risposta non valida (JSON) da invadcstatus")
        return _empty_response("Risposta non valida dal server")

    # Se l'endpoint segnala un errore nel campo "error"
    if data.get("error") is not None:
        error_msg = str(data["error"])
        logger.info("Endpoint invadcstatus ha restituito errore: %s", error_msg)
        return _empty_response(error_msg)

    return {
        "sensors": data.get("sensors", []),
        "history": data.get("history", {}),
        "timestamp": data.get("timestamp"),
        "error": None,
    }
