"""
Bug condition exploration tests for Mac APNs push notifications.

These tests demonstrate two bugs in the current code:

1. send_apns_to_all() ignores per-subscription bundle_id — always uses
   the global APNS_BUNDLE_ID from config as the apns-topic header.
2. add_apns_subscription() does not accept a bundle_id parameter, so
   Mac subscriptions cannot carry their own bundle ID.

**EXPECTED**: Both tests FAIL on unfixed code — failure confirms the bugs exist.

**Validates: Requirements 1.4, 2.3**
"""
import json
import uuid
from unittest.mock import MagicMock, patch

import fakeredis
import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

import apns_utils
from apns_utils import (
    APNS_SUBS_HASH_KEY,
    add_apns_subscription,
    send_apns_to_all,
)

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------
hex_token = st.text(alphabet="0123456789abcdef", min_size=64, max_size=64)
device_id_strategy = st.uuids().map(str)

# Bundle IDs that are intentionally DIFFERENT from the global APNS_BUNDLE_ID
mac_bundle_id = st.sampled_from([
    "com.example.MacApp",
    "com.example.UptimeDashboardMac",
    "org.test.MacMonitor",
    "io.dev.DashboardMac",
])


# ---------------------------------------------------------------------------
# Test 1 — Bundle ID ignored in send_apns_to_all()
#
# Register a subscription with a bundle_id field stored directly in Redis,
# then call send_apns_to_all() with a mocked httpx client. Assert that the
# apns-topic header in the POST call equals the subscription's bundle_id.
#
# This FAILS because current code always uses APNS_BUNDLE_ID from config.
#
# **Validates: Requirements 1.4, 2.3**
# ---------------------------------------------------------------------------
@given(token=hex_token, device_id=device_id_strategy, bundle_id=mac_bundle_id)
@settings(max_examples=50)
def test_send_apns_to_all_uses_per_subscription_bundle_id(
    token: str, device_id: str, bundle_id: str
):
    """
    Bug Condition Test 1: send_apns_to_all() must use the subscription's
    bundle_id as apns-topic header when present.

    **Validates: Requirements 1.4, 2.3**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    # Store a subscription record WITH a bundle_id field directly in Redis
    record = {
        "device_token": token,
        "device_id": device_id,
        "environment": "production",
        "bundle_id": bundle_id,
        "registered_at": "2025-01-01T00:00:00+00:00",
    }
    fake_r.hset(APNS_SUBS_HASH_KEY, token, json.dumps(record))

    # Mock httpx client
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.text = ""

    mock_client_instance = MagicMock()
    mock_client_instance.post.return_value = mock_response
    mock_client_instance.__enter__ = MagicMock(return_value=mock_client_instance)
    mock_client_instance.__exit__ = MagicMock(return_value=False)

    mock_client_cls = MagicMock(return_value=mock_client_instance)

    with patch.object(apns_utils, "_redis", fake_r), \
         patch("apns_utils.httpx.Client", mock_client_cls), \
         patch("apns_utils._generate_apns_jwt", return_value="fake.jwt.token"), \
         patch("apns_utils.APNS_KEY_PATH", "/fake/path/key.p8"):

        send_apns_to_all(
            title="Test",
            body="Test body",
            data={"state": "RED"},
        )

    # The POST must have been called with apns-topic == subscription's bundle_id
    assert mock_client_instance.post.call_count == 1, (
        f"Expected 1 POST call, got {mock_client_instance.post.call_count}"
    )

    call_kwargs = mock_client_instance.post.call_args
    headers_sent = call_kwargs.kwargs.get("headers") or call_kwargs[1].get("headers", {})

    assert headers_sent["apns-topic"] == bundle_id, (
        f"Expected apns-topic '{bundle_id}', "
        f"got '{headers_sent.get('apns-topic')}'"
    )


# ---------------------------------------------------------------------------
# Test 2 — add_apns_subscription() missing bundle_id support
#
# Call add_apns_subscription() with a bundle_id keyword argument.
# This FAILS because the function does not accept a bundle_id parameter.
#
# **Validates: Requirements 2.3**
# ---------------------------------------------------------------------------
@given(
    token=hex_token,
    device_id=device_id_strategy,
    bundle_id=mac_bundle_id,
)
@settings(max_examples=50)
def test_add_apns_subscription_accepts_bundle_id(
    token: str, device_id: str, bundle_id: str
):
    """
    Bug Condition Test 2: add_apns_subscription() must accept and store
    a bundle_id parameter for Mac subscriptions.

    **Validates: Requirements 2.3**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    with patch.object(apns_utils, "_redis", fake_r):
        # This call will FAIL with TypeError because the current function
        # signature does not include a bundle_id parameter.
        add_apns_subscription(token, device_id, "production", bundle_id=bundle_id)

        # If we get here, verify the bundle_id was stored in Redis
        raw = fake_r.hget(APNS_SUBS_HASH_KEY, token)
        assert raw is not None, "Subscription not found in Redis"

        stored = json.loads(raw)
        assert stored.get("bundle_id") == bundle_id, (
            f"Expected bundle_id '{bundle_id}' in Redis record, "
            f"got '{stored.get('bundle_id')}'"
        )
