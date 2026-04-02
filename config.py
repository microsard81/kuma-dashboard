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

PUSH_VAPID_CLAIMS = {"sub": f"mailto:{PUSH_VAPID_EMAIL}"}

# --- STATUS SERVER / WEBHOOK ---
STATUS_URL   = "http://127.0.0.1:9000/status"

HTTP_TIMEOUT = 10


# ------------------------------------------------------------
# MONITOR UPTIME KUMA
# ------------------------------------------------------------

PROBE_BG       = "Bergamo Aruba"
PROBE_TIM      = "Sestu TIM"
PROBE_ILIAD    = "Sinnai ILIAD"
PROBE_NODEPING = "Europe NodePing"

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
MAX_HISTORY_POINTS = 120

# Frequenza di aggiornamento del worker in secondi
HISTORY_UPDATE_INTERVAL = 10

# Hiostory sleep time for workers
SLEEP = 30

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
