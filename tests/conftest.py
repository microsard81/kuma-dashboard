"""Configurazione pytest per i test del backend.

ISOLAMENTO DALLA PRODUZIONE
I test girano anche sul server di produzione. Ogni modulo crea il proprio client
Redis all'import (redis_history.r, auth._r, rate_limit._r, app._redis,
push_utils._redis, apns_utils._redis, manage_users.r): se un test non li
sostituisce, scrive nel Redis reale (storico eventi, stato sonde, ...).
La fixture autouse `_isolate_redis` li rimpiazza TUTTI, per ogni test, con un
unico FakeRedis condiviso (stesso comportamento di un Redis reale, ma in memoria).
I test che installano un proprio FakeRedis continuano a funzionare: il loro
patch si applica sopra a questo.
"""
import os
import sys

# Nessun log push su file durante i test: altrimenti finirebbe nel push.log reale.
# load_dotenv non sovrascrive variabili già presenti, quindi questo vince sul .env.
os.environ["PUSH_LOG_FILE"] = ""

import fakeredis
import pytest

# (modulo, attributo) dei client Redis creati all'import dei moduli applicativi
_REDIS_CLIENTS = [
    ("redis_history", "r"),
    ("auth", "_r"),
    ("rate_limit", "_r"),
    ("app", "_redis"),
    ("push_utils", "_redis"),
    ("apns_utils", "_redis"),
    ("manage_users", "r"),
]


@pytest.fixture(autouse=True)
def _isolate_redis(monkeypatch):
    """Sostituisce ogni client Redis reale con un FakeRedis condiviso per il test."""
    fake = fakeredis.FakeRedis(server=fakeredis.FakeServer(), decode_responses=True)
    for module_name, attr in _REDIS_CLIENTS:
        module = sys.modules.get(module_name)
        # Solo moduli già importati dal test: non importiamo nulla qui
        # (eviterebbe side-effect di import non richiesti).
        if module is not None and hasattr(module, attr):
            monkeypatch.setattr(module, attr, fake)
    yield fake


@pytest.fixture
def fake_redis():
    """Istanza fakeredis con decode_responses=True, compatibile con apns_utils."""
    return fakeredis.FakeRedis(decode_responses=True)
