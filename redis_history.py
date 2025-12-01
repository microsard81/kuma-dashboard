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

def save_point(name_norm, severity):
    """
    Salva un punto nello storico di un monitor, usando il nome normalizzato
    come chiave stabile. Mantiene massimo MAX_HISTORY_POINTS valori.
    """
    key = f"history:{name_norm}"
    r.rpush(key, severity)
    r.ltrim(key, -MAX_HISTORY_POINTS, -1)


def load_history(name_norm):
    """
    Carica lo storico (0/1/2) dal Redis usando il nome normalizzato.
    """
    key = f"history:{name_norm}"
    data = r.lrange(key, 0, -1)
    return [int(x) for x in data] if data else []


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