# redis_history.py

import redis
from config import REDIS_HOST, REDIS_PORT, REDIS_DB, MAX_HISTORY_POINTS

r = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    db=REDIS_DB,
    decode_responses=True
)

# ------------------ STORICO PER MONITOR ------------------ #

def save_point(name_norm, severity, k1=None, k2=None, k3=None, n1=None, u1=None):
    """
    Salva un punto nello storico di un monitor.
    Formato a 6 campi: "severity:k1:k2:k3:n1:u1" (es. "1:0:0:1:0:1")
    Formato a 5 campi (legacy): "severity:k1:k2:k3:n1"
    Se gli stati per-sonda non sono forniti, salva solo severity (retrocompatibile).
    """
    key = f"history:{name_norm}"
    if k1 is not None and k2 is not None and k3 is not None and n1 is not None:
        if u1 is not None:
            value = f"{severity}:{k1}:{k2}:{k3}:{n1}:{u1}"
        else:
            value = f"{severity}:{k1}:{k2}:{k3}:{n1}"
    else:
        value = str(severity)
    r.rpush(key, value)
    r.ltrim(key, -MAX_HISTORY_POINTS, -1)


def load_history(name_norm):
    """
    Carica lo storico dal Redis. Restituisce una lista di dict:
    [{"s": severity, "k1": stato, "k2": stato, "k3": stato, "n1": stato, "u1": stato}, ...]
    Per i punti a 5 campi (legacy), u1 sarà None.
    Per i punti a 1 campo (legacy minimo), k1/k2/k3/n1/u1 saranno None.
    """
    key = f"history:{name_norm}"
    data = r.lrange(key, 0, -1)
    result = []
    for raw in (data or []):
        parts = raw.split(":")
        if len(parts) == 6:
            result.append({
                "s": int(parts[0]),
                "k1": int(parts[1]),
                "k2": int(parts[2]),
                "k3": int(parts[3]),
                "n1": int(parts[4]),
                "u1": int(parts[5]),
            })
        elif len(parts) == 5:
            result.append({
                "s": int(parts[0]),
                "k1": int(parts[1]),
                "k2": int(parts[2]),
                "k3": int(parts[3]),
                "n1": int(parts[4]),
                "u1": None,
            })
        else:
            result.append({
                "s": int(parts[0]),
                "k1": None,
                "k2": None,
                "k3": None,
                "n1": None,
                "u1": None,
            })
    return result


# ------------------ STATO GLOBALE PER PUSH ------------------ #

_GLOBAL_STATE_KEY = "global_state"


def get_global_state():
    """
    Ritorna lo stato globale salvato in Redis: 'GREEN', 'YELLOW', 'RED' oppure None.
    """
    val = r.get(_GLOBAL_STATE_KEY)
    if not val:
        return None
    val = val.upper()
    return val if val in ("GREEN", "YELLOW", "RED") else None


def set_global_state(state: str):
    """
    Salva lo stato globale in Redis ('GREEN' / 'YELLOW' / 'RED').
    Ignora valori non validi.
    """
    state = (state or "").upper()
    if state not in ("GREEN", "YELLOW", "RED"):
        return
    r.set(_GLOBAL_STATE_KEY, state)


# ------------------ RISORSE ANOMALE PER SAME-STATE PUSH ------------------ #

_ANOMALOUS_RESOURCES_KEY = "anomalous_resources"


def get_anomalous_resources() -> set[str]:
    """
    Ritorna il set di nomi delle risorse anomale salvato in Redis.
    Restituisce un set vuoto se la chiave non esiste.
    """
    return r.smembers(_ANOMALOUS_RESOURCES_KEY)


def set_anomalous_resources(resources: set[str]):
    """
    Sovrascrive il set di risorse anomale in Redis.
    Usa una pipeline (DELETE + SADD) per atomicità.
    Se il set è vuoto, cancella solo la chiave.
    """
    pipe = r.pipeline()
    pipe.delete(_ANOMALOUS_RESOURCES_KEY)
    if resources:
        pipe.sadd(_ANOMALOUS_RESOURCES_KEY, *resources)
    pipe.execute()


# ------------------ MAX DOWN PROBES PER SOGLIA NOTIFICA ------------------ #

_LAST_MAX_DOWN_KEY = "last_max_down_probes"


def get_last_max_down_probes() -> int | None:
    """
    Ritorna l'ultimo valore di max_down_probes usato per una notifica anomala.
    Restituisce None se la chiave non esiste (nessuna notifica anomala precedente).
    """
    val = r.get(_LAST_MAX_DOWN_KEY)
    if val is None:
        return None
    try:
        return int(val)
    except (ValueError, TypeError):
        return None


def set_last_max_down_probes(value: int):
    """
    Salva il max_down_probes dell'ultima notifica anomala in Redis.
    Usato per le notifiche GREEN/recovery: chi non ha ricevuto la notifica
    DOWN (soglia troppo alta) non deve ricevere nemmeno la GREEN.
    """
    r.set(_LAST_MAX_DOWN_KEY, str(value))


def clear_last_max_down_probes():
    """Cancella il valore dopo l'invio della notifica GREEN."""
    r.delete(_LAST_MAX_DOWN_KEY)


# ------------------ EVENT LOG PER APP iOS/macOS ------------------ #

import json
import uuid
from datetime import datetime, timezone

_EVENTS_KEY = "events:log"
_MAX_EVENTS = 500


def load_events(limit: int = 50, before: str | None = None) -> list[dict]:
    """
    Carica gli ultimi N eventi. Se 'before' è fornito (timestamp ISO),
    restituisce solo eventi precedenti a quel timestamp.
    """
    # Carica tutti e filtra (max 500, accettabile)
    raw = r.lrange(_EVENTS_KEY, 0, _MAX_EVENTS - 1)
    events = [json.loads(item) for item in (raw or [])]

    if before:
        events = [e for e in events if e["ts"] < before]

    return events[:limit]


def push_event(
    event_type: str,
    name: str,
    from_state: str,
    to_state: str,
    detail: str = "",
    severity: int = 0,
) -> None:
    """
    Registra un evento di transizione nel log Redis.

    event_type: 'global' | 'monitor' | 'sensor'
    name: nome della risorsa (es. 'www.regione.vda.it', 'Temperatura Media', 'global')
    from_state: stato precedente
    to_state: stato corrente
    detail: dettaglio opzionale (es. "DOWN su TIM, NodePing")
    severity: 0 (normal), 1 (warning), 2 (critical)
    """
    event = {
        "id": str(uuid.uuid4()),
        "ts": datetime.now(timezone.utc).isoformat(),
        "type": event_type,
        "name": name,
        "from": from_state,
        "to": to_state,
        "detail": detail,
        "severity": severity,
    }
    r.lpush(_EVENTS_KEY, json.dumps(event))
    r.ltrim(_EVENTS_KEY, 0, _MAX_EVENTS - 1)



# ------------------ PROBE STATE PER MONITOR (per granular event log) ------------------ #

_MONITOR_PROBES_KEY = "monitor_probes_state"


def get_monitor_probes_state() -> dict[str, set[str]]:
    """
    Ritorna lo stato delle sonde DOWN per ogni monitor anomalo.
    Formato: {"nome_monitor": {"tim", "iliad"}, ...}
    """
    raw = r.hgetall(_MONITOR_PROBES_KEY)
    result = {}
    for name, probes_str in (raw or {}).items():
        result[name] = set(probes_str.split(",")) if probes_str else set()
    return result


def set_monitor_probes_state(state: dict[str, set[str]]):
    """
    Salva lo stato delle sonde DOWN per ogni monitor anomalo.
    Cancella le entry per monitor non più anomali.
    """
    pipe = r.pipeline()
    pipe.delete(_MONITOR_PROBES_KEY)
    for name, probes in state.items():
        if probes:
            pipe.hset(_MONITOR_PROBES_KEY, name, ",".join(sorted(probes)))
    pipe.execute()
