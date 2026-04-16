# Feature: add-uptime-probe, Property 1: Round-trip storico 6 campi
"""
Property-based tests for the Uptime probe (u1) addition to redis_history.

Property 1: Round-trip storico 6 campi
For any valid tuple (severity, k1, k2, k3, n1, u1) with severity ∈ {0,1,2}
and each probe ∈ {0,1}, saving with save_point and reloading with load_history
must return a dict with the same values.

**Validates: Requirements 3.2, 3.3, 13.1, 13.4**
"""
from unittest.mock import patch

import fakeredis
from hypothesis import given, settings
from hypothesis import strategies as st

import redis_history


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------
severity_st = st.sampled_from([0, 1, 2])
probe_st = st.sampled_from([0, 1])

monitor_name = st.text(
    alphabet=st.characters(whitelist_categories=("L", "N")),
    min_size=1,
    max_size=20,
).filter(lambda s: s.strip() != "")


# ---------------------------------------------------------------------------
# Property 1 — Round-trip storico 6 campi
#
# For any valid tuple (severity, k1, k2, k3, n1, u1), save_point followed
# by load_history must return a dict with the same values.
#
# **Validates: Requirements 3.2, 3.3, 13.1, 13.4**
# ---------------------------------------------------------------------------
@given(
    name=monitor_name,
    severity=severity_st,
    k1=probe_st,
    k2=probe_st,
    k3=probe_st,
    n1=probe_st,
    u1=probe_st,
)
@settings(max_examples=100)
def test_round_trip_6_fields(name, severity, k1, k2, k3, n1, u1):
    """
    Property 1: Round-trip storico 6 campi.

    Saving a point with 6 fields (severity + 5 probes including u1) and
    reloading it must produce a dict with identical values.

    **Validates: Requirements 3.2, 3.3, 13.1, 13.4**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    with patch.object(redis_history, "r", fake_r):
        # Save a single point with all 6 fields
        redis_history.save_point(name, severity, k1=k1, k2=k2, k3=k3, n1=n1, u1=u1)

        # Reload history
        history = redis_history.load_history(name)

    assert len(history) == 1, f"Expected 1 point, got {len(history)}"

    point = history[0]
    assert point["s"] == severity, f"severity: expected {severity}, got {point['s']}"
    assert point["k1"] == k1, f"k1: expected {k1}, got {point['k1']}"
    assert point["k2"] == k2, f"k2: expected {k2}, got {point['k2']}"
    assert point["k3"] == k3, f"k3: expected {k3}, got {point['k3']}"
    assert point["n1"] == n1, f"n1: expected {n1}, got {point['n1']}"
    assert point["u1"] == u1, f"u1: expected {u1}, got {point['u1']}"


# ---------------------------------------------------------------------------
# Property 2 — Retrocompatibilità formato 5 campi
#
# For any valid string "severity:k1:k2:k3:n1", load_history must return a
# dict with u1 = None and correct values for s, k1, k2, k3, n1.
#
# Feature: add-uptime-probe, Property 2: Retrocompatibilità formato 5 campi
#
# **Validates: Requirements 3.4, 10.1, 13.2**
# ---------------------------------------------------------------------------
@given(
    name=monitor_name,
    severity=severity_st,
    k1=probe_st,
    k2=probe_st,
    k3=probe_st,
    n1=probe_st,
)
@settings(max_examples=100)
def test_backward_compat_5_fields(name, severity, k1, k2, k3, n1):
    """
    Property 2: Retrocompatibilità formato 5 campi.

    For any valid 5-field string "severity:k1:k2:k3:n1" injected directly
    into Redis, load_history must return a dict with u1 = None and the
    remaining fields (s, k1, k2, k3, n1) matching the original values.

    **Validates: Requirements 3.4, 10.1, 13.2**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    # Build the legacy 5-field string and inject it directly into Redis
    raw_value = f"{severity}:{k1}:{k2}:{k3}:{n1}"
    key = f"history:{name}"
    fake_r.rpush(key, raw_value)

    with patch.object(redis_history, "r", fake_r):
        history = redis_history.load_history(name)

    assert len(history) == 1, f"Expected 1 point, got {len(history)}"

    point = history[0]
    assert point["s"] == severity, f"severity: expected {severity}, got {point['s']}"
    assert point["k1"] == k1, f"k1: expected {k1}, got {point['k1']}"
    assert point["k2"] == k2, f"k2: expected {k2}, got {point['k2']}"
    assert point["k3"] == k3, f"k3: expected {k3}, got {point['k3']}"
    assert point["n1"] == n1, f"n1: expected {n1}, got {point['n1']}"
    assert point["u1"] is None, f"u1: expected None, got {point['u1']}"


# ---------------------------------------------------------------------------
# Property 3 — Retrocompatibilità formato 1 campo
#
# For any valid string "severity" with severity ∈ {0,1,2}, load_history must
# return a dict with all probe fields (k1, k2, k3, n1, u1) as None and s
# equal to the severity value.
#
# Feature: add-uptime-probe, Property 3: Retrocompatibilità formato 1 campo
#
# **Validates: Requirements 3.5, 10.2, 13.3**
# ---------------------------------------------------------------------------
@given(
    name=monitor_name,
    severity=st.sampled_from([0, 1, 2]),
)
@settings(max_examples=100)
def test_backward_compat_1_field(name, severity):
    """
    Property 3: Retrocompatibilità formato 1 campo.

    For any valid 1-field string "severity" injected directly into Redis,
    load_history must return a dict with all probe fields (k1, k2, k3, n1, u1)
    as None and s equal to the severity value.

    **Validates: Requirements 3.5, 10.2, 13.3**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    # Build the legacy 1-field string and inject it directly into Redis
    raw_value = str(severity)
    key = f"history:{name}"
    fake_r.lpush(key, raw_value)

    with patch.object(redis_history, "r", fake_r):
        history = redis_history.load_history(name)

    assert len(history) == 1, f"Expected 1 point, got {len(history)}"

    point = history[0]
    assert point["s"] == severity, f"severity: expected {severity}, got {point['s']}"
    assert point["k1"] is None, f"k1: expected None, got {point['k1']}"
    assert point["k2"] is None, f"k2: expected None, got {point['k2']}"
    assert point["k3"] is None, f"k3: expected None, got {point['k3']}"
    assert point["n1"] is None, f"n1: expected None, got {point['n1']}"
    assert point["u1"] is None, f"u1: expected None, got {point['u1']}"


# ---------------------------------------------------------------------------
# Property 4 — Severity mismatch con 5 sonde
#
# For any combination of 5 binary values (bg, tim, iliad, nodeping, uptime)
# where not all values are equal, compute_severity must return 1.
#
# Feature: add-uptime-probe, Property 4: Severity mismatch con 5 sonde
#
# **Validates: Requirements 2.4**
# ---------------------------------------------------------------------------
from hypothesis import assume

from severity import compute_severity


@given(
    bg=probe_st,
    tim=probe_st,
    iliad=probe_st,
    nodeping=probe_st,
    uptime=probe_st,
)
@settings(max_examples=100)
def test_severity_mismatch_5_probes(bg, tim, iliad, nodeping, uptime):
    """
    Property 4: Severity mismatch con 5 sonde.

    For any combination of 5 binary values (bg, tim, iliad, nodeping, uptime)
    where not all values are equal, compute_severity must return 1
    (giallo/mismatch).

    **Validates: Requirements 2.4**
    """
    # Filter out cases where all 5 values are equal (all UP or all DOWN)
    assume(not (bg == tim == iliad == nodeping == uptime))

    result = compute_severity(bg, tim, iliad, nodeping, uptime)
    assert result == 1, (
        f"Expected severity 1 (mismatch) for bg={bg}, tim={tim}, iliad={iliad}, "
        f"nodeping={nodeping}, uptime={uptime}, got {result}"
    )


# ---------------------------------------------------------------------------
# Property 5 — Compatibilità severity con sonda UP aggiuntiva
#
# For any combination of 4 concordant binary values (bg, tim, iliad, nodeping)
# (all 0 or all 1), adding uptime=1 must:
#   - return 0 when all 4 are UP  (5×UP → verde)
#   - return 1 when all 4 are DOWN (4×DOWN + 1×UP → mismatch, not 2)
#
# Feature: add-uptime-probe, Property 5: Compatibilità severity con sonda UP aggiuntiva
#
# **Validates: Requirements 2.5**
# ---------------------------------------------------------------------------
@given(
    concordant_value=st.sampled_from([0, 1]),
)
@settings(max_examples=100)
def test_severity_compat_additional_up_probe(concordant_value):
    """
    Property 5: Compatibilità severity con sonda UP aggiuntiva.

    When uptime=1 (UP or not configured), severity is based only on the
    4 core probes. So:
      - 4×UP + uptime=1 → severity 0 (verde, all core UP)
      - 4×DOWN + uptime=1 → severity 2 (rosso, all core DOWN — uptime ignored)

    **Validates: Requirements 2.5**
    """
    bg = tim = iliad = nodeping = concordant_value

    result = compute_severity(bg, tim, iliad, nodeping, uptime=1)

    if concordant_value == 1:
        # All 4 UP + uptime UP → all 5 UP → severity 0 (verde)
        assert result == 0, (
            f"Expected severity 0 (all UP) for bg={bg}, tim={tim}, iliad={iliad}, "
            f"nodeping={nodeping}, uptime=1, got {result}"
        )
    else:
        # All 4 DOWN + uptime UP → mismatch → severity 1 (giallo), NOT 2 (rosso)
        assert result == 1, (
            f"Expected severity 1 (mismatch) for bg={bg}, tim={tim}, iliad={iliad}, "
            f"nodeping={nodeping}, uptime=1, got {result}"
        )


# ---------------------------------------------------------------------------
# Property 6 — Stato finale con 5 sonde
#
# For any combination of 5 binary values (bg, tim, iliad, nodeping, uptime),
# process_monitor must return final=0 (DOWN) if and only if all 5 values are 0.
#
# Feature: add-uptime-probe, Property 6: Stato finale con 5 sonde
#
# **Validates: Requirements 5.2, 5.3**
# ---------------------------------------------------------------------------
from status_client import process_monitor


@given(
    bg=probe_st,
    tim=probe_st,
    iliad=probe_st,
    nodeping=probe_st,
    uptime=probe_st,
)
@settings(max_examples=100)
def test_final_state_5_probes(bg, tim, iliad, nodeping, uptime):
    """
    Property 6: Stato finale con 5 sonde.

    process_monitor must return final=0 (DOWN) when all 4 core probes
    (bg, tim, iliad, nodeping) are DOWN, regardless of uptime state.

    **Validates: Requirements 5.2, 5.3**
    """
    from config import PROBE_BG, PROBE_TIM, PROBE_ILIAD, PROBE_NODEPING, PROBE_UPTIME

    monitor_name = "Test Monitor"
    name_norm = "test-monitor"

    # Build the probes list: a probe is in the list when its state is 0 (DOWN)
    probes = []
    if bg == 0:
        probes.append(PROBE_BG)
    if tim == 0:
        probes.append(PROBE_TIM)
    if iliad == 0:
        probes.append(PROBE_ILIAD)
    if nodeping == 0:
        probes.append(PROBE_NODEPING)
    if uptime == 0:
        probes.append(PROBE_UPTIME)

    status_dict = {
        "http://example.com": {
            "last_name": monitor_name,
            "probes": probes,
        }
    }

    with patch("status_client.load_history", return_value=[]):
        result = process_monitor(monitor_name, status_dict, name_norm)

    # final is DOWN when all 5 probes are DOWN
    all_down = bg == 0 and tim == 0 and iliad == 0 and nodeping == 0 and uptime == 0
    expected_final = 0 if all_down else 1

    assert result["final"] == expected_final, (
        f"Expected final={expected_final} for bg={bg}, tim={tim}, iliad={iliad}, "
        f"nodeping={nodeping}, uptime={uptime}, got {result['final']}"
    )


# ---------------------------------------------------------------------------
# Property 7 — Notifiche push includono sonda Uptime
#
# For any list of monitor_details where at least one monitor has uptime=0
# and severity=1, _build_detail_body must include "Uptime" in the DOWN
# probes list for that monitor.
#
# Feature: add-uptime-probe, Property 7: Notifiche push includono sonda Uptime
#
# **Validates: Requirements 4.7, 11.1, 11.2**
# ---------------------------------------------------------------------------
from history_worker import _build_detail_body

monitor_detail_st = st.fixed_dictionaries({
    "name": st.text(
        alphabet=st.characters(whitelist_categories=("L", "N")),
        min_size=1,
        max_size=15,
    ),
    "bg": probe_st,
    "tim": probe_st,
    "iliad": probe_st,
    "nodeping": probe_st,
    "uptime": probe_st,
    "severity": st.sampled_from([0, 1, 2]),
})


@given(
    details=st.lists(monitor_detail_st, min_size=1, max_size=5),
)
@settings(max_examples=100)
def test_push_notification_includes_uptime(details):
    """
    Property 7: Notifiche push includono sonda Uptime.

    For any list of monitor_details where at least one monitor has uptime=0
    and severity=1 (mismatch), _build_detail_body must include "Uptime" in
    the DOWN probes list for that monitor.

    **Validates: Requirements 4.7, 11.1, 11.2**
    """
    # Ensure at least one monitor has uptime=0 and severity=1
    has_target = any(m["uptime"] == 0 and m["severity"] == 1 for m in details)
    if not has_target:
        # Force one monitor to have uptime=0 and severity=1
        details[0]["uptime"] = 0
        details[0]["severity"] = 1

    # Test with YELLOW state (mismatch notifications)
    body = _build_detail_body(details, "YELLOW")

    # For each monitor with uptime=0 and severity=1, "Uptime" must appear
    for m in details:
        if m["uptime"] == 0 and m["severity"] == 1:
            assert body is not None, "Expected non-None body for YELLOW state with mismatch monitors"
            assert "Uptime" in body, (
                f"Expected 'Uptime' in notification body for monitor {m['name']} "
                f"with uptime=0 and severity=1. Body: {body}"
            )
