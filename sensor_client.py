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
            headers={"Authorization": f"Bearer {STATUS_TOKEN}"},
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

    # Normalizza i sensori: l'endpoint non fornisce id, category, unit
    # Li deriviamo dal nome del sensore
    raw_sensors = data.get("sensors", [])
    sensors = []
    for s in raw_sensors:
        name = s.get("name", "")
        sensors.append({
            "id": name,  # usiamo il nome come ID (corrisponde alle chiavi history)
            "name": name,
            "category": _guess_category(name),
            "value": s.get("value"),
            "unit": "kW" if _guess_category(name) == "power" else "°C",
            "timestamp": _epoch_to_iso(s.get("timestamp")),
        })

    # Normalizza history: timestamps epoch → ISO
    raw_history = data.get("history", {})
    history = {}
    for key, entries in raw_history.items():
        history[key] = [
            {"t": _epoch_to_iso(e.get("t")), "v": e.get("v")}
            for e in entries
        ]

    return {
        "sensors": sensors,
        "history": history,
        "timestamp": _epoch_to_iso(data.get("timestamp")) if isinstance(data.get("timestamp"), (int, float)) else data.get("timestamp"),
        "error": None,
    }


# Nomi sensori di potenza (contengono "Power" o "Consumo")
_POWER_KEYWORDS = ("power", "consumo")


def _guess_category(name):
    """Determina la categoria dal nome del sensore."""
    lower = name.lower()
    for kw in _POWER_KEYWORDS:
        if kw in lower:
            return "power"
    return "temperature"


def _epoch_to_iso(ts):
    """Converte un timestamp epoch (float/int) in stringa ISO 8601."""
    if ts is None:
        return None
    if isinstance(ts, str):
        return ts  # già stringa
    try:
        from datetime import datetime, timezone
        return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
    except (ValueError, TypeError, OSError):
        return None
