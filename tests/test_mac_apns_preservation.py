"""
Preservation property tests for iOS APNs subscriptions (BEFORE fix).

These tests capture the baseline behavior of the UNFIXED code for non-buggy
inputs (iOS subscriptions without bundle_id). They MUST PASS on the unfixed
code and continue to pass after the Mac push notification fix is applied.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**
"""
import json
import uuid
from unittest.mock import MagicMock, patch

import fakeredis
from hypothesis import given, settings
from hypothesis import strategies as st

import apns_utils
from apns_utils import (
    APNS_SUBS_HASH_KEY,
    add_apns_subscription,
    send_apns_to_all,
)
from config import APNS_BUNDLE_ID

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------
hex_token = st.text(alphabet="0123456789abcdef", min_size=64, max_size=64)
device_id_strategy = st.uuids().map(str)
environment_strategy = st.sampled_from(["production", "sandbox"])


# ---------------------------------------------------------------------------
# Property 1 — iOS subscription round-trip preservation
# For all valid (token, device_id, environment) without bundle_id,
# add_apns_subscription stores exactly {device_token, device_id, environment,
# registered_at} in Redis. The stored record must NOT contain a bundle_id key.
#
# **Validates: Requirements 3.1**
# ---------------------------------------------------------------------------
@given(token=hex_token, device_id=device_id_strategy, env=environment_strategy)
@settings(max_examples=100)
def test_ios_subscription_roundtrip_preservation(token: str, device_id: str, env: str):
    """
    Property 1: iOS subscription round-trip preservation.

    **Validates: Requirements 3.1**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    with patch.object(apns_utils, "_redis", fake_r):
        add_apns_subscription(token, device_id, env)

        raw = fake_r.hget(APNS_SUBS_HASH_KEY, token)
        assert raw is not None, f"Token {token[:8]}... not found in Redis"

        record = json.loads(raw)

        # Must contain exactly these four keys
        assert record["device_token"] == token
        assert record["device_id"] == device_id
        assert record["environment"] == env
        assert "registered_at" in record

        # Must NOT contain a bundle_id key
        assert "bundle_id" not in record, (
            f"Record unexpectedly contains 'bundle_id': {record}"
        )

        # Must have exactly 4 keys
        assert set(record.keys()) == {
            "device_token", "device_id", "environment", "registered_at"
        }, f"Unexpected keys in record: {set(record.keys())}"


# ---------------------------------------------------------------------------
# Property 2 — iOS notification apns-topic header preservation
# For all iOS subscriptions (no bundle_id in Redis record),
# send_apns_to_all() must use APNS_BUNDLE_ID as the apns-topic header value
# in the httpx POST call.
#
# **Validates: Requirements 3.2**
# ---------------------------------------------------------------------------
@given(
    token=hex_token,
    device_id=device_id_strategy,
    env=environment_strategy,
)
@settings(max_examples=100)
def test_ios_apns_topic_header_preservation(token: str, device_id: str, env: str):
    """
    Property 2: iOS notification apns-topic header preservation.

    **Validates: Requirements 3.2**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    with patch.object(apns_utils, "_redis", fake_r):
        add_apns_subscription(token, device_id, env)

        # Mock httpx client with 200 OK response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.text = ""

        mock_client_instance = MagicMock()
        mock_client_instance.post.return_value = mock_response
        mock_client_instance.__enter__ = MagicMock(return_value=mock_client_instance)
        mock_client_instance.__exit__ = MagicMock(return_value=False)

        mock_client_cls = MagicMock(return_value=mock_client_instance)

        with patch("apns_utils.httpx.Client", mock_client_cls), \
             patch("apns_utils._generate_apns_jwt", return_value="fake.jwt.token"), \
             patch("apns_utils.APNS_KEY_PATH", "/fake/path/key.p8"):

            send_apns_to_all(
                title="Test",
                body="Test body",
                data={"state": "RED"},
            )

        # Verify exactly one POST call was made
        assert mock_client_instance.post.call_count == 1, (
            f"Expected 1 POST call, got {mock_client_instance.post.call_count}"
        )

        # Extract the headers from the POST call
        call_kwargs = mock_client_instance.post.call_args
        headers_used = call_kwargs.kwargs.get("headers", call_kwargs[1].get("headers", {}))

        assert headers_used["apns-topic"] == APNS_BUNDLE_ID, (
            f"Expected apns-topic '{APNS_BUNDLE_ID}', "
            f"got '{headers_used.get('apns-topic')}'"
        )


# ---------------------------------------------------------------------------
# Property 3 — Invalid token cleanup preservation
# For all subscriptions where APNs returns status 410, the token must be
# removed from Redis after send_apns_to_all().
#
# **Validates: Requirements 3.3**
# ---------------------------------------------------------------------------
@given(
    tokens=st.lists(
        hex_token,
        min_size=1,
        max_size=5,
        unique=True,
    ),
    env=environment_strategy,
)
@settings(max_examples=100)
def test_invalid_token_cleanup_preservation(tokens: list, env: str):
    """
    Property 3: Invalid token cleanup preservation.

    **Validates: Requirements 3.3**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    with patch.object(apns_utils, "_redis", fake_r):
        # Register all tokens
        for token in tokens:
            add_apns_subscription(token, str(uuid.uuid4()), env)

        # Verify all tokens are present
        for token in tokens:
            assert fake_r.hexists(APNS_SUBS_HASH_KEY, token) is True

        # Mock httpx client returning 410 Gone for every request
        mock_response = MagicMock()
        mock_response.status_code = 410
        mock_response.text = ""

        mock_client_instance = MagicMock()
        mock_client_instance.post.return_value = mock_response
        mock_client_instance.__enter__ = MagicMock(return_value=mock_client_instance)
        mock_client_instance.__exit__ = MagicMock(return_value=False)

        mock_client_cls = MagicMock(return_value=mock_client_instance)

        with patch("apns_utils.httpx.Client", mock_client_cls), \
             patch("apns_utils._generate_apns_jwt", return_value="fake.jwt.token"), \
             patch("apns_utils.APNS_KEY_PATH", "/fake/path/key.p8"):

            send_apns_to_all(
                title="Test",
                body="Test body",
                data={"state": "RED"},
            )

        # Verify all tokens have been removed from Redis
        for token in tokens:
            assert fake_r.hexists(APNS_SUBS_HASH_KEY, token) is False, (
                f"Token {token[:8]}... still in Redis after 410 response"
            )
