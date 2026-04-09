# IN.VA Uptime Dashboard

Sistema di monitoraggio uptime multi-sonda con dashboard web (PWA) e app iOS nativa. Monitora lo stato dei servizi tramite quattro sonde indipendenti (Aruba Bergamo, TIM Sestu, ILIAD Sinnai, NodePing Europe) e invia notifiche push al cambio di stato globale.

## Architettura

```
┌─────────────────────────────────────────────────────────┐
│  App iOS (Swift + SwiftUI)   │   PWA (browser)          │
│  UptimeDashboard/            │   templates/dashboard.html│
└──────────────────┬───────────┴───────────────────────────┘
                   │ HTTPS
┌──────────────────▼───────────────────────────────────────┐
│              Flask Backend (app.py)                       │
│  /login  /2fa  /logout  /api/dashboard-data              │
│  /push/subscribe  /push/apns/subscribe  ...              │
└──────┬───────────────────┬────────────────────────────────┘
       │                   │
┌──────▼──────┐   ┌────────▼────────┐
│    Redis    │   │  Uptime Kuma    │
│  (storico) │   │  (3 istanze)    │
└─────────────┘   └─────────────────┘
```

**Sonde:**
- `k1` — Aruba Bergamo
- `k2` — TIM Sestu
- `k3` — ILIAD Sinnai
- `n1` — NodePing Europe

**Stato globale:** `GREEN` (tutto UP) / `YELLOW` (mismatch tra sonde) / `RED` (DOWN su tutte le sonde)

---

## Backend Flask

### Requisiti

- Python 3.11+
- Redis 6+
- Virtualenv

### Setup

```bash
# Clona il repo e crea il virtualenv
python3 -m venv /home/venvs/kuma-dashboard
source /home/venvs/kuma-dashboard/bin/activate

# Installa le dipendenze
pip install flask flask-login pyotp werkzeug redis pywebpush \
            PyJWT httpx[http2] python-dotenv

# Copia e compila le variabili d'ambiente
cp .env.example .env
# Modifica .env con i valori reali (vedi sezione Variabili d'ambiente)
```

### Variabili d'ambiente

Copia `.env.example` in `.env` e compila tutti i campi:

| Variabile | Obbligatoria | Descrizione |
|---|---|---|
| `FLASK_SECRET_KEY` | ✅ | Chiave segreta Flask per le sessioni |
| `STATUS_TOKEN` | ✅ | Token per l'endpoint `/status` di Uptime Kuma |
| `PUSH_VAPID_PUBLIC_KEY` | ✅ | Chiave pubblica VAPID per Web Push |
| `PUSH_VAPID_PRIVATE_KEY` | ✅ | Chiave privata VAPID per Web Push |
| `PUSH_VAPID_EMAIL` | ✅ | Email per i VAPID claims |
| `AUTH_PASSWORD_HASH` | ✅ | Hash bcrypt della password (generato con `werkzeug`) |
| `AUTH_TOTP_SECRET` | ✅ | Segreto TOTP base32 per il 2FA |
| `APNS_KEY_ID` | ⚠️ | Key ID della chiave `.p8` Apple (per notifiche iOS) |
| `APNS_TEAM_ID` | ⚠️ | Team ID Apple Developer |
| `APNS_BUNDLE_ID` | ⚠️ | Bundle ID dell'app iOS |
| `APNS_KEY_PATH` | ⚠️ | Percorso assoluto al file `.p8` APNs |
| `BIOMETRIC_SECRET` | — | Segreto per firmare i token biometrici (default: `FLASK_SECRET_KEY`) |
| `REDIS_HOST` | — | Host Redis (default: `127.0.0.1`) |
| `REDIS_PORT` | — | Porta Redis (default: `6379`) |
| `REDIS_DB` | — | Database Redis (default: `0`) |

> ⚠️ Le variabili APNs sono opzionali se non si usa l'app iOS nativa. Se assenti, le notifiche APNs vengono silenziosamente saltate.

**Generare `AUTH_PASSWORD_HASH`:**
```python
from werkzeug.security import generate_password_hash
print(generate_password_hash("la-tua-password"))
```

**Generare `AUTH_TOTP_SECRET`:**
```python
import pyotp
print(pyotp.random_base32())
```

### Avvio

```bash
# Sviluppo
source /home/venvs/kuma-dashboard/bin/activate
python app.py

# Produzione (con gunicorn/wsgi)
gunicorn -w 2 -b 127.0.0.1:5000 wsgi:app

# Worker storico (processo separato, da tenere sempre attivo)
python history_worker.py
```

### Struttura file backend

```
app.py                  # Flask app — routing, autenticazione, API
auth.py                 # Verifica password e TOTP
config.py               # Configurazione da variabili d'ambiente
history_worker.py       # Worker che aggiorna lo storico Redis e invia push
kuma_client.py          # Client per le API di Uptime Kuma
status_client.py        # Parsing degli stati dai webhook
push_utils.py           # Web Push VAPID (browser/PWA)
apns_utils.py           # APNs push (app iOS nativa)
redis_history.py        # Lettura/scrittura storico e stato globale su Redis
severity.py             # Calcolo severità e stato globale
wsgi.py                 # Entry point WSGI per produzione
send_test_push.py       # Invio manuale notifica Web Push di test
test_push.py            # Debug Web Push con log dettagliato per endpoint
keys/                   # Chiavi .p8 APNs (non committare, solo deploy)
static/                 # Asset PWA (CSS, JS, immagini, manifest.json)
templates/              # Template Jinja2 (login.html, 2fa.html, dashboard.html)
```

### API endpoints

| Metodo | Path | Auth | Descrizione |
|---|---|---|---|
| `GET/POST` | `/login` | — | Login con username/password |
| `GET/POST` | `/2fa` | — | Verifica codice TOTP |
| `GET` | `/logout` | ✅ | Logout |
| `GET` | `/` | ✅ | Dashboard web |
| `GET` | `/api/dashboard-data` | ✅ | Dati dashboard in JSON |
| `POST` | `/push/subscribe` | ✅ | Registra subscription Web Push (VAPID) |
| `POST` | `/push/unsubscribe` | ✅ | Rimuove subscription Web Push |
| `POST` | `/push/apns/subscribe` | ✅ | Registra device token APNs (iOS) |
| `POST` | `/push/apns/unsubscribe` | ✅ | Rimuove device token APNs (iOS) |

**Formato risposta `/api/dashboard-data`:**
```json
{
  "items": [
    {
      "name": "Nome Servizio",
      "k1": "UP",
      "k2": "DOWN",
      "k3": "UP",
      "n1": "UP",
      "final": "UP",
      "severity": 1,
      "history": [0, 0, 1, 2, 0],
      "link": "https://example.com"
    }
  ],
  "global_state": "YELLOW",
  "timestamp": "2024-01-15T10:30:00"
}
```

### Redis — schema chiavi

| Chiave | Tipo | Descrizione |
|---|---|---|
| `history:<nome_monitor>` | List | Storico severity (max 60 punti) |
| `global_state` | String | Stato globale corrente (`GREEN`/`YELLOW`/`RED`) |
| `push:subs_by_endpoint` | Hash | Subscription Web Push VAPID |
| `apns:subs_by_token` | Hash | Device token APNs iOS |

### Test backend

```bash
source /home/venvs/kuma-dashboard/bin/activate
pip install pytest hypothesis fakeredis

# Esegui tutti i test
python -m pytest tests/ -v

# Solo i test APNs
python -m pytest tests/test_apns_utils.py tests/test_apns_endpoints.py -v
```

I test coprono 5 proprietà di correttezza verificate con Hypothesis (property-based testing):
- **P13** — Round-trip subscribe/unsubscribe APNs in Redis
- **P14** — Validazione payload: HTTP 400 senza `device_token`
- **P15** — `send_apns_to_all` chiama esattamente N volte per N token registrati
- **P16** — Rimozione automatica token non validi (status 410 / `BadDeviceToken`)
- **P17** — Separazione namespace Redis `apns:` vs `push:`

---

## App iOS

App nativa Swift + SwiftUI (iOS 16+) che replica la dashboard web con notifiche push native via APNs.

### Requisiti

- Xcode 15+
- iOS 16+ (target)
- Account Apple Developer (per Push Notifications)

### Setup Xcode

1. Apri `UptimeDashboard/UptimeDashboard.xcodeproj` in Xcode
2. Imposta il **Bundle Identifier** uguale al valore di `APNS_BUNDLE_ID`
3. Abilita le capability nel target:
   - **Signing & Capabilities → Push Notifications**
   - **Signing & Capabilities → Background Modes → Remote notifications**
4. Modifica `UptimeDashboard/Info.plist` — imposta `BACKEND_BASE_URL` con l'URL del tuo backend (deve usare `https://`)
5. (Opzionale) Aggiungi SwiftCheck via Swift Package Manager per i test property-based:
   - URL: `https://github.com/typelift/SwiftCheck`

### Struttura app iOS

```
UptimeDashboard/
├── UptimeDashboardApp.swift        # @main, AppDelegate, navigazione root
├── Info.plist                      # BACKEND_BASE_URL, background modes
├── Models/
│   └── DashboardModels.swift       # MonitorItem, GlobalState, SparklineSegment, ...
├── ViewModels/
│   ├── AuthViewModel.swift         # Login, 2FA, logout, session expiry
│   ├── DashboardViewModel.swift    # Fetch, auto-refresh, filtro, ordinamento
│   └── SettingsViewModel.swift     # Tema chiaro/scuro/auto, persistenza
├── Views/
│   ├── SplashView.swift            # Splash screen animata all'avvio
│   ├── LoginView.swift             # Form login con "Ricordami"
│   ├── TwoFAView.swift             # Input TOTP con autocompletamento SMS
│   ├── BiometricGateView.swift     # Gate Face ID / Touch ID per sessioni salvate
│   ├── DashboardView.swift         # Lista monitor, LED, badge, filtro DOWN
│   └── SparklineView.swift         # Barre colorate con tooltip al tap
├── Services/
│   ├── NetworkClient.swift         # URLSession, cookie Flask, tutti gli endpoint
│   ├── KeychainStore.swift         # Archiviazione sicura session token
│   └── NotificationManager.swift  # APNs, permessi, token lifecycle
└── Utils/
    └── Config.swift                # AppConfig.baseURL con validazione https://

UptimeDashboardTests/
├── MonitorItemTests.swift          # P3 (rowColor), P5 (field mapping)
├── SparklineTests.swift            # P7 (troncamento 60pt), P8 (colori)
├── KeychainStoreTests.swift        # P1 (round-trip Keychain)
├── NetworkClientTests.swift        # P12 (payload APNs), P18 (HTTPS validation)
├── AuthViewModelTests.swift        # P2 (whitespace validation)
├── DashboardViewModelTests.swift   # P4 (sort), P6 (LED/badge), P9 (filtro DOWN)
├── ThemeModeTests.swift            # P10 (ciclo tema)
├── SettingsViewModelTests.swift    # P11 (persistenza tema)
└── NotificationManagerTests.swift  # test unitari APNs
```

### Funzionalità

- **Splash screen** — schermata animata all'avvio con logo
- **Autenticazione** — login username/password + TOTP 2FA, "Ricordami" con session token nel Keychain
- **Biometria** — accesso rapido con Face ID / Touch ID quando c'è una sessione salvata nel Keychain
- **Dashboard** — lista monitor con stato per sonda (k1/k2/k3/n1), colore riga, sparkline storico
- **Auto-refresh** — aggiornamento automatico ogni 10 secondi in foreground
- **Filtro DOWN** — toggle per mostrare solo i monitor in stato DOWN
- **LED globale** — indicatore colorato nella navbar che riflette lo stato globale
- **Sparkline** — barre colorate (verde/giallo/rosso) con tooltip al tap
- **Notifiche push** — notifiche native APNs al cambio di stato globale
- **Tema** — chiaro / scuro / automatico (segue iOS), persistito tra i riavvii
- **Logout** — con conferma, elimina il token dal Keychain

### Test iOS

Esegui i test da Xcode con `Cmd+U` oppure da CLI:

```bash
xcodebuild test \
  -project UptimeDashboard/UptimeDashboard.xcodeproj \
  -scheme UptimeDashboard \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

I test coprono 18 proprietà di correttezza (100 iterazioni ciascuna):

| Proprietà | File | Requisiti |
|---|---|---|
| P1: Round-trip Keychain | `KeychainStoreTests` | 1.5, 2.4, 12.1 |
| P2: Validazione whitespace | `AuthViewModelTests` | 1.7 |
| P3: Codifica cromatica righe | `MonitorItemTests` | 3.3 |
| P4: Ordinamento per severità | `DashboardViewModelTests` | 3.4 |
| P5: Mapping campi monitor | `MonitorItemTests` | 3.2 |
| P6: LED globale e badge DOWN | `DashboardViewModelTests` | 4.1, 4.2, 4.4 |
| P7: Troncamento sparkline 60pt | `SparklineTests` | 5.1, 5.3 |
| P8: Colori sparkline | `SparklineTests` | 5.2 |
| P9: Filtro "Solo DOWN" | `DashboardViewModelTests` | 7.2, 7.3 |
| P10: Ciclo tema deterministico | `ThemeModeTests` | 8.2 |
| P11: Round-trip persistenza tema | `SettingsViewModelTests` | 8.3 |
| P12: Payload subscribe APNs | `NetworkClientTests` | 9.2 |
| P18: Validazione schema HTTPS | `NetworkClientTests` | 12.3, 12.4 |

---

## Notifiche Push

Il sistema supporta due canali di notifica paralleli:

### Web Push (VAPID) — browser/PWA
- Gestito da `push_utils.py`
- Subscription salvate in Redis sotto `push:subs_by_endpoint`
- Compatibile con Chrome, Firefox, Safari (WebKit), Edge

### APNs — app iOS nativa
- Gestito da `apns_utils.py`
- Richiede chiave `.p8` Apple Developer, Key ID e Team ID
- Subscription salvate in Redis sotto `apns:subs_by_token`
- JWT firmato con ES256, richieste HTTP/2 ad `api.push.apple.com`
- Token non validi (410 / `BadDeviceToken`) rimossi automaticamente

Le notifiche vengono inviate da `history_worker.py` alle transizioni di stato:
- 🔴 `GREEN → RED` — "Servizi DOWN"
- 🟡 `* → YELLOW` — "Incongruenza tra sonde"
- 🟢 `RED/YELLOW → GREEN` — "Tutto OK"

---

## Sicurezza

- Sessioni Flask con cookie `HttpOnly`, `Secure`, `SameSite=Lax`
- Password hashata con bcrypt (werkzeug)
- 2FA TOTP obbligatorio
- Session token iOS conservato nel Keychain con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Comunicazione backend esclusivamente via HTTPS (validata lato app)
- Credenziali e token mai scritti nei log
- Namespace Redis separati per VAPID (`push:`) e APNs (`apns:`)
- Endpoint APNs protetti da `@login_required`
