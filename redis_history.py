# redis_history.py

import redis
from config import REDIS_HOST, REDIS_PORT, REDIS_DB, MAX_HISTORY_POINTS

r = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    db=REDIS_DB,
    decode_responses=True
)

def save_point(url, severity):
    """
    Salva un punto nello storico di un monitor, usando l'URL come chiave stabile.
    Mantiene massimo MAX_HISTORY_POINTS valori.
    """
    key = f"history:{url}"
    r.rpush(key, severity)
    r.ltrim(key, -MAX_HISTORY_POINTS, -1)

def load_history(url):
    """
    Carica lo storico (0/1/2) dal Redis usando l'URL come chiave stabile.
    """
    key = f"history:{url}"
    data = r.lrange(key, 0, -1)
    return [int(x) for x in data] if data else []