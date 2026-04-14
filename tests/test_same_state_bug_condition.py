"""
Bug condition exploration tests for missing same-state notifications.

These tests demonstrate the bug where `maybe_send_global_push()` does NOT
send notifications when the global state stays YELLOW -> YELLOW or RED -> RED,
even though *new* resources have become anomalous.

**EXPECTED**: Both tests FAIL on unfixed code — failure confirms the bug exists.

The root cause is that `previous != "YELLOW"` and `previous != "RED"` conditions
in `maybe_send_global_push()` block all notifications during same-state transitions,
regardless of whether new resources have entered an anomalous state.

After the fix is applied, these same tests encode the EXPECTED behavior and
should PASS — confirming the fix works.

**Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3**
"""
from unittest.mock import patch, MagicMock

from hypothesis import given, settings, assume
from hypothesis import strategies as st

import history_worker

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------
resource_name = st.text(
    alphabet=st.characters(whitelist_categories=("L", "N", "P")),
    min_size=1,
    max_size=30,
).filter(lambda s: s.strip() != "")

PUSH_NOTIFY_ON_ALL = {
    "final_down": True,
    "probe_mismatch": True,
    "back_to_green": True,
}


def _make_monitor_detail(name: str, severity: int) -> dict:
    """Build a monitor_details entry with the given name and severity."""
    if severity == 2:
        return {"name": name, "bg": 0, "tim": 0, "iliad": 0, "nodeping": 0, "severity": 2}
    elif severity == 1:
        return {"name": name, "bg": 0, "tim": 1, "iliad": 1, "nodeping": 1, "severity": 1}
    else:
        return {"name": name, "bg": 1, "tim": 1, "iliad": 1, "nodeping": 1, "severity": 0}


# ---------------------------------------------------------------------------
# Test 1 — YELLOW -> YELLOW with new mismatch resource
#
# Previous state: YELLOW (e.g., "ServerA" had severity 1)
# Current cycle: a NEW resource enters severity 1 (e.g., "ServerB")
# Expected (correct behavior): notification sent mentioning new resource
# This FAILS on unfixed code because `previous != "YELLOW"` blocks it.
#
# **Validates: Requirements 1.1, 2.1, 2.3**
# ---------------------------------------------------------------------------
@given(
    existing_resource=resource_name,
    new_resource=resource_name,
)
@settings(max_examples=50)
def test_yellow_to_yellow_new_mismatch_sends_notification(
    existing_resource: str,
    new_resource: str,
):
    """
    Bug Condition Test 1: YELLOW -> YELLOW with a new mismatch resource
    must send a notification. On unfixed code this FAILS because
    `previous != "YELLOW"` blocks all notifications when state stays YELLOW.

    **Validates: Requirements 1.1, 2.1, 2.3**
    """
    assume(existing_resource != new_resource)

    monitor_details = [
        _make_monitor_detail(existing_resource, 1),
        _make_monitor_detail(new_resource, 1),
    ]

    # Build patches — mock anomalous resource functions if they exist (post-fix)
    extra_patches = {}
    if hasattr(history_worker, "get_anomalous_resources"):
        extra_patches["get_anom"] = patch(
            "history_worker.get_anomalous_resources",
            return_value={existing_resource},
        )
    if hasattr(history_worker, "set_anomalous_resources"):
        extra_patches["set_anom"] = patch("history_worker.set_anomalous_resources")

    managers = []

    with patch("history_worker.get_global_state", return_value="YELLOW"), \
         patch("history_worker.set_global_state"), \
         patch("history_worker.send_push_to_all") as mock_push, \
         patch("history_worker.send_apns_to_all") as mock_apns, \
         patch.object(history_worker, "PUSH_ENABLED", True), \
         patch.object(history_worker, "PUSH_NOTIFY_ON", PUSH_NOTIFY_ON_ALL):

        for p in extra_patches.values():
            p.start()
            managers.append(p)

        try:
            history_worker.maybe_send_global_push("YELLOW", monitor_details)
        finally:
            for p in managers:
                p.stop()

    # On unfixed code: send_push_to_all is NOT called at all during
    # YELLOW -> YELLOW because `previous != "YELLOW"` is False.
    # We assert the EXPECTED correct behavior (notification sent),
    # so this assertion FAILS on unfixed code — proving the bug.
    assert mock_push.called, (
        "send_push_to_all was NOT called during YELLOW -> YELLOW with new "
        "anomalous resource — this confirms the bug exists"
    )
    assert mock_apns.called, (
        "send_apns_to_all was NOT called during YELLOW -> YELLOW with new "
        "anomalous resource — this confirms the bug exists"
    )


# ---------------------------------------------------------------------------
# Test 2 — RED -> RED with new DOWN resource
#
# Previous state: RED (e.g., "ServerA" had severity 2)
# Current cycle: a NEW resource goes fully DOWN severity 2 (e.g., "ServerC")
# Expected (correct behavior): notification sent mentioning new resource
# This FAILS on unfixed code because `previous != "RED"` blocks it.
#
# **Validates: Requirements 1.2, 2.2, 2.3**
# ---------------------------------------------------------------------------
@given(
    existing_resource=resource_name,
    new_resource=resource_name,
)
@settings(max_examples=50)
def test_red_to_red_new_down_sends_notification(
    existing_resource: str,
    new_resource: str,
):
    """
    Bug Condition Test 2: RED -> RED with a new DOWN resource
    must send a notification. On unfixed code this FAILS because
    `previous != "RED"` blocks all notifications when state stays RED.

    **Validates: Requirements 1.2, 2.2, 2.3**
    """
    assume(existing_resource != new_resource)

    monitor_details = [
        _make_monitor_detail(existing_resource, 2),
        _make_monitor_detail(new_resource, 2),
    ]

    # Build patches — mock anomalous resource functions if they exist (post-fix)
    extra_patches = {}
    if hasattr(history_worker, "get_anomalous_resources"):
        extra_patches["get_anom"] = patch(
            "history_worker.get_anomalous_resources",
            return_value={existing_resource},
        )
    if hasattr(history_worker, "set_anomalous_resources"):
        extra_patches["set_anom"] = patch("history_worker.set_anomalous_resources")

    managers = []

    with patch("history_worker.get_global_state", return_value="RED"), \
         patch("history_worker.set_global_state"), \
         patch("history_worker.send_push_to_all") as mock_push, \
         patch("history_worker.send_apns_to_all") as mock_apns, \
         patch.object(history_worker, "PUSH_ENABLED", True), \
         patch.object(history_worker, "PUSH_NOTIFY_ON", PUSH_NOTIFY_ON_ALL):

        for p in extra_patches.values():
            p.start()
            managers.append(p)

        try:
            history_worker.maybe_send_global_push("RED", monitor_details)
        finally:
            for p in managers:
                p.stop()

    # On unfixed code: send_push_to_all is NOT called at all during
    # RED -> RED because `previous != "RED"` is False.
    # We assert the EXPECTED correct behavior (notification sent),
    # so this assertion FAILS on unfixed code — proving the bug.
    assert mock_push.called, (
        "send_push_to_all was NOT called during RED -> RED with new "
        "DOWN resource — this confirms the bug exists"
    )
    assert mock_apns.called, (
        "send_apns_to_all was NOT called during RED -> RED with new "
        "DOWN resource — this confirms the bug exists"
    )
