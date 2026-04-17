"""
Test di proprietà per apns_utils.py — Proprietà 13, 15, 17.

Proprietà 13: Round-trip subscribe/unsubscribe APNs in Redis
  Per qualsiasi coppia (device_token, device_id) valida, dopo add_apns_subscription
  il token deve essere presente in Redis; dopo remove_apns_subscription sullo stesso
  token, il token non deve più essere presente in Redis.

Valida: Requisiti 10.1, 10.2
"""
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
    remove_apns_subscription,
    send_apns_to_all,
)

# ---------------------------------------------------------------------------
# Strategia: token hex di esattamente 64 caratteri (come un APNs device token)
# ---------------------------------------------------------------------------
hex_token = st.text(alphabet="0123456789abcdef", min_size=64, max_size=64)
device_id_strategy = st.uuids().map(str)


# ---------------------------------------------------------------------------
# Proprietà 13 — Feature: ios-native-app, Property 13: Round-trip subscribe/unsubscribe APNs in Redis
# ---------------------------------------------------------------------------
@given(token=hex_token, device_id=device_id_strategy)
@settings(max_examples=100)
def test_apns_subscribe_unsubscribe_roundtrip(token: str, device_id: str):
    """
    Proprietà 13: Round-trip subscribe/unsubscribe APNs in Redis.

    Valida: Requisiti 10.1, 10.2
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    with patch.object(apns_utils, "_redis", fake_r):
        # Precondizione: il token non è presente
        assert fake_r.hexists(APNS_SUBS_HASH_KEY, token) is False

        # Dopo add_apns_subscription il token deve essere presente
        add_apns_subscription(token, device_id)
        assert fake_r.hexists(APNS_SUBS_HASH_KEY, token) is True, (
            f"Token {token[:8]}... non trovato in Redis dopo add_apns_subscription"
        )

        # Dopo remove_apns_subscription il token non deve più essere presente
        remove_apns_subscription(token)
        assert fake_r.hexists(APNS_SUBS_HASH_KEY, token) is False, (
            f"Token {token[:8]}... ancora presente in Redis dopo remove_apns_subscription"
        )


# ---------------------------------------------------------------------------
# Proprietà 17 — Feature: ios-native-app, Property 17: Separazione namespace Redis APNs/VAPID
# ---------------------------------------------------------------------------
@given(token=hex_token, device_id=device_id_strategy)
@settings(max_examples=100)
def test_apns_redis_namespace_separation(token: str, device_id: str):
    """
    Proprietà 17: Separazione namespace Redis APNs/VAPID.

    Tutte le chiavi Redis scritte da apns_utils devono avere prefisso `apns:`
    e non devono mai collidere con il namespace VAPID (prefisso `push:`).

    Valida: Requisiti 10.7
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    with patch.object(apns_utils, "_redis", fake_r):
        add_apns_subscription(token, device_id)

        all_keys = fake_r.keys("*")

        for key in all_keys:
            assert key.startswith("apns:"), (
                f"Chiave Redis '{key}' non ha prefisso 'apns:'"
            )
            assert not key.startswith("push:"), (
                f"Chiave Redis '{key}' collide con il namespace VAPID 'push:'"
            )


# ---------------------------------------------------------------------------
# Proprietà 15 — Feature: ios-native-app, Property 15: Notifica APNs a tutti i token registrati
# ---------------------------------------------------------------------------
@given(tokens=st.lists(
    st.text(alphabet="0123456789abcdef", min_size=64, max_size=64),
    min_size=1,
    max_size=10,
    unique=True,
))
@settings(max_examples=100)
def test_send_apns_to_all_tokens(tokens: list):
    """
    Proprietà 15: Notifica APNs a tutti i token registrati.

    Per qualsiasi insieme di N token APNs registrati in Redis, quando viene
    invocata send_apns_to_all, il client httpx mockato deve ricevere esattamente
    N chiamate POST, una per ciascun token registrato.

    **Validates: Requirements 10.5**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    with patch.object(apns_utils, "_redis", fake_r):
        # Registra tutti gli N token in Redis tramite add_apns_subscription
        for token in tokens:
            add_apns_subscription(token, str(uuid.uuid4()))

        # Prepara il mock del client httpx con risposta 200 OK
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

        # Verifica che il client httpx abbia ricevuto esattamente N chiamate POST
        assert mock_client_instance.post.call_count == len(tokens), (
            f"Attese {len(tokens)} chiamate POST, "
            f"ricevute {mock_client_instance.post.call_count}"
        )


# ---------------------------------------------------------------------------
# Proprietà 16 — Feature: ios-native-app, Property 16: Rimozione automatica token APNs non validi
# ---------------------------------------------------------------------------
@given(tokens=st.lists(
    st.text(alphabet="0123456789abcdef", min_size=64, max_size=64),
    min_size=1,
    max_size=10,
    unique=True,
))
@settings(max_examples=100)
def test_apns_invalid_token_removed(tokens: list):
    """
    Proprietà 16: Rimozione automatica token APNs non validi.

    Per qualsiasi insieme di N token APNs registrati in Redis, quando il client
    APNs restituisce status 410 (Gone) per ogni token, tutti i token devono
    essere rimossi da Redis dopo la chiamata a send_apns_to_all.

    **Validates: Requirements 10.6**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    with patch.object(apns_utils, "_redis", fake_r):
        # Registra tutti gli N token in Redis
        for token in tokens:
            add_apns_subscription(token, str(uuid.uuid4()))

        # Precondizione: tutti i token sono presenti in Redis
        for token in tokens:
            assert fake_r.hexists(APNS_SUBS_HASH_KEY, token) is True

        # Mock del client httpx che restituisce sempre status 410
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

        # Verifica che ogni token sia stato rimosso da Redis
        for token in tokens:
            assert fake_r.hexists(APNS_SUBS_HASH_KEY, token) is False, (
                f"Token {token[:8]}... ancora presente in Redis dopo risposta 410"
            )


# ---------------------------------------------------------------------------
# Test unitari — Integrazione history_worker / APNs (Task 4.2)
# Valida: Requisiti 10.5
# ---------------------------------------------------------------------------
import history_worker


class TestWorkerApnsIntegration:
    """Test unitari per l'integrazione tra history_worker e send_apns_to_all."""

    def _run_maybe_send(self, previous_state, new_state, push_notify_on):
        """Helper: esegue maybe_send_global_push con i mock necessari."""
        with patch("history_worker.send_apns_to_all") as mock_apns, \
             patch("history_worker.send_push_to_all") as mock_push, \
             patch("history_worker.get_global_state", return_value=previous_state), \
             patch("history_worker.set_global_state"), \
             patch.object(history_worker, "PUSH_ENABLED", True), \
             patch.object(history_worker, "PUSH_NOTIFY_ON", push_notify_on):
            history_worker.maybe_send_global_push(new_state)
            return mock_apns, mock_push

    # ------------------------------------------------------------------
    # Transizione → RED
    # ------------------------------------------------------------------
    def test_transition_to_red_calls_send_apns(self):
        """Al cambio di stato verso RED, send_apns_to_all deve essere chiamata
        con titolo, corpo e data corretti."""
        mock_apns, mock_push = self._run_maybe_send(
            previous_state="GREEN",
            new_state="RED",
            push_notify_on={"final_down": True, "probe_mismatch": False, "back_to_green": False},
        )

        from unittest.mock import ANY
        mock_apns.assert_called_once_with(
            "🔴 Servizi DOWN",
            "Una o più risorse risultano DOWN.",
            {"state": "RED"},
            max_down_probes=ANY,
        )
        mock_push.assert_called_once()

    def test_transition_to_red_not_called_when_already_red(self):
        """Se lo stato precedente era già RED, send_apns_to_all NON deve essere chiamata."""
        mock_apns, _ = self._run_maybe_send(
            previous_state="RED",
            new_state="RED",
            push_notify_on={"final_down": True, "probe_mismatch": False, "back_to_green": False},
        )
        mock_apns.assert_not_called()

    # ------------------------------------------------------------------
    # Transizione → YELLOW
    # ------------------------------------------------------------------
    def test_transition_to_yellow_calls_send_apns(self):
        """Al cambio di stato verso YELLOW, send_apns_to_all deve essere chiamata
        con titolo, corpo e data corretti."""
        mock_apns, mock_push = self._run_maybe_send(
            previous_state="GREEN",
            new_state="YELLOW",
            push_notify_on={"final_down": False, "probe_mismatch": True, "back_to_green": False},
        )

        from unittest.mock import ANY
        mock_apns.assert_called_once_with(
            "🟡 Incongruenza tra sonde",
            "Una o più risorse hanno stato diverso tra le sonde.",
            {"state": "YELLOW"},
            max_down_probes=ANY,
        )
        mock_push.assert_called_once()

    def test_transition_to_yellow_not_called_when_already_yellow(self):
        """Se lo stato precedente era già YELLOW, send_apns_to_all NON deve essere chiamata."""
        mock_apns, _ = self._run_maybe_send(
            previous_state="YELLOW",
            new_state="YELLOW",
            push_notify_on={"final_down": False, "probe_mismatch": True, "back_to_green": False},
        )
        mock_apns.assert_not_called()

    # ------------------------------------------------------------------
    # Transizione → GREEN
    # ------------------------------------------------------------------
    def test_transition_to_green_from_red_calls_send_apns(self):
        """Al ritorno a GREEN da RED, send_apns_to_all deve essere chiamata
        con titolo, corpo e data corretti."""
        mock_apns, mock_push = self._run_maybe_send(
            previous_state="RED",
            new_state="GREEN",
            push_notify_on={"final_down": False, "probe_mismatch": False, "back_to_green": True},
        )

        from unittest.mock import ANY
        mock_apns.assert_called_once_with(
            "🟢 Tutto OK",
            ANY,
            {"state": "GREEN"},
            max_down_probes=None,
        )
        mock_push.assert_called_once()

    def test_transition_to_green_from_yellow_calls_send_apns(self):
        """Al ritorno a GREEN da YELLOW, send_apns_to_all deve essere chiamata."""
        mock_apns, mock_push = self._run_maybe_send(
            previous_state="YELLOW",
            new_state="GREEN",
            push_notify_on={"final_down": False, "probe_mismatch": False, "back_to_green": True},
        )

        from unittest.mock import ANY
        mock_apns.assert_called_once_with(
            "🟢 Tutto OK",
            ANY,
            {"state": "GREEN"},
            max_down_probes=None,
        )
        mock_push.assert_called_once()

    def test_transition_to_green_not_called_when_already_green(self):
        """Se lo stato precedente era già GREEN, send_apns_to_all NON deve essere chiamata."""
        mock_apns, _ = self._run_maybe_send(
            previous_state="GREEN",
            new_state="GREEN",
            push_notify_on={"final_down": False, "probe_mismatch": False, "back_to_green": True},
        )
        mock_apns.assert_not_called()

    # ------------------------------------------------------------------
    # Push disabilitate
    # ------------------------------------------------------------------
    def test_apns_not_called_when_push_disabled(self):
        """Se PUSH_ENABLED è False, send_apns_to_all NON deve essere chiamata."""
        with patch("history_worker.send_apns_to_all") as mock_apns, \
             patch("history_worker.send_push_to_all"), \
             patch("history_worker.get_global_state", return_value="GREEN"), \
             patch("history_worker.set_global_state"), \
             patch.object(history_worker, "PUSH_ENABLED", False), \
             patch.object(history_worker, "PUSH_NOTIFY_ON", {"final_down": True, "probe_mismatch": True, "back_to_green": True}):
            history_worker.maybe_send_global_push("RED")
            mock_apns.assert_not_called()

    # ------------------------------------------------------------------
    # Primo avvio (previous_state = None)
    # ------------------------------------------------------------------
    def test_apns_not_called_on_first_run(self):
        """Al primo avvio (previous_state = None), send_apns_to_all NON deve essere chiamata."""
        with patch("history_worker.send_apns_to_all") as mock_apns, \
             patch("history_worker.send_push_to_all"), \
             patch("history_worker.get_global_state", return_value=None), \
             patch("history_worker.set_global_state"), \
             patch.object(history_worker, "PUSH_ENABLED", True), \
             patch.object(history_worker, "PUSH_NOTIFY_ON", {"final_down": True, "probe_mismatch": True, "back_to_green": True}):
            history_worker.maybe_send_global_push("RED")
            mock_apns.assert_not_called()
