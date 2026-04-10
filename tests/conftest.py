"""Configurazione pytest per i test del backend."""
import pytest
import fakeredis


@pytest.fixture
def fake_redis():
    """Istanza fakeredis con decode_responses=True, compatibile con apns_utils."""
    return fakeredis.FakeRedis(decode_responses=True)
