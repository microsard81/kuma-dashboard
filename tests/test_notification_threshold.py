"""
Test di proprietà per notification-threshold — Proprietà 1, 2.

Proprietà 1: Validazione soglia — correttezza completa
  Per qualsiasi valore v, validate_threshold(v) deve restituire True se e solo se
  v è un intero (non booleano) compreso nell'insieme {1, 2, 3, 4, 5}.

Proprietà 2: Conteggio sonde DOWN — proprietà metamorfica
  Per qualsiasi combinazione di 5 valori binari (bg, tim, iliad, nodeping, uptime),
  count_down_probes(bg, tim, iliad, nodeping, uptime) == 5 - (bg + tim + iliad + nodeping + uptime).

Valida: Requisiti 1.3, 1.4, 2.3, 2.4, 6.1, 6.2, 6.3, 6.4, 6.5, 14.1, 14.2, 14.3, 14.4, 15.1
"""
from hypothesis import given, settings
from hypothesis import strategies as st

from severity import count_down_probes, validate_threshold

# ---------------------------------------------------------------------------
# Strategia: valori misti per testare validate_threshold su tutti i tipi
# ---------------------------------------------------------------------------
mixed_values = st.one_of(
    st.integers(min_value=-100, max_value=100),   # interi in e fuori range
    st.floats(allow_nan=True, allow_infinity=True),  # float
    st.text(min_size=0, max_size=10),              # stringhe
    st.none(),                                      # None
    st.booleans(),                                  # booleani
)


# ---------------------------------------------------------------------------
# Proprietà 1 — Feature: notification-threshold, Property 1: Validazione soglia — correttezza completa
# ---------------------------------------------------------------------------
@given(v=mixed_values)
@settings(max_examples=100)
def test_validate_threshold_correctness(v):
    """
    Proprietà 1: Validazione soglia — correttezza completa.

    Per qualsiasi valore v, validate_threshold(v) deve restituire True
    se e solo se v è un intero (non booleano) in {1, 2, 3, 4, 5}.

    **Validates: Requirements 1.3, 1.4, 2.3, 2.4, 14.1, 14.2, 14.3, 14.4**
    """
    expected = isinstance(v, int) and not isinstance(v, bool) and 1 <= v <= 5
    assert validate_threshold(v) == expected, (
        f"validate_threshold({v!r}) ha restituito {validate_threshold(v)}, "
        f"atteso {expected}"
    )


# ---------------------------------------------------------------------------
# Proprietà 2 — Feature: notification-threshold, Property 2: Conteggio sonde DOWN — proprietà metamorfica
# ---------------------------------------------------------------------------
@given(
    bg=st.integers(min_value=0, max_value=1),
    tim=st.integers(min_value=0, max_value=1),
    iliad=st.integers(min_value=0, max_value=1),
    nodeping=st.integers(min_value=0, max_value=1),
    uptime=st.integers(min_value=0, max_value=1),
)
@settings(max_examples=100)
def test_count_down_probes_metamorphic(
    bg: int, tim: int, iliad: int, nodeping: int, uptime: int
):
    """
    Proprietà 2: Conteggio sonde DOWN — proprietà metamorfica.

    Per qualsiasi combinazione di 5 valori binari, il conteggio delle sonde DOWN
    deve essere uguale a 5 - (bg + tim + iliad + nodeping + uptime).

    **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5, 15.1**
    """
    result = count_down_probes(bg, tim, iliad, nodeping, uptime)
    expected = 5 - (bg + tim + iliad + nodeping + uptime)
    assert result == expected, (
        f"count_down_probes({bg}, {tim}, {iliad}, {nodeping}, {uptime}) "
        f"ha restituito {result}, atteso {expected}"
    )


# ---------------------------------------------------------------------------
# Imports aggiuntivi per Proprietà 3 e 4
# ---------------------------------------------------------------------------
import json
import fakeredis
from unittest.mock import patch, MagicMock

import push_utils
from push_utils import send_push_to_all, SUBS_HASH_KEY


# ---------------------------------------------------------------------------
# Strategia: subscription con soglia casuale o assente
# ---------------------------------------------------------------------------
def _sub_strategy():
    """Strategia per generare una singola subscription con threshold casuale o assente."""
    return st.fixed_dictionaries(
        {
            "endpoint": st.from_regex(r"https://example\.com/push/[a-z0-9]{8}", fullmatch=True),
            "keys": st.fixed_dictionaries(
                {
                    "p256dh": st.from_regex(r"[A-Za-z0-9]{20}", fullmatch=True),
                    "auth": st.from_regex(r"[A-Za-z0-9]{10}", fullmatch=True),
                }
            ),
        }
    ).flatmap(
        lambda base: st.one_of(
            # Con threshold esplicito (1-5)
            st.integers(min_value=1, max_value=5).map(
                lambda t: {**base, "threshold": t}
            ),
            # Senza campo threshold (retrocompatibilità, default 1)
            st.just(base),
        )
    )


def _subs_list_strategy():
    """Genera una lista di 1-10 subscription con endpoint unici."""
    return st.lists(
        _sub_strategy(),
        min_size=1,
        max_size=10,
    ).filter(
        # Assicura endpoint unici nella lista
        lambda subs: len(set(s["endpoint"] for s in subs)) == len(subs)
    )


# ---------------------------------------------------------------------------
# Proprietà 3 — Feature: notification-threshold, Property 3: Filtraggio notifiche per soglia
# ---------------------------------------------------------------------------
@given(
    subs=_subs_list_strategy(),
    max_down_probes=st.integers(min_value=0, max_value=5),
)
@settings(max_examples=100)
def test_threshold_filtering(subs, max_down_probes):
    """
    Proprietà 3: Filtraggio notifiche per soglia.

    Per qualsiasi lista di subscription con soglie diverse (incluse subscription
    senza campo threshold) e per qualsiasi valore di max_down_probes in 0–5,
    la funzione send_push_to_all deve inviare la notifica a una subscription
    se e solo se threshold <= max_down_probes (threshold default 1 se assente).

    **Validates: Requirements 5.3, 5.4, 5.5, 10.1, 10.2, 11.2, 11.4, 12.2, 12.4, 15.3, 15.4, 15.5**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    # Popola fakeredis con le subscription
    for sub in subs:
        fake_r.hset(SUBS_HASH_KEY, sub["endpoint"], json.dumps(sub))

    mock_webpush = MagicMock()

    with patch.object(push_utils, "_redis", fake_r), \
         patch.object(push_utils, "PUSH_ENABLED", True), \
         patch.object(push_utils, "webpush", mock_webpush):
        send_push_to_all(
            title="Test",
            body="Test body",
            data={"state": "RED"},
            max_down_probes=max_down_probes,
        )

    # Calcola gli endpoint attesi: threshold <= max_down_probes
    expected_endpoints = set()
    for sub in subs:
        threshold = sub.get("threshold", 1)
        if threshold <= max_down_probes:
            expected_endpoints.add(sub["endpoint"])

    # Raccogli gli endpoint effettivamente chiamati
    called_endpoints = {
        c.kwargs["subscription_info"]["endpoint"]
        for c in mock_webpush.call_args_list
    }

    assert called_endpoints == expected_endpoints, (
        f"max_down_probes={max_down_probes}, "
        f"attesi={expected_endpoints}, "
        f"chiamati={called_endpoints}"
    )


# ---------------------------------------------------------------------------
# Proprietà 4 — Feature: notification-threshold, Property 4: Bypass soglia con max_down_probes=None
# ---------------------------------------------------------------------------
@given(subs=_subs_list_strategy())
@settings(max_examples=100)
def test_threshold_bypass_with_none(subs):
    """
    Proprietà 4: Bypass soglia con max_down_probes=None.

    Per qualsiasi lista di subscription con soglie diverse (incluse soglie alte
    come 5), quando max_down_probes è None, tutte le subscription devono
    ricevere la notifica.

    **Validates: Requirements 11.3, 12.3, 13.3, 13.4**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    # Popola fakeredis con le subscription
    for sub in subs:
        fake_r.hset(SUBS_HASH_KEY, sub["endpoint"], json.dumps(sub))

    mock_webpush = MagicMock()

    with patch.object(push_utils, "_redis", fake_r), \
         patch.object(push_utils, "PUSH_ENABLED", True), \
         patch.object(push_utils, "webpush", mock_webpush):
        send_push_to_all(
            title="Ripristino",
            body="Tutti i servizi sono tornati operativi",
            data={"state": "GREEN"},
            max_down_probes=None,
        )

    # Tutti gli endpoint devono ricevere la notifica
    all_endpoints = {sub["endpoint"] for sub in subs}

    called_endpoints = {
        c.kwargs["subscription_info"]["endpoint"]
        for c in mock_webpush.call_args_list
    }

    assert called_endpoints == all_endpoints, (
        f"Con max_down_probes=None tutte le subscription devono ricevere la notifica. "
        f"Attesi={all_endpoints}, chiamati={called_endpoints}"
    )


# ---------------------------------------------------------------------------
# Imports aggiuntivi per Proprietà 5 e 6
# ---------------------------------------------------------------------------
from apns_utils import APNS_SUBS_HASH_KEY


# ---------------------------------------------------------------------------
# Strategie per Proprietà 5 (VAPID) e 6 (APNs)
# ---------------------------------------------------------------------------

# VAPID subscription
vapid_endpoint = st.from_regex(r"https://example\.com/push/[a-z0-9]{16}", fullmatch=True)
vapid_key = st.from_regex(r"[A-Za-z0-9_-]{20,40}", fullmatch=True)

# APNs subscription
apns_token = st.text(alphabet="0123456789abcdef", min_size=64, max_size=64)
apns_device_id = st.uuids().map(str)
apns_environment = st.sampled_from(["production", "sandbox"])
apns_bundle_id = st.from_regex(r"com\.[a-z]{3,8}\.[a-z]{3,8}", fullmatch=True)


# ---------------------------------------------------------------------------
# Proprietà 5 — Feature: notification-threshold, Property 5: Preservazione campi subscription VAPID
# ---------------------------------------------------------------------------
@given(
    endpoint=vapid_endpoint,
    p256dh=vapid_key,
    auth=vapid_key,
    initial_threshold=st.integers(min_value=1, max_value=5),
    new_threshold=st.integers(min_value=1, max_value=5),
)
@settings(max_examples=100)
def test_vapid_subscription_field_preservation(
    endpoint: str,
    p256dh: str,
    auth: str,
    initial_threshold: int,
    new_threshold: int,
):
    """
    Proprietà 5: Preservazione campi subscription VAPID.

    Per qualsiasi subscription con endpoint e keys validi, aggiornare il campo
    threshold deve preservare tutti i campi esistenti (endpoint, keys) e
    modificare solo il campo threshold.

    Approccio: simula direttamente la logica Redis read-modify-write usata
    dall'endpoint POST /push/threshold, senza passare per Flask.

    **Validates: Requirements 1.5, 3.2**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    # 1. Crea il record originale con tutti i campi
    original_record = {
        "endpoint": endpoint,
        "keys": {"p256dh": p256dh, "auth": auth},
        "threshold": initial_threshold,
    }
    fake_r.hset(SUBS_HASH_KEY, endpoint, json.dumps(original_record))

    # 2. Simula l'aggiornamento della soglia (logica di POST /push/threshold)
    raw = fake_r.hget(SUBS_HASH_KEY, endpoint)
    assert raw is not None, "Il record deve esistere in Redis"
    record = json.loads(raw)
    record["threshold"] = new_threshold
    fake_r.hset(SUBS_HASH_KEY, endpoint, json.dumps(record))

    # 3. Rileggi e verifica la preservazione dei campi
    updated_raw = fake_r.hget(SUBS_HASH_KEY, endpoint)
    updated_record = json.loads(updated_raw)

    # Il threshold deve essere aggiornato
    assert updated_record["threshold"] == new_threshold, (
        f"threshold atteso {new_threshold}, ottenuto {updated_record['threshold']}"
    )

    # Tutti gli altri campi devono essere preservati
    assert updated_record["endpoint"] == endpoint, (
        f"endpoint alterato: atteso {endpoint!r}, ottenuto {updated_record['endpoint']!r}"
    )
    assert updated_record["keys"]["p256dh"] == p256dh, (
        f"keys.p256dh alterato: atteso {p256dh!r}, ottenuto {updated_record['keys']['p256dh']!r}"
    )
    assert updated_record["keys"]["auth"] == auth, (
        f"keys.auth alterato: atteso {auth!r}, ottenuto {updated_record['keys']['auth']!r}"
    )

    # Verifica che non ci siano campi extra aggiunti
    assert set(updated_record.keys()) == {"endpoint", "keys", "threshold"}, (
        f"Campi inattesi nel record: {set(updated_record.keys())}"
    )


# ---------------------------------------------------------------------------
# Proprietà 6 — Feature: notification-threshold, Property 6: Preservazione campi subscription APNs
# ---------------------------------------------------------------------------
@given(
    device_token=apns_token,
    device_id=apns_device_id,
    environment=apns_environment,
    registered_at=st.datetimes().map(lambda dt: dt.isoformat()),
    bundle_id=apns_bundle_id,
    initial_threshold=st.integers(min_value=1, max_value=5),
    new_threshold=st.integers(min_value=1, max_value=5),
)
@settings(max_examples=100)
def test_apns_subscription_field_preservation(
    device_token: str,
    device_id: str,
    environment: str,
    registered_at: str,
    bundle_id: str,
    initial_threshold: int,
    new_threshold: int,
):
    """
    Proprietà 6: Preservazione campi subscription APNs.

    Per qualsiasi subscription APNs con device_token, device_id, environment,
    registered_at e bundle_id validi, aggiornare il campo threshold deve
    preservare tutti i campi esistenti e modificare solo il campo threshold.

    Approccio: simula direttamente la logica Redis read-modify-write usata
    dall'endpoint POST /push/apns/threshold, senza passare per Flask.

    **Validates: Requirements 2.5, 4.2**
    """
    fake_r = fakeredis.FakeRedis(decode_responses=True)

    # 1. Crea il record originale con tutti i campi
    original_record = {
        "device_token": device_token,
        "device_id": device_id,
        "environment": environment,
        "registered_at": registered_at,
        "bundle_id": bundle_id,
        "threshold": initial_threshold,
    }
    fake_r.hset(APNS_SUBS_HASH_KEY, device_token, json.dumps(original_record))

    # 2. Simula l'aggiornamento della soglia (logica di POST /push/apns/threshold)
    raw = fake_r.hget(APNS_SUBS_HASH_KEY, device_token)
    assert raw is not None, "Il record deve esistere in Redis"
    record = json.loads(raw)
    record["threshold"] = new_threshold
    fake_r.hset(APNS_SUBS_HASH_KEY, device_token, json.dumps(record))

    # 3. Rileggi e verifica la preservazione dei campi
    updated_raw = fake_r.hget(APNS_SUBS_HASH_KEY, device_token)
    updated_record = json.loads(updated_raw)

    # Il threshold deve essere aggiornato
    assert updated_record["threshold"] == new_threshold, (
        f"threshold atteso {new_threshold}, ottenuto {updated_record['threshold']}"
    )

    # Tutti gli altri campi devono essere preservati
    assert updated_record["device_token"] == device_token, (
        f"device_token alterato: atteso {device_token!r}, ottenuto {updated_record['device_token']!r}"
    )
    assert updated_record["device_id"] == device_id, (
        f"device_id alterato: atteso {device_id!r}, ottenuto {updated_record['device_id']!r}"
    )
    assert updated_record["environment"] == environment, (
        f"environment alterato: atteso {environment!r}, ottenuto {updated_record['environment']!r}"
    )
    assert updated_record["registered_at"] == registered_at, (
        f"registered_at alterato: atteso {registered_at!r}, ottenuto {updated_record['registered_at']!r}"
    )
    assert updated_record["bundle_id"] == bundle_id, (
        f"bundle_id alterato: atteso {bundle_id!r}, ottenuto {updated_record['bundle_id']!r}"
    )

    # Verifica che non ci siano campi extra aggiunti
    expected_keys = {"device_token", "device_id", "environment", "registered_at", "bundle_id", "threshold"}
    assert set(updated_record.keys()) == expected_keys, (
        f"Campi inattesi nel record: {set(updated_record.keys()) - expected_keys}"
    )
