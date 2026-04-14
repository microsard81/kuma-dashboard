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

def save_point(name_norm, severity, k1=None, k2=None, k3=None, n1=None):
    """
    Salva un punto nello storico di un monitor.
    Formato: "severity:k1:k2:k3:n1" (es. "1:0:0:1:0")
    Se gli stati per-sonda non sono forniti, salva solo severity (retrocompatibile).
    """
    key = f"history:{name_norm}"
    if k1 is not None and k2 is not None and k3 is not None and n1 is not None:
        value = f"{severity}:{k1}:{k2}:{k3}:{n1}"
    else:
        value = str(severity)
    r.rpush(key, value)
    r.ltrim(key, -MAX_HISTORY_POINTS, -1)


def load_history(name_norm):
    """
    Carica lo storico dal Redis. Restituisce una lista di dict:
    [{"s": severity, "k1": stato, "k2": stato, "k3": stato, "n1": stato}, ...]
    Per i punti vecchi (solo intero), k1/k2/k3/n1 saranno None.
    """
    key = f"history:{name_norm}"
    data = r.lrange(key, 0, -1)
    result = []
    for raw in (data or []):
        parts = raw.split(":")
        if len(parts) == 5:
            result.append({
                "s": int(parts[0]),
                "k1": int(parts[1]),
                "k2": int(parts[2]),
                "k3": int(parts[3]),
                "n1": int(parts[4]),
            })
        else:
            result.append({
                "s": int(parts[0]),
                "k1": None,
                "k2": None,
                "k3": None,
                "n1": None,
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