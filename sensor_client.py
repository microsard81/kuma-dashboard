# ------------------------------------------------------------
# SENSOR CLIENT – Fetch dati inverter da invadcstatus endpoint
# ------------------------------------------------------------

import logging
from datetime import datetime, timezone

import requests

from config import INVERTER_STATUS_URL, STATUS_TOKEN, HTTP_TIMEOUT

logger = logging.getLogger(__name__)


# Mapping type → category per raggruppamento UI
_TYPE_CATEGORY_MAP = {
    "TEMPERATURE": "temperature",
    "POWER_KWATTS": "power",
    "VOLTAGE": "generator",
    "STATE": None,  # determinato dal room/contesto
    "NUMBER": None,  # determinato dal room/contesto
}

# Prefissi room per determinare la categoria di sensori STATE/NUMBER
_ROOM_CATEGORY_RULES = {
    "UPS": "ups",
    "GE": "generator",
}


def _determine_category(sensor_type: str, room: str, name: str) -> str:
    """
    Determina la categoria del sensore per il raggruppamento UI.

    Categorie: temperature, power, ups, generator
    """
    # Prima prova il mapping diretto per tipo
    mapped = _TYPE_CATEGORY_MAP.get(sensor_type)
    if mapped is not None:
        # VOLTAGE va in generator, POWER_KWATTS in power, TEMPERATURE in temperature
        # Le fasi UPS (POWER_KWATTS con room UPS) vanno in ups
        if sensor_type == "POWER_KWATTS" and "UPS" in (room or ""):
            return "ups"
        return mapped

    # Per STATE e NUMBER, determina dalla room
    room_upper = (room or "").upper()
    for prefix, cat in _ROOM_CATEGORY_RULES.items():
        if prefix in room_upper:
            return cat

    # Fallback: se il nome contiene indizi
    name_upper = (name or "").upper()
    if "UPS" in name_upper:
        return "ups"
    if "GE" in name_upper or "GENERATORE" in name_upper:
        return "generator"

    return "other"


def _evaluate_threshold(value, threshold: dict | None) -> str:
    """
    Valuta il threshold per-sensore e ritorna lo stato: "normal" o "critical".

    Tipi di threshold supportati:
    - {"type": "above", "value": X} → critical se valore > X
    - {"type": "below", "value": X} → critical se valore < X
    - {"type": "greater_than", "value": X} → critical se valore > X
    - {"type": "not_equal", "expected": "V"} → critical se valore != V
    - {"type": "not_in", "expected": [...]} → critical se valore non nella lista
    """
    if threshold is None:
        return "normal"
    if value is None:
        return "normal"

    th_type = threshold.get("type", "")

    if th_type == "above":
        th_value = threshold.get("value")
        if th_value is not None and isinstance(value, (int, float)):
            return "critical" if value > th_value else "normal"

    elif th_type == "below":
        th_value = threshold.get("value")
        if th_value is not None and isinstance(value, (int, float)):
            return "critical" if value < th_value else "normal"

    elif th_type == "greater_than":
        th_value = threshold.get("value")
        if th_value is not None and isinstance(value, (int, float)):
            return "critical" if value > th_value else "normal"

    elif th_type == "not_equal":
        expected = threshold.get("expected")
        if expected is not None:
            return "critical" if value != expected else "normal"

    elif th_type == "not_in":
        expected_list = threshold.get("expected", [])
        if expected_list:
            return "critical" if value not in expected_list else "normal"

    return "normal"


def _empty_response(error_msg: str) -> dict:
    """Ritorna struttura di risposta vuota con messaggio di errore."""
    return {
        "sensors": [],
        "history": {},
        "sites": {},
        "timestamp": None,
        "error": error_msg,
    }


def fetch_inverter_data() -> dict:
    """
    POST a INVERTER_STATUS_URL con STATUS_TOKEN.

    Returns:
        dict con chiavi: sensors, history, sites, timestamp, error
        - error è None in caso di successo
        - error è una stringa descrittiva in caso di fallimento

    Ogni sensore include:
        id, name, category, value, unit, timestamp, site, room,
        type, description, threshold, status
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

    # Parse sites
    sites = data.get("sites", {})

    # Normalizza i sensori con il nuovo formato
    raw_sensors = data.get("sensors", [])
    sensors = []
    for s in raw_sensors:
        name = s.get("name", "")
        sensor_type = s.get("type", "")
        room = s.get("room", "")
        site = s.get("site", "")
        threshold = s.get("threshold")  # per-sensore, può essere None
        value = s.get("value")
        unit = s.get("unit", "")

        category = _determine_category(sensor_type, room, name)

        # Valuta lo stato alert dal threshold per-sensore
        status = _evaluate_threshold(value, threshold)

        sensors.append({
            "id": name,
            "name": name,
            "category": category,
            "value": value,
            "unit": unit,
            "timestamp": _epoch_to_iso(s.get("timestamp")),
            "site": site,
            "room": room,
            "type": sensor_type,
            "description": s.get("description", ""),
            "threshold": threshold,
            "status": status,
        })

    # Normalizza history: timestamps epoch → ISO, supporta valori stringa
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
        "sites": sites,
        "timestamp": _epoch_to_iso(data.get("timestamp")) if isinstance(data.get("timestamp"), (int, float)) else data.get("timestamp"),
        "error": None,
    }


def _epoch_to_iso(ts) -> str | None:
    """Converte un timestamp epoch (float/int) in stringa ISO 8601."""
    if ts is None:
        return None
    if isinstance(ts, str):
        return ts
    try:
        return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
    except (ValueError, TypeError, OSError):
        return None
