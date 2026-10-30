# ------------------------------------------------------------
# CONFIGURAZIONE KUMA DASHBOARD – VERSIONE COMPLETA (TUO + REDIS)
# ------------------------------------------------------------

import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

# --- SEGRETI OBBLIGATORI (da variabili d'ambiente) ---
FLASK_SECRET_KEY       = os.environ["FLASK_SECRET_KEY"]
STATUS_TOKEN           = os.environ["STATUS_TOKEN"]
PUSH_VAPID_PUBLIC_KEY  = os.environ["PUSH_VAPID_PUBLIC_KEY"]
PUSH_VAPID_PRIVATE_KEY = os.environ["PUSH_VAPID_PRIVATE_KEY"]
PUSH_VAPID_EMAIL       = os.environ["PUSH_VAPID_EMAIL"]

# --- Biometric token secret (usato per firmare i token monouso Face ID) ---
# Se non impostato, viene derivato da FLASK_SECRET_KEY
BIOMETRIC_SECRET = os.environ.get("BIOMETRIC_SECRET", FLASK_SECRET_KEY)

# --- Watch API token (per l'app Apple Watch) ---
WATCH_API_TOKEN = os.environ.get("WATCH_API_TOKEN", "")

# --- APNs (Apple Push Notification service) ---
APNS_KEY_ID    = os.environ.get("APNS_KEY_ID")
APNS_TEAM_ID   = os.environ.get("APNS_TEAM_ID")
APNS_BUNDLE_ID = os.environ.get("APNS_BUNDLE_ID")
APNS_KEY_PATH  = os.environ.get("APNS_KEY_PATH")

PUSH_VAPID_CLAIMS = {"sub": f"mailto:{PUSH_VAPID_EMAIL}"}

# --- STATUS SERVER / WEBHOOK ---
STATUS_URL   = "http://127.0.0.1:9000/status"
INVERTER_STATUS_URL = os.environ.get("INVERTER_STATUS_URL", "http://127.0.0.1:9000/invadcstatus")
# Stato sonde Kuma (check NodePing) — stesso webhook, autenticato con STATUS_TOKEN
PROBE_HEALTH_URL = os.environ.get("PROBE_HEALTH_URL", "http://127.0.0.1:9000/probe-health")

# --- Debounce sensori ---
# Numero di rilevamenti consecutivi oltre soglia prima di confermare critical
SENSOR_CRITICAL_DEBOUNCE = int(os.environ.get("SENSOR_CRITICAL_DEBOUNCE", "5"))

HTTP_TIMEOUT = 10


# ------------------------------------------------------------
# MONITOR UPTIME KUMA
# ------------------------------------------------------------

PROBE_BG       = "Bergamo Aruba"
PROBE_TIM      = "Sestu TIM"
PROBE_ILIAD    = "Sinnai ILIAD"
PROBE_NODEPING = "Europe NodePing"
PROBE_UPTIME   = "Uptime INVA"

KUMA1 = {
    "name": "Kuma Aruba Bergamo",
    "host": "monitor-bg.sundata.cloud",
    "slug": "inva",
}

KUMA2 = {
    "name": "Kuma TIM Sestu",
    "host": "kuma.sundata.cloud",
    "slug": "inva",
}

KUMA3 = {
    "name": "Kuma ILIAD Sinnai",
    "host": "monitor-iliad.sundata.cloud",
    "slug": "inva",
}

NODEPING = {
    "name": "NodePing",
    "host": "nodeping.com",
    "slug": "in.va.",
}

# ------------------------------------------------------------
# REDIS – STORICO CENTRALIZZATO
# ------------------------------------------------------------
# Storage condiviso tra tutti i client e aggiornato dal worker

REDIS_HOST = "127.0.0.1"
REDIS_PORT = 6379
REDIS_DB   = 0

# Massimo 60 punti (1 ora con worker/cron ogni 60 secondi, o 10 minuti con intervalli 10s)
MAX_HISTORY_POINTS = 60

# Frequenza di aggiornamento del worker in secondi
HISTORY_UPDATE_INTERVAL = 10

# Hiostory sleep time for workers
SLEEP = 60

# ------------------------------------------------------------
# PUSH NOTIFICATIONS
# ------------------------------------------------------------
PUSH_ENABLED = True

# Politica notifiche (D)
PUSH_NOTIFY_ON = {
    "final_down": True,      # rosso: entrambe le sonde rilevano DOWN
    "probe_mismatch": True,  # giallo: mismatch tra sonde
    "back_to_green": True   # verde: tutto OK (puoi abilitarlo se vuoi)
}

# Log file per le notifiche push (VAPID + APNs). Se vuoto, il log push è disabilitato.
PUSH_LOG_FILE = os.environ.get("PUSH_LOG_FILE", "")

# ------------------------------------------------------------
# EMAIL (SMTP) – RESET PASSWORD SELF-SERVICE
# ------------------------------------------------------------
# Tutti i valori arrivano da variabili d'ambiente (.env). Nessun segreto nel codice.
# I valori di SMTP_USERNAME / SMTP_PASSWORD non vengono mai loggati.

import logging as _logging

_config_logger = _logging.getLogger("kuma.config")


def _env_int(name: str, default: int, min_value: int, max_value: int) -> int:
    """Legge un intero da env nel range [min_value, max_value]; non valido -> default + WARNING."""
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError:
        value = None
    if value is None or not (min_value <= value <= max_value):
        _config_logger.warning(
            "%s non valido (atteso intero %d..%d): uso il default %d",
            name, min_value, max_value, default,
        )
        return default
    return value


def _env_smtp_port() -> int | None:
    """Porta SMTP: default 587; valore non valido -> None (mailer disabilitato)."""
    raw = os.environ.get("SMTP_PORT", "").strip()
    if not raw:
        return 587
    try:
        port = int(raw)
    except ValueError:
        port = None
    if port is None or not (1 <= port <= 65535):
        _config_logger.warning("SMTP_PORT non valido: invio email disabilitato")
        return None
    return port


def _env_public_base_url() -> str:
    """URL pubblico per i link nelle email: deve iniziare con https://."""
    url = os.environ.get("PUBLIC_BASE_URL", "").strip().rstrip("/")
    if url and not url.startswith("https://"):
        _config_logger.warning("PUBLIC_BASE_URL deve iniziare con https://: ignorato")
        return ""
    return url


SMTP_HOST     = os.environ.get("SMTP_HOST", "").strip()
SMTP_PORT     = _env_smtp_port()
SMTP_USERNAME = os.environ.get("SMTP_USERNAME", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
SMTP_FROM     = os.environ.get("SMTP_FROM", "").strip()
SMTP_STARTTLS = os.environ.get("SMTP_STARTTLS", "").strip().lower() in ("1", "true", "yes", "on")

# Durata del link di reset password (minuti, 1..1440)
PASSWORD_RESET_TOKEN_TTL_MINUTES = _env_int("PASSWORD_RESET_TOKEN_TTL_MINUTES", 30, 1, 1440)

# URL pubblico della dashboard (es. https://kuma-dashboard.example.com), senza slash finale
PUBLIC_BASE_URL = _env_public_base_url()

# Email admin per l'avviso di reset completato (vuota = avviso disattivato)
ADMIN_NOTIFY_EMAIL = os.environ.get("ADMIN_NOTIFY_EMAIL", "").strip()

# Numero di reverse proxy fidati davanti a gunicorn (ProxyFix x_for), 1..5
TRUSTED_PROXY_COUNT = _env_int("TRUSTED_PROXY_COUNT", 2, 1, 5)
