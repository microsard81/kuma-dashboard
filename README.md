# IN.VA Uptime Dashboard

Sistema di monitoraggio uptime multi-sonda con dashboard web (PWA) e app iOS nativa. Monitora lo stato dei servizi tramite cinque sonde indipendenti (Aruba Bergamo, TIM Sestu, ILIAD Sinnai, NodePing Europe, Uptime INVA) e invia notifiche push al cambio di stato globale.

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
- `u1` — Uptime INVA

**Stato globale:** `GREEN` (tutto UP) / `YELLOW` (mismatch tra sonde) / `RED` (DOWN su tutte le sonde)

---

## Backend Flask

### Requisiti

- Python 3.11+
- Redis 6+
- Virtualenv

### Installazione prerequisiti

**RHEL / CentOS / Rocky / AlmaLinux:**

```bash
# Python 3.11 e pip
sudo dnf install python3.11 python3.11-pip python3.11-devel

# Redis
sudo dnf install redis
sudo systemctl enable --now redis

# Virtualenv
pip3.11 install virtualenv
```

**Debian / Ubuntu:**

```bash
# Python 3.11 e pip
sudo apt update
sudo apt install python3.11 python3.11-venv python3.11-dev python3-pip

# Redis
sudo apt install redis-server
sudo systemctl enable --now redis-server

# Virtualenv (incluso in python3.11-venv)
```

**Verifica:**

```bash
python3.11 --version   # Python 3.11.x
redis-cli ping          # PONG
```

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
| `AUTH_PASSWORD_HASH` | — | (Legacy) Hash password utente singolo — migrato in Redis al primo avvio |
| `AUTH_TOTP_SECRET` | — | (Legacy) Segreto TOTP utente singolo — migrato in Redis al primo avvio |
| `AUTH_LEGACY_USERNAME` | — | Username per la migrazione legacy (default: `itcarmat`) |
| `APNS_KEY_ID` | ⚠️ | Key ID della chiave `.p8` Apple (per notifiche iOS) |
| `APNS_TEAM_ID` | ⚠️ | Team ID Apple Developer |
| `APNS_BUNDLE_ID` | ⚠️ | Bundle ID dell'app iOS |
| `APNS_KEY_PATH` | ⚠️ | Percorso assoluto al file `.p8` APNs |
| `WATCH_API_TOKEN` | — | Token statico per l'endpoint `/api/watch-data` (Apple Watch) |
| `BIOMETRIC_SECRET` | — | Segreto per firmare i token biometrici (default: `FLASK_SECRET_KEY`) |
| `PUSH_LOG_FILE` | — | Percorso file di log per le notifiche push VAPID e APNs (vuoto = disabilitato) |
| `REDIS_HOST` | — | Host Redis (default: `127.0.0.1`) |
| `REDIS_PORT` | — | Porta Redis (default: `6379`) |
| `REDIS_DB` | — | Database Redis (default: `0`) |

> ⚠️ Le variabili APNs sono opzionali se non si usa l'app iOS nativa. Se assenti, le notifiche APNs vengono silenziosamente saltate.

> Gli utenti sono ora gestiti in Redis tramite `manage_users.py`. Le variabili `AUTH_PASSWORD_HASH` e `AUTH_TOTP_SECRET` servono solo per la migrazione automatica dell'utente legacy al primo avvio. Possono essere rimosse dal `.env` dopo la migrazione.

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
auth.py                 # Autenticazione multi-utente con Redis
config.py               # Configurazione da variabili d'ambiente
history_worker.py       # Worker che aggiorna lo storico Redis e invia push
kuma_client.py          # Client per le API di Uptime Kuma
status_client.py        # Parsing degli stati dai webhook
push_utils.py           # Web Push VAPID (browser/PWA)
apns_utils.py           # APNs push (app iOS nativa)
redis_history.py        # Lettura/scrittura storico e stato globale su Redis
severity.py             # Calcolo severità e stato globale
manage_users.py         # CLI gestione utenti (add, remove, list, reset)
manage_push.py          # CLI gestione e test notifiche push (list, test, remove)
wsgi.py                 # Entry point WSGI per produzione
keys/                   # Chiavi .p8 APNs (non committare, solo deploy)
static/                 # Asset PWA (CSS, JS, immagini, manifest.json)
templates/              # Template Jinja2 (login, 2fa, dashboard, totp_setup, change_password)
```

### API endpoints

| Metodo | Path | Auth | Descrizione |
|---|---|---|---|
| `GET/POST` | `/login` | — | Login con username/password |
| `GET/POST` | `/2fa` | — | Verifica codice TOTP |
| `GET/POST` | `/change-password` | — | Cambio password obbligatorio (primo accesso / reset) |
| `GET/POST` | `/totp-setup` | — | Enrollment TOTP con QR code (primo accesso / reset) |
| `GET` | `/logout` | ✅ | Logout |
| `GET` | `/` | ✅ | Dashboard web |
| `GET` | `/api/dashboard-data` | ✅ | Dati dashboard in JSON |
| `POST` | `/api/login` | — | Login JSON (app iOS) |
| `POST` | `/api/2fa` | — | Verifica 2FA JSON (app iOS) |
| `POST` | `/api/change-password` | — | Cambio password JSON (app iOS) |
| `POST` | `/api/totp/enroll` | — | Enrollment TOTP JSON (app iOS) |
| `POST` | `/push/subscribe` | ✅ | Registra subscription Web Push (VAPID) |
| `POST` | `/push/unsubscribe` | ✅ | Rimuove subscription Web Push |
| `POST` | `/api/mac/apns/subscribe` | Token | Registra device token APNs dal Mac (header `X-Watch-Token`, supporta `bundle_id`) |
| `POST` | `/push/apns/subscribe` | ✅ | Registra device token APNs (iOS) |
| `POST` | `/push/apns/unsubscribe` | ✅ | Rimuove device token APNs (iOS) |
| `POST` | `/auth/biometric/login` | — | Login con token biometrico (Face ID / Touch ID) |
| `GET` | `/api/watch-data` | Token | Dati dashboard per Apple Watch (header `X-Watch-Token`) |

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
      "u1": "UP",
      "final": "UP",
      "severity": 1,
      "history": [
        {"s": 0, "k1": 1, "k2": 1, "k3": 1, "n1": 1, "u1": 1},
        {"s": 1, "k1": 1, "k2": 0, "k3": 1, "n1": 1, "u1": 1},
        {"s": 0, "k1": 1, "k2": 1, "k3": 1, "n1": 1, "u1": 1}
      ],
      "link": "https://example.com"
    }
  ],
  "global_state": "YELLOW",
  "timestamp": "2024-01-15T10:30:00"
}
```

> Lo storico usa la convenzione `0 = DOWN, 1 = UP` per ogni sonda. I punti vecchi (pre-migrazione) possono apparire come semplici interi. I punti nel formato a 5 campi (pre-sonda Uptime) avranno `u1: null`.

### Redis — schema chiavi

| Chiave | Tipo | Descrizione |
|---|---|---|
| `history:<nome_monitor>` | List | Storico severity (max 60 punti, formato `severity:k1:k2:k3:n1:u1`) |
| `global_state` | String | Stato globale corrente (`GREEN`/`YELLOW`/`RED`) |
| `push:subs_by_endpoint` | Hash | Subscription Web Push VAPID |
| `apns:subs_by_token` | Hash | Device token APNs iOS/Mac (con `bundle_id` opzionale per Mac) |
| `anomalous_resources` | Set | Nomi risorse anomale del ciclo corrente (per notifiche same-state) |
| `user:<username>` | Hash | Credenziali utente (`password_hash`, `totp_secret`, `totp_enrolled`, `must_change_password`, `password_history`) |
| `biometric:<username>:<token>` | String | Token biometrico con TTL 90 giorni |

### Gestione utenti

Gli utenti sono salvati in Redis. Usa lo script CLI per gestirli:

```bash
source /home/venvs/kuma-dashboard/bin/activate

# Aggiungi un utente (chiede password interattivamente)
python manage_users.py add <username>

# Lista utenti
python manage_users.py list

# Reset password (obbliga il cambio al prossimo login)
python manage_users.py reset-password <username>

# Reset TOTP (obbliga la riconfigurazione 2FA al prossimo login)
python manage_users.py reset-totp <username>

# Rimuovi utente
python manage_users.py remove <username>
```

**Flusso primo accesso di un nuovo utente:**
1. L'admin crea l'utente con `manage_users.py add`
2. L'admin comunica username e password temporanea all'utente
3. Al primo login, l'utente è obbligato a cambiare la password
4. Dopo il cambio password, viene mostrata la schermata di setup 2FA con QR code
5. L'utente scansiona il QR con la sua app authenticator e verifica il codice
6. Dai login successivi: username + password + codice TOTP

> Il TOTP secret non viene mai mostrato nel terminale dell'admin — è visibile solo all'utente durante l'enrollment in-app/PWA.

> Requisiti password: almeno 8 caratteri, una maiuscola, una minuscola, un numero e un carattere speciale. Le ultime 5 password non possono essere riutilizzate (il reset da CLI azzera lo storico).

> Al primo avvio, se le variabili `AUTH_PASSWORD_HASH` e `AUTH_TOTP_SECRET` sono presenti in `.env`, l'utente legacy viene migrato automaticamente in Redis come già enrolled.

### Gestione notifiche push

Usa `manage_push.py` per ispezionare le subscription registrate e inviare notifiche di test:

```bash
source /home/venvs/kuma-dashboard/bin/activate

# Lista tutti i dispositivi registrati (VAPID + APNs)
python manage_push.py list

# Solo VAPID (browser/PWA) — mostra tipo dispositivo (Android, Safari, Firefox, Edge)
python manage_push.py list vapid

# Solo APNs (iOS/Mac) — mostra token, environment, bundle ID
python manage_push.py list apns

# Invia push di test a tutti i dispositivi
python manage_push.py test

# Solo a browser/PWA
python manage_push.py test vapid

# Solo a iOS/Mac
python manage_push.py test apns

# Rimuovi una subscription VAPID per endpoint (parziale)
python manage_push.py remove "cntZoPZq4oA"

# Rimuovi una subscription APNs per token (parziale)
python manage_push.py remove-apns "a70b5d1f"
```

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

Bugfix Mac push notifications:
- **Bug Condition** — `send_apns_to_all()` usa il `bundle_id` per-subscription come `apns-topic`; `add_apns_subscription()` accetta `bundle_id`
- **Preservation** — Round-trip iOS senza `bundle_id`, header `apns-topic` iOS invariato, cleanup token invalidi invariato

Bugfix same-state notifications:
- **Bug Condition** — YELLOW→YELLOW e RED→RED con nuove risorse anomale inviano notifica
- **Preservation** — Transizioni GREEN↔YELLOW↔RED, primo avvio, push disabilitate, GREEN→GREEN invariati

Sonda Uptime (u1) — 7 proprietà di correttezza:
- **P1** — Round-trip storico 6 campi (save_point → load_history)
- **P2** — Retrocompatibilità formato 5 campi (u1 = None)
- **P3** — Retrocompatibilità formato 1 campo (tutte le sonde = None)
- **P4** — Severity mismatch con 5 sonde
- **P5** — Compatibilità severity con sonda UP aggiuntiva
- **P6** — Stato finale con 5 sonde (DOWN solo se tutte DOWN)
- **P7** — Notifiche push includono sonda Uptime

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
│   └── SettingsViewModel.swift     # Tema, ordinamento, refresh, notifiche, biometria — persistenza UserDefaults
├── Views/
│   ├── SplashView.swift            # Splash screen animata all'avvio
│   ├── LoginView.swift             # Form login con "Ricordami"
│   ├── ChangePasswordView.swift    # Cambio password obbligatorio (primo accesso / reset)
│   ├── TOTPSetupView.swift         # Enrollment TOTP con QR code
│   ├── TwoFAView.swift             # Input TOTP con autocompletamento SMS
│   ├── BiometricGateView.swift     # Gate Face ID / Touch ID per sessioni salvate
│   ├── DashboardView.swift         # Lista monitor, LED, badge, filtro DOWN, raggruppamento per stato
│   ├── SettingsView.swift          # Menu impostazioni (tema, ordinamento, refresh, notifiche, biometria, info)
│   └── SparklineView.swift         # Barre colorate con effetto fisheye e haptic feedback
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
- **Cambio password obbligatorio** — al primo accesso o dopo reset da parte dell'admin
- **Enrollment TOTP** — configurazione 2FA con QR code al primo accesso o dopo reset
- **Biometria** — accesso rapido con Face ID / Touch ID quando c'è una sessione salvata nel Keychain
- **Dashboard** — lista monitor con stato per sonda, colore riga, sparkline storico, raggruppamento per stato (DOWN/Mismatch/UP)
- **Auto-refresh** — aggiornamento automatico configurabile (default 60s)
- **Filtro DOWN** — toggle per mostrare solo i monitor in stato DOWN o mismatch
- **LED globale** — indicatore colorato nella navbar che riflette lo stato globale
- **Sparkline** — barre colorate con effetto fisheye (stile Dock macOS) e haptic feedback durante lo scrubbing; orario e stato del campione mostrati nella riga delle sonde; dettaglio per-sonda su campioni mismatch
- **Badge icona app** — numero di risorse con problemi mostrato sull'icona dell'app (disattivabile)
- **Notifiche push** — notifiche native APNs al cambio di stato globale con dettaglio risorse e sonde
- **Impostazioni** — tema (dark default/chiaro/auto), ordinamento, intervallo auto-refresh, notifiche, biometria, haptic feedback, badge, info app
- **Tema dark** — sfondo #141c2b (come splash screen), default all'installazione
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

## App macOS

App nativa macOS (SwiftUI) con le stesse funzionalità dell'app iPad.

### Funzionalità

- Login con supporto 1Password (`.textContentType`)
- "Ricordami" con cookie persistiti in UserDefaults
- Cambio password obbligatorio e TOTP enrollment con QR code
- Dashboard con sparkline, sonde colorate, raggruppamento per stato
- Hover sulle sparkline mostra orario e stato; su mismatch evidenzia le sonde DOWN
- Auto-refresh configurabile (10s/30s/60s/disabilitato)
- Ordinamento: per gravità, alfabetico, per stato globale
- Badge Dock con contatore risorse DOWN/mismatch (disattivabile)
- Notifiche push APNs native
- Tema: Auto/Chiaro/Scuro (default Scuro con sfondo #141c2b)
- Dimensione testo regolabile (80%-160%)
- La X minimizza nel Dock invece di chiudere l'app
- Widget macOS (small/medium/large) con stato servizi, LED globale, 5 pallini sonde per monitor

### Setup

1. In Xcode: File → New → Target → macOS → App → "UptimeDashboardMac"
2. Aggiungi i file Swift dalla cartella `UptimeDashboardMac/` al target
3. Signing & Capabilities: aggiungi Push Notifications e App Sandbox (Outgoing Connections)
4. Genera `WATCH_API_TOKEN` e aggiungilo al `.env` del server
5. In Xcode, target UptimeDashboardMac → Build Settings → User-Defined → aggiungi `WATCH_API_TOKEN` con il valore del token (l'Info.plist lo referenzia come `$(WATCH_API_TOKEN)`)
6. L'environment APNs viene rilevato automaticamente: `development` per build Xcode, `production` per release

### Struttura

```
UptimeDashboardMac/
├── UptimeDashboardMacApp.swift     # @main, AppDelegate, gestione finestra
├── MacAppViewModel.swift           # Auth, fetch, preferenze, badge Dock
├── MacRootView.swift               # Router per stato auth
├── MacLoginView.swift              # Login con 1Password
├── MacChangePasswordView.swift     # Cambio password obbligatorio
├── MacTOTPSetupView.swift          # Enrollment TOTP con QR code
├── MacTwoFAView.swift              # Verifica 2FA
├── MacDashboardView.swift          # Dashboard con sparkline e sonde
├── MacSettingsView.swift           # Impostazioni (Cmd+,)
└── TextScaleModifier.swift         # Font scalati custom
```

---

## App Apple Watch

App companion watchOS che mostra lo stato dei servizi con card compatte. Funziona indipendentemente dall'iPhone tramite fetch diretto all'API.

### Funzionalità

- Lista servizi con stato finale e sonde (Aruba, TIM, ILIAD, NodePing, Uptime)
- Raggruppamento per stato (DOWN / Mismatch / UP)
- Colore sonde verde/rosso per identificare subito i problemi
- LED globale nella toolbar
- Refresh automatico ogni 60 secondi + refresh manuale
- Aggiornamento immediato quando l'app torna in primo piano
- Dati cached tra i riavvii via WatchConnectivity
- Notifiche push APNs (arrivano sul watch quando l'iPhone è bloccato)

### Setup

1. In Xcode: File → New → Target → watchOS → App → "UptimeDashboardWatch"
2. Aggiungi i file Swift dalla cartella `UptimeDashboardWatch Watch App/` al target watch
3. Nel tab Info del target watch, aggiungi:
   - `BACKEND_BASE_URL`: URL del backend (es. `https://kuma-dashboard.sundata.cloud`)
   - `WATCH_API_TOKEN`: lo stesso token presente nel `.env` del server
4. Genera il token: `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`
5. Aggiungi `WATCH_API_TOKEN=<token>` al `.env` del server e riavvia

---

## Notifiche Push

Il sistema supporta due canali di notifica paralleli:

### Web Push (VAPID) — browser/PWA
- Gestito da `push_utils.py`
- Subscription salvate in Redis sotto `push:subs_by_endpoint`
- Compatibile con Chrome, Firefox, Safari (WebKit), Edge

### APNs — app iOS e macOS nativa
- Gestito da `apns_utils.py`
- Richiede chiave `.p8` Apple Developer, Key ID e Team ID
- Subscription salvate in Redis sotto `apns:subs_by_token`
- JWT firmato con ES256, richieste HTTP/2 ad `api.push.apple.com` (production) o `api.sandbox.push.apple.com` (development/sandbox)
- Supporto per-subscription `bundle_id`: l'app Mac invia il proprio bundle ID, usato come `apns-topic` header; le subscription iOS senza `bundle_id` usano `APNS_BUNDLE_ID` di default
- Environment detection automatico: `development` per build Xcode, `production` per App Store/TestFlight
- Token non validi (410 / `BadDeviceToken`) rimossi automaticamente
- Retry con backoff esponenziale (1s, 2s, 4s) per la registrazione del token dal client Mac

### Log notifiche push

Se `PUSH_LOG_FILE` è impostato nel `.env`, ogni notifica inviata (VAPID e APNs) viene loggata su file con timestamp, destinatario, titolo, corpo e esito:

```
PUSH_LOG_FILE=/var/log/kuma-dashboard/push.log
```

Formato:
```
[2026-04-17 09:39:25,755] APNs OK → a70b5d1f30defa45... | env=sandbox | title=🟡 Incongruenza tra sonde | body=INVA - www.regione.vda.it — DOWN su TIM
[2026-04-17 09:39:24,691] VAPID OK → https://fcm.googleapis.com/fcm/send/... | title=🟡 Incongruenza tra sonde
```

Le notifiche vengono inviate da `history_worker.py` alle transizioni di stato, con dettaglio delle risorse coinvolte:

- 🔴 `GREEN → RED` — "Servizi DOWN" + elenco risorse DOWN con sonde specifiche e orario
- 🔴 `RED → RED` (nuove risorse) — "Nuova risorsa DOWN" + solo le risorse appena entrate in stato DOWN
- 🟡 `* → YELLOW` — "Incongruenza tra sonde" + elenco risorse in mismatch con sonde DOWN e orario
- 🟡 `YELLOW → YELLOW` (nuove risorse) — "Nuova incongruenza" + solo le risorse appena entrate in mismatch
- 🟢 `RED/YELLOW → GREEN` — "Tutto OK" + conferma ripristino con orario

> La notifica GREEN non include il campo `badge` nel payload APNs: questo evita che iOS cancelli automaticamente le notifiche precedenti dal centro notifiche. Il badge viene azzerato dall'app quando l'utente la apre e vede che è tutto verde.

Esempio notifica mismatch:
```
🟡 Incongruenza tra sonde
INVA - www.regione.vda.it — DOWN su NodePing
Ore 14:32
```

---

## Sicurezza

- Sessioni Flask con cookie `HttpOnly`, `Secure`, `SameSite=Lax`
- Password hashata con bcrypt (werkzeug), salvata in Redis
- Cambio password obbligatorio al primo accesso e dopo reset
- Validazione complessità password: minimo 8 caratteri, maiuscola, minuscola, numero, carattere speciale
- Storico ultime 5 password: l'utente non può riutilizzarle (azzerato solo da reset admin)
- 2FA TOTP obbligatorio con enrollment in-app (QR code mai esposto all'admin)
- Autenticazione multi-utente con credenziali in Redis (namespace `user:`)
- Token biometrici firmati con HMAC-SHA256, salvati in Redis con TTL 90 giorni
- Session token iOS conservato nel Keychain con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Comunicazione backend esclusivamente via HTTPS (validata lato app)
- Credenziali e token mai scritti nei log
- Namespace Redis separati per VAPID (`push:`), APNs (`apns:`), utenti (`user:`), biometria (`biometric:`)
- Endpoint protetti da `@login_required`
