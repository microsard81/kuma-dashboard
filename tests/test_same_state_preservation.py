"""
Preservation property tests for maybe_send_global_push().

These tests capture the EXISTING correct behavior of the function BEFORE
the bugfix is applied. They must PASS on both unfixed and fixed code,
ensuring no regressions are introduced.

Property 2: Preservation — State Transition and Non-Buggy Behavior Unchanged

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**
"""
from unittest.mock import patch, MagicMock, call

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
        return {"name": name, "bg": 0, "tim": 0, "iliad": 0, "nodeping": 0, "uptime": 0, "severity": 2}
    elif severity == 1:
        return {"name": name, "bg": 0, "tim": 1, "iliad": 1, "nodeping": 1, "uptime": 1, "severity": 1}
    else:
        return {"name": name, "bg": 1, "tim": 1, "iliad": 1, "nodeping": 1, "uptime": 1, "severity": 0}


# Strategies for monitor_details lists
severity1_details = st.lists(
    resource_name.map(lambda n: _make_monitor_detail(n, 1)),
    min_size=1,
    max_size=5,
)

severity2_details = st.lists(
    resource_name.map(lambda n: _make_monitor_detail(n, 2)),
    min_size=1,
    max_size=5,
)

green_details = st.lists(
    resource_name.map(lambda n: _make_monitor_detail(n, 0)),
    min_size=1,
    max_size=5,
)

previous_non_green = st.sampled_from(["RED", "YELLOW"])


def _patch_common():
    """Return common patches for preservation tests, ignoring anomalous resource functions if they exist."""
    patches = {}
    # Patch anomalous resource functions if they exist (post-fix code)
    if hasattr(history_worker, "get_anomalous_resources"):
        patches["get_anom"] = patch("history_worker.get_anomalous_resources", return_value=set())
    if hasattr(history_worker, "set_anomalous_resources"):
        patches["set_anom"] = patch("history_worker.set_anomalous_resources")
    return patches


# ---------------------------------------------------------------------------
# Test 1 — GREEN -> YELLOW preservation
#
# For all valid monitor_details with at least one severity 1 resource,
# transitioning from GREEN to YELLOW must call send_push_to_all and
# send_apns_to_all with title "🟡 Incongruenza tra sonde".
#
# **Validates: Requirement 3.1**
# ---------------------------------------------------------------------------
@given(details=severity1_details)
@settings(max_examples=50)
def test_green_to_yellow_sends_notification(details):
    """
    Preservation Test 1: GREEN -> YELLOW must send notification with
    title '🟡 Incongruenza tra sonde' and data {'state': 'YELLOW'}.

    **Validates: Requirement 3.1**
    """
    extra_patches = _patch_common()
    managers = []

    with patch("history_worker.get_global_state", return_value="GREEN"), \
         patch("history_worker.set_global_state"), \
         patch("history_worker.send_push_to_all") as mock_push, \
         patch("history_worker.send_apns_to_all") as mock_apns, \
         patch.object(history_worker, "PUSH_ENABLED", True), \
         patch.object(history_worker, "PUSH_NOTIFY_ON", PUSH_NOTIFY_ON_ALL):

        # Apply extra patches for post-fix compatibility
        for p in extra_patches.values():
            p.start()
            managers.append(p)

        try:
            history_worker.maybe_send_global_push("YELLOW", details)
        finally:
            for p in managers:
                p.stop()

    mock_push.assert_called_once()
    assert mock_push.call_args[0][0] == "🟡 Incongruenza tra sonde"
    assert mock_push.call_args[0][2] == {"state": "YELLOW"}

    mock_apns.assert_called_once()
    assert mock_apns.call_args[0][0] == "🟡 Incongruenza tra sonde"


# ---------------------------------------------------------------------------
# Test 2 — GREEN -> RED preservation
#
# **Validates: Requirement 3.2**
# ---------------------------------------------------------------------------
@given(details=severity2_details)
@settings(max_examples=50)
def test_green_to_red_sends_notification(details):
    """
    Preservation Test 2: GREEN -> RED must send notification with
    title '🔴 Servizi DOWN' and data {'state': 'RED'}.

    **Validates: Requirement 3.2**
    """
    extra_patches = _patch_common()
    managers = []

    with patch("history_worker.get_global_state", return_value="GREEN"), \
         patch("history_worker.set_global_state"), \
         patch("history_worker.send_push_to_all") as mock_push, \
         patch("history_worker.send_apns_to_all") as mock_apns, \
         patch.object(history_worker, "PUSH_ENABLED", True), \
         patch.object(history_worker, "PUSH_NOTIFY_ON", PUSH_NOTIFY_ON_ALL):

        for p in extra_patches.values():
            p.start()
            managers.append(p)

        try:
            history_worker.maybe_send_global_push("RED", details)
        finally:
            for p in managers:
                p.stop()

    mock_push.assert_called_once()
    assert mock_push.call_args[0][0] == "🔴 Servizi DOWN"
    assert mock_push.call_args[0][2] == {"state": "RED"}

    mock_apns.assert_called_once()
    assert mock_apns.call_args[0][0] == "🔴 Servizi DOWN"


# ---------------------------------------------------------------------------
# Test 3 — *->GREEN preservation (from RED or YELLOW)
#
# **Validates: Requirement 3.3**
# ---------------------------------------------------------------------------
@given(prev=previous_non_green, details=green_details)
@settings(max_examples=50)
def test_to_green_sends_notification(prev, details):
    """
    Preservation Test 3: RED/YELLOW -> GREEN must send notification with
    title '🟢 Tutto OK' and data {'state': 'GREEN'}.

    **Validates: Requirement 3.3**
    """
    extra_patches = _patch_common()
    managers = []

    with patch("history_worker.get_global_state", return_value=prev), \
         patch("history_worker.set_global_state"), \
         patch("history_worker.send_push_to_all") as mock_push, \
         patch("history_worker.send_apns_to_all") as mock_apns, \
         patch.object(history_worker, "PUSH_ENABLED", True), \
         patch.object(history_worker, "PUSH_NOTIFY_ON", PUSH_NOTIFY_ON_ALL):

        for p in extra_patches.values():
            p.start()
            managers.append(p)

        try:
            history_worker.maybe_send_global_push("GREEN", details)
        finally:
            for p in managers:
                p.stop()

    mock_push.assert_called_once()
    assert mock_push.call_args[0][0] == "🟢 Tutto OK"
    assert mock_push.call_args[0][2] == {"state": "GREEN"}

    mock_apns.assert_called_once()
    assert mock_apns.call_args[0][0] == "🟢 Tutto OK"


# ---------------------------------------------------------------------------
# Test 4 — First boot preservation (previous_state = None)
#
# **Validates: Requirement 3.4**
# ---------------------------------------------------------------------------
@given(new_state=st.sampled_from(["GREEN", "YELLOW", "RED"]))
@settings(max_examples=20)
def test_first_boot_no_notification(new_state):
    """
    Preservation Test 4: When previous_state is None (first boot),
    no notifications are sent regardless of new_state.

    **Validates: Requirement 3.4**
    """
    extra_patches = _patch_common()
    managers = []

    with patch("history_worker.get_global_state", return_value=None), \
         patch("history_worker.set_global_state"), \
         patch("history_worker.send_push_to_all") as mock_push, \
         patch("history_worker.send_apns_to_all") as mock_apns, \
         patch.object(history_worker, "PUSH_ENABLED", True), \
         patch.object(history_worker, "PUSH_NOTIFY_ON", PUSH_NOTIFY_ON_ALL):

        for p in extra_patches.values():
            p.start()
            managers.append(p)

        try:
            history_worker.maybe_send_global_push(new_state, [])
        finally:
            for p in managers:
                p.stop()

    mock_push.assert_not_called()
    mock_apns.assert_not_called()


# ---------------------------------------------------------------------------
# Test 5 — PUSH_ENABLED=False preservation
#
# **Validates: Requirement 3.5**
# ---------------------------------------------------------------------------
@given(
    prev=st.sampled_from(["GREEN", "YELLOW", "RED"]),
    new_state=st.sampled_from(["GREEN", "YELLOW", "RED"]),
)
@settings(max_examples=30)
def test_push_disabled_no_notification(prev, new_state):
    """
    Preservation Test 5: When PUSH_ENABLED is False, no notifications
    are sent regardless of state transition.

    **Validates: Requirement 3.5**
    """
    extra_patches = _patch_common()
    managers = []

    with patch("history_worker.get_global_state", return_value=prev), \
         patch("history_worker.set_global_state"), \
         patch("history_worker.send_push_to_all") as mock_push, \
         patch("history_worker.send_apns_to_all") as mock_apns, \
         patch.object(history_worker, "PUSH_ENABLED", False), \
         patch.object(history_worker, "PUSH_NOTIFY_ON", PUSH_NOTIFY_ON_ALL):

        for p in extra_patches.values():
            p.start()
            managers.append(p)

        try:
            history_worker.maybe_send_global_push(new_state, [])
        finally:
            for p in managers:
                p.stop()

    mock_push.assert_not_called()
    mock_apns.assert_not_called()


# ---------------------------------------------------------------------------
# Test 6 — GREEN -> GREEN preservation
#
# **Validates: Requirement 3.6**
# ---------------------------------------------------------------------------
@given(details=green_details)
@settings(max_examples=50)
def test_green_to_green_no_notification(details):
    """
    Preservation Test 6: When both previous and new state are GREEN,
    no notifications are sent.

    **Validates: Requirement 3.6**
    """
    extra_patches = _patch_common()
    managers = []

    with patch("history_worker.get_global_state", return_value="GREEN"), \
         patch("history_worker.set_global_state"), \
         patch("history_worker.send_push_to_all") as mock_push, \
         patch("history_worker.send_apns_to_all") as mock_apns, \
         patch.object(history_worker, "PUSH_ENABLED", True), \
         patch.object(history_worker, "PUSH_NOTIFY_ON", PUSH_NOTIFY_ON_ALL):

        for p in extra_patches.values():
            p.start()
            managers.append(p)

        try:
            history_worker.maybe_send_global_push("GREEN", details)
        finally:
            for p in managers:
                p.stop()

    mock_push.assert_not_called()
    mock_apns.assert_not_called()
