# ------------------------------------------------------------
# PROBE HEALTH CLIENT – Stato sonde Kuma dal servizio kuma-webhook
# ------------------------------------------------------------
# Legge GET /probe-health dal webhook locale (127.0.0.1:9000) e restituisce
# lo stato normalizzato delle sonde di monitoraggio (check NodePing).
#
# Distinzione importante: queste NON sono le sonde dei portali (TIM/Aruba/...)
# ma la salute degli agenti di monitoraggio Kuma stessi.

import logging

import requests

from config import PROBE_HEALTH_URL, STATUS_TOKEN, HTTP_TIMEOUT

logger = logging.getLogger(__name__)

# Timeout più corto per /probe-health: è una GET locale e leggera.
_PROBE_HEALTH_TIMEOUT = min(HTTP_TIMEOUT, 5)


def _empty_response(status: str, error_msg: str | None = None) -> dict:
    """Struttura di risposta vuota/di errore con status esplicito."""
    return {
        "status": status,
        "probes": [],
        "non_operative_count": 0,
        "effective_threshold": None,
        "down_threshold_configured": None,
        "last_check": None,
        "error": error_msg,
    }


def fetch_probe_health() -> dict:
    """
    GET a PROBE_HEALTH_URL con STATUS_TOKEN.

    Returns:
        dict con chiavi:
        - status: "ok" | "disabled" | "error"
        - probes: lista di {check_id, label, is_operative, state}
        - non_operative_count: int
        - effective_threshold: int | None
        - down_threshold_configured: int | None
        - last_check: str (ISO) | None
        - error: str | None  (valorizzato solo se status == "error")

    Il consumatore deve sempre controllare `status` prima di leggere `probes`.
    """
    try:
        resp = requests.get(
            PROBE_HEALTH_URL,
            headers={"Authorization": f"Bearer {STATUS_TOKEN}"},
            timeout=_PROBE_HEALTH_TIMEOUT,
        )
    except requests.exceptions.Timeout:
        logger.warning("Timeout connessione a probe-health")
        return _empty_response("error", "Timeout connessione a probe-health")
    except requests.exceptions.ConnectionError as exc:
        logger.warning("Errore di connessione a probe-health: %s", exc)
        return _empty_response("error", "Errore di connessione al webhook")
    except requests.exceptions.RequestException as exc:
        logger.warning("Errore richiesta probe-health: %s", exc)
        return _empty_response("error", "Errore di connessione al webhook")

    if resp.status_code == 401:
        logger.error("probe-health: token non valido (401)")
        return _empty_response("error", "Autenticazione non valida")

    if resp.status_code != 200:
        logger.warning("Errore HTTP %d da probe-health", resp.status_code)
        return _empty_response("error", f"Errore HTTP {resp.status_code}")

    try:
        data = resp.json()
    except (ValueError, requests.exceptions.JSONDecodeError):
        logger.warning("Risposta non valida (JSON) da probe-health")
        return _empty_response("error", "Risposta non valida dal server")

    status = data.get("status")

    # Monitor disabilitato: l'endpoint risponde 200 ma senza dati sonde.
    if status == "disabled":
        result = _empty_response("disabled")
        result["reason"] = data.get("reason", "Monitoraggio sonde non attivo")
        result["error"] = None
        return result

    if status != "ok":
        logger.info("probe-health status inatteso: %s", status)
        return _empty_response("error", f"Stato inatteso: {status}")

    # Normalizza le sonde — usa sempre is_operative come riferimento affidabile.
    raw_probes = data.get("probes", [])
    probes = []
    for p in raw_probes:
        probes.append({
            "check_id": p.get("check_id", ""),
            "label": p.get("label", ""),
            "is_operative": bool(p.get("is_operative", p.get("state") == 1)),
            "state": p.get("state"),
        })

    return {
        "status": "ok",
        "probes": probes,
        "non_operative_count": data.get("non_operative_count", 0),
        "effective_threshold": data.get("effective_threshold"),
        "down_threshold_configured": data.get("down_threshold_configured"),
        "last_check": data.get("last_check"),
        "error": None,
    }
