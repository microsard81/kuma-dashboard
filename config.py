# ------------------------------------------------------------
# CONFIGURAZIONE KUMA DASHBOARD – VERSIONE COMPLETA (TUO + REDIS)
# ------------------------------------------------------------

# --- STATUS SERVER / WEBHOOK ---
STATUS_TOKEN = "755caf624e23e696e05626c402a295e5c771e5f30a79905db7b936ba16952fd557e2a53bb78f24569a81a1a94e4323c9135d2ba4ace2d508e791ee8b1ca8f277"
STATUS_URL   = "http://127.0.0.1:9000/status"

HTTP_TIMEOUT = 10


# ------------------------------------------------------------
# MONITOR UPTIME KUMA
# ------------------------------------------------------------
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


# ------------------------------------------------------------
# PUSH NOTIFICATIONS
# ------------------------------------------------------------
PUSH_ENABLED = True

# Chiavi VAPID tue (correttamente mantenute)
PUSH_VAPID_PUBLIC_KEY  = "BGZBtqdMDzXvqH7x9UWfYU_UqxhTksx4CQuWkVdtZCnmKpN7GhOKGhYGzPlYeNYa-CJEX1DN8hfDyCKBHSZcaWA"
PUSH_VAPID_PRIVATE_KEY = "sV9DQYj-KG8V8vTAouH1KTaXmnYY4YELChvx3scmkTk"

# Claim richiesto da WebPush
PUSH_VAPID_CLAIMS = {
    "sub": "mailto:assistenza@itcarmat.net"
}

# Politica notifiche (D)
PUSH_NOTIFY_ON = {
    "final_down": True,      # rosso: entrambe le sonde rilevano DOWN
    "probe_mismatch": True,  # giallo: mismatch tra sonde
    "back_to_green": True   # verde: tutto OK (puoi abilitarlo se vuoi)
}