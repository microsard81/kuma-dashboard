"""Test unitari per rate_limit.py (fakeredis, tempo mockato)."""
from types import SimpleNamespace

import fakeredis
import pytest
import redis

import rate_limit
from rate_limit import Rule


RULE = Rule("test", "ip", 3, 900)
OTHER = Rule("test", "user", 3, 900)


@pytest.fixture
def fr(monkeypatch):
    client = fakeredis.FakeRedis(decode_responses=True)
    monkeypatch.setattr(rate_limit, "_r", client)
    return client


@pytest.fixture
def clock(monkeypatch):
    state = {"now": 1_000_000.0}
    monkeypatch.setattr(rate_limit, "time", SimpleNamespace(time=lambda: state["now"]))
    return state


def test_blocks_at_limit_plus_one(fr, clock):
    for _ in range(RULE.limit):
        assert rate_limit.hit(RULE, "1.2.3.4").allowed
    res = rate_limit.hit(RULE, "1.2.3.4")
    assert not res.allowed
    assert res.rule == RULE
    expected = RULE.window - int(clock["now"] % RULE.window)
    assert res.retry_after == expected
    assert res.retry_after >= 1


def test_identifiers_are_independent_and_normalized(fr, clock):
    for _ in range(RULE.limit):
        rate_limit.hit(RULE, "Mario")
    # stesso identificatore normalizzato (strip + lower)
    assert not rate_limit.hit(RULE, "  mario ").allowed
    assert rate_limit.hit(RULE, "luigi").allowed


def test_new_window_resets_counter(fr, clock):
    for _ in range(RULE.limit + 1):
        rate_limit.hit(RULE, "1.2.3.4")
    assert not rate_limit.hit(RULE, "1.2.3.4").allowed
    clock["now"] += RULE.window
    assert rate_limit.hit(RULE, "1.2.3.4").allowed


def test_key_has_ttl(fr, clock):
    rate_limit.hit(RULE, "1.2.3.4")
    keys = list(fr.scan_iter("rl:*"))
    assert len(keys) == 1
    ttl = fr.ttl(keys[0])
    assert 0 < ttl <= RULE.window + 5


def test_check_stops_at_first_block_without_incrementing_next(fr, clock):
    for _ in range(RULE.limit):
        rate_limit.hit(RULE, "1.2.3.4")
    res = rate_limit.check((RULE, "1.2.3.4"), (OTHER, "mario"))
    assert not res.allowed
    assert res.rule == RULE
    # la seconda regola non è stata toccata
    assert not any(":user:" in k for k in fr.scan_iter("rl:*"))


def test_check_all_allowed(fr, clock):
    res = rate_limit.check((RULE, "1.2.3.4"), (OTHER, "mario"))
    assert res.allowed
    assert res.retry_after == 0
    assert res.rule is None


def test_fail_open_on_redis_error(monkeypatch, clock, caplog):
    class Broken:
        def pipeline(self, *a, **kw):
            raise redis.ConnectionError("down")

    monkeypatch.setattr(rate_limit, "_r", Broken())
    with caplog.at_level("ERROR"):
        res = rate_limit.hit(RULE, "1.2.3.4")
    assert res.allowed
    assert "rate limit non disponibile" in caplog.text


def test_identifier_never_in_clear_in_key(fr, clock):
    rate_limit.hit(rate_limit.LOGIN_USER, "segreto.utente")
    rate_limit.hit(rate_limit.LOGIN_IP, "203.0.113.7")
    keys = list(fr.scan_iter("rl:*"))
    assert len(keys) == 2
    for k in keys:
        assert "segreto" not in k
        assert "203.0.113.7" not in k
        parts = k.split(":")
        assert len(parts) == 5
        assert len(parts[3]) == 32


def test_rule_constants():
    assert (rate_limit.LOGIN_IP.limit, rate_limit.LOGIN_IP.window) == (10, 900)
    assert (rate_limit.LOGIN_USER.limit, rate_limit.LOGIN_USER.window) == (5, 900)
    assert (rate_limit.TOTP_USER.limit, rate_limit.TOTP_USER.window) == (5, 900)
    assert (rate_limit.BIO_IP.limit, rate_limit.BIO_IP.window) == (10, 900)
    assert (rate_limit.CHPW_USER.limit, rate_limit.CHPW_USER.window) == (10, 900)
    assert (rate_limit.PWREQ_IP.limit, rate_limit.PWREQ_IP.window) == (10, 3600)
    assert (rate_limit.PWREQ_USER.limit, rate_limit.PWREQ_USER.window) == (3, 3600)
    assert (rate_limit.PWRESET_IP.limit, rate_limit.PWRESET_IP.window) == (10, 900)
    assert (rate_limit.PWRESET_TOKEN.limit, rate_limit.PWRESET_TOKEN.window) == (5, 900)
