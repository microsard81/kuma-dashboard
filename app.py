from flask import (
    Flask,
    render_template,
    request,
    redirect,
    url_for,
    session,
    send_from_directory,
    jsonify,
    abort,
)
from flask_login import (
    LoginManager,
    login_user,
    logout_user,
    login_required,
    UserMixin,
    current_user,
)
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import logging

from werkzeug.middleware.proxy_fix import ProxyFix

from kuma_client import load_monitors
from status_client import load_status, process_monitor
from sensor_client import fetch_inverter_data
from auth import verify_user, verify_totp, is_totp_enrolled, get_totp_secret, enroll_totp, must_change_password, change_password, validate_password_complexity, PasswordValidationError
from auth import (
    get_session_epoch,
    validate_new_password,
    is_valid_username,
    get_user_email,
    RESET_TOKEN_RE,
    create_password_reset_token,
    peek_reset_token,
    consume_reset_token,
    complete_password_reset,
)
import rate_limit
import mailer
from severity import compute_global_state, validate_threshold
from config import (
    FLASK_SECRET_KEY,
    KUMA1,
    KUMA2,
    KUMA3,
    NODEPING,
    PUSH_ENABLED,
    PUSH_VAPID_PUBLIC_KEY,
    BIOMETRIC_SECRET,
    WATCH_API_TOKEN,
    REDIS_HOST,
    REDIS_PORT,
    REDIS_DB,
    PUBLIC_BASE_URL,
    TRUSTED_PROXY_COUNT,
)
from push_utils import (
    add_subscription,
    remove_subscription,
)
from apns_utils import (
    add_apns_subscription,
    remove_apns_subscription,
)
import json
import os, random, secrets, hmac, hashlib, time
import redis as redis_lib

# Logging applicativo (stderr -> journal). Mai password, codici TOTP, token o email.
logging.basicConfig(level=logging.WARNING, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("kuma.security")
logger.setLevel(logging.INFO)
logging.getLogger("kuma.mailer").setLevel(logging.INFO)

app = Flask(__name__)
app.secret_key = FLASK_SECRET_KEY

# IP reale del client: catena upstream proxy -> Apache -> gunicorn
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=TRUSTED_PROXY_COUNT, x_proto=1, x_host=1)

# Sicurezza cookie di sessione
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SECURE"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

# Remember me durata 30 giorni
app.config["REMEMBER_COOKIE_DURATION"] = timedelta(days=30)

_redis = redis_lib.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)

login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = "login"


# ============================================================================
# MODELLO UTENTE
# ============================================================================
class User(UserMixin):
    def __init__(self, username: str, epoch: int = 0):
        self.id = username
        self.epoch = epoch

    def get_id(self):
        # L'epoch finisce in sessione e nel remember cookie: incrementarlo revoca tutto
        return f"{self.id}:{self.epoch}"


@login_manager.user_loader
def load_user(uid):
    username, sep, ep = uid.rpartition(":")
    if not sep or not ep.isdigit() or len(ep) > 9:
        # Sessione legacy senza epoch
        username, claimed = uid, None
    else:
        claimed = int(ep)

    try:
        current = get_session_epoch(username)
    except (redis_lib.RedisError, ValueError):
        logger.error("user_loader: verifica sessione non disponibile")
        abort(503)

    if current is None:
        return None
    if claimed is None:
        # Legacy accettata solo finché l'utente non ha mai fatto un reset
        return User(username, 0) if current == 0 else None
    if claimed != current:
        return None
    return User(username, current)


# ============================================================================
# HEADER DI SICUREZZA ED ERRORI
# ============================================================================
@app.after_request
def _security_headers(response):
    if request.endpoint in ("forgot_password", "reset_password"):
        # Pagine di reset: niente JS, niente referrer (il token è nella URL), niente cache
        response.headers["Content-Security-Policy"] = _RESET_PAGE_CSP
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers.setdefault("Strict-Transport-Security", "max-age=31536000")
    return response


@app.errorhandler(503)
def _service_unavailable(_e):
    if request.path.startswith(("/api/", "/auth/", "/push/")):
        return {"ok": False, "error": "service unavailable"}, 503
    return (
        "Servizio temporaneamente non disponibile, riprova più tardi.",
        503,
        {"Content-Type": "text/plain; charset=utf-8"},
    )


# ============================================================================
# HELPER AUTENTICAZIONE
# ============================================================================
_RATE_LIMIT_MSG = "Troppi tentativi, riprova più tardi."
_RESET_REQUEST_MSG = "Se l'account esiste ed ha un'email associata, riceverai un link a breve."
_RESET_PAGE_CSP = (
    "default-src 'none'; style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
    "img-src 'self' data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
)


def _log_safe(s) -> str:
    """Valore sicuro per i log: troncato a 64 caratteri, senza caratteri di controllo."""
    text = str(s)[:64]
    return "".join(c if c.isprintable() else "?" for c in text)


def _client_ip() -> str:
    return request.remote_addr or ""


def _clear_pending() -> None:
    for k in ("pending_user", "pending_epoch", "2fa_pending", "totp_setup_pending",
              "password_change_pending", "remember_choice"):
        session.pop(k, None)


def _get_pending_user(flag: str) -> str | None:
    username = session.get("pending_user")
    if not username or not session.get(flag):
        return None                      # nessuna pulizia: lo stato resta valido per il suo step
    try:
        current = get_session_epoch(username)
    except (redis_lib.RedisError, ValueError):
        logger.error("pending session: verifica non disponibile")
        abort(503)
    if current is None or session.get("pending_epoch", 0) != current:
        _clear_pending()                 # pulizia solo su epoch non valido o utente rimosso
        return None
    return username


def _start_pending(username: str, remember: bool | None = None) -> None:
    """Dopo una password corretta: ripulisce i tentativi precedenti e apre il flusso pending.
    remember=None (API) non imposta remember_choice, come prima."""
    _clear_pending()
    try:
        epoch = get_session_epoch(username)
    except (redis_lib.RedisError, ValueError):
        logger.error("pending session: verifica non disponibile")
        abort(503)
    session["pending_user"] = username
    session["pending_epoch"] = epoch or 0
    if remember is not None:
        session["remember_choice"] = remember


def _rate_limited(*pairs):
    """Restituisce il Result se una regola blocca, altrimenti None."""
    res = rate_limit.check(*pairs)
    if res.allowed:
        return None
    user = "-"
    if res.rule is not None and res.rule.kind == "user":
        user = next((_log_safe(i) for r, i in pairs if r == res.rule), "-")
    logger.warning(
        "rate limit superato path=%s scope=%s kind=%s ip=%s user=%s",
        _log_safe(request.path), res.rule.scope if res.rule else "-",
        res.rule.kind if res.rule else "-", _log_safe(_client_ip()), user,
    )
    return res


def _too_many_json(res):
    return {"ok": False, "error": "Troppi tentativi, riprova più tardi"}, 429, {"Retry-After": str(res.retry_after)}


def _too_many_page(res, template: str, **ctx):
    return render_template(template, error=_RATE_LIMIT_MSG, **ctx), 429, {"Retry-After": str(res.retry_after)}


# ============================================================================
# LOGIN + 2FA
# ============================================================================
@app.route("/login", methods=["GET", "POST"])
def login():
    if current_user.is_authenticated:
        return redirect(url_for("dashboard"))

    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "").strip()
        remember = bool(request.form.get("remember"))
        ip = _client_ip()

        pairs = [(rate_limit.LOGIN_IP, ip)]
        if username:
            pairs.append((rate_limit.LOGIN_USER, username))
        res = _rate_limited(*pairs)
        if res:
            return _too_many_page(res, "login.html")

        if verify_user(username, password):
            _start_pending(username, remember)

            if must_change_password(username):
                session["password_change_pending"] = True
                return redirect(url_for("force_change_password"))

            if not is_totp_enrolled(username):
                session["totp_setup_pending"] = True
                return redirect(url_for("totp_setup"))

            session["2fa_pending"] = True
            return redirect(url_for("twofa"))

        logger.warning("login fallito user=%s ip=%s", _log_safe(username), _log_safe(ip))
        return render_template("login.html", error="Credenziali non valide.")

    return render_template("login.html")


@app.route("/2fa", methods=["GET", "POST"])
def twofa():
    username = _get_pending_user("2fa_pending")
    if not username:
        return redirect(url_for("login"))

    if request.method == "POST":
        res = _rate_limited((rate_limit.TOTP_USER, username))
        if res:
            return _too_many_page(res, "2fa.html")

        code = request.form.get("code", "")

        if verify_totp(username, code):
            remember = session.get("remember_choice", False)
            epoch = session.get("pending_epoch", 0)
            _clear_pending()

            login_user(User(username, epoch), remember=remember)
            return redirect(url_for("dashboard"))

        logger.warning("TOTP fallito user=%s ip=%s", _log_safe(username), _log_safe(_client_ip()))
        return render_template("2fa.html", error="Codice 2FA non valido.")

    return render_template("2fa.html")


@app.route("/totp-setup", methods=["GET", "POST"])
def totp_setup():
    """Pagina di enrollment TOTP — mostrata al primo login."""
    username = _get_pending_user("totp_setup_pending")
    if not username:
        return redirect(url_for("login"))

    totp_secret = get_totp_secret(username)

    if not totp_secret:
        return redirect(url_for("login"))

    import pyotp
    totp_uri = pyotp.TOTP(totp_secret).provisioning_uri(
        name=username,
        issuer_name="INVA Dashboard"
    )

    if request.method == "POST":
        res = _rate_limited((rate_limit.TOTP_USER, username))
        if res:
            return _too_many_page(res, "totp_setup.html", totp_secret=totp_secret, totp_uri=totp_uri)

        code = request.form.get("code", "")
        if enroll_totp(username, code):
            remember = session.get("remember_choice", False)
            epoch = session.get("pending_epoch", 0)
            _clear_pending()
            login_user(User(username, epoch), remember=remember)
            return redirect(url_for("dashboard"))
        logger.warning("TOTP fallito user=%s ip=%s", _log_safe(username), _log_safe(_client_ip()))
        return render_template("totp_setup.html",
                               totp_secret=totp_secret,
                               totp_uri=totp_uri,
                               error="Codice non valido. Riprova.")

    return render_template("totp_setup.html",
                           totp_secret=totp_secret,
                           totp_uri=totp_uri)


@app.route("/change-password", methods=["GET", "POST"])
def force_change_password():
    """Cambio password obbligatorio — mostrato dopo il login se il flag è attivo."""
    username = _get_pending_user("password_change_pending")
    if not username:
        return redirect(url_for("login"))

    if request.method == "POST":
        res = _rate_limited((rate_limit.CHPW_USER, username))
        if res:
            return _too_many_page(res, "change_password.html")

        new_password = request.form.get("new_password", "").strip()
        confirm_password = request.form.get("confirm_password", "").strip()

        if new_password != confirm_password:
            return render_template("change_password.html",
                                   error="Le password non corrispondono.")

        try:
            change_password(username, new_password)
        except PasswordValidationError as e:
            return render_template("change_password.html", error=str(e))

        session.pop("password_change_pending", None)

        # Prosegui con il flusso normale
        if not is_totp_enrolled(username):
            session["totp_setup_pending"] = True
            return redirect(url_for("totp_setup"))

        session["2fa_pending"] = True
        return redirect(url_for("twofa"))

    return render_template("change_password.html")


@app.route("/logout")
def logout():
    logout_user()
    return redirect(url_for("login"))


# ============================================================================
# HELPER
# ============================================================================
def map_status(x):
    return "DOWN" if x == 0 else "UP"


def extract_monitor_url(name, statuses):
    import re

    m = re.search(r"-\s*(https?://)?([\w.-]+\.\w+)", name)
    if not m:
        return None

    domain = m.group(2)

    for url in statuses.keys():
        if domain in url:
            return url
    return None


# ============================================================================
# SENSOR ALERT LOGIC
# ============================================================================
def compute_alert_status(sensor: dict) -> str:
    """
    Returns the alert status for a single sensor reading.
    Uses the per-sensor threshold from the webhook.
    Returns: "normal" or "critical"
    """
    return sensor.get("status", "normal")


def build_sensor_payload(inverter_data: dict) -> dict:
    """
    Builds the sensor portion of the watch-data response.
    Returns dict with: sensors, sites, sensor_history, sensor_alerts,
    and optionally sensor_error.
    """
    if inverter_data.get("error"):
        return {
            "sensors": [],
            "sites": {},
            "sensor_history": {},
            "sensor_alerts": {"critical_count": 0},
            "sensor_error": inverter_data["error"],
        }

    sensors = inverter_data.get("sensors", [])
    sites = inverter_data.get("sites", {})
    history = inverter_data.get("history", {})

    # Compute alerts — solo critical (no warning)
    critical_count = 0
    for s in sensors:
        if s.get("status") == "critical":
            critical_count += 1

    return {
        "sensors": sensors,
        "sites": sites,
        "sensor_history": history,
        "sensor_alerts": {"critical_count": critical_count},
    }


# ============================================================================
# COSTRUZIONE DATI DASHBOARD
# ============================================================================
def build_dashboard_data():
    m2 = load_monitors(KUMA2["host"], KUMA2["slug"])
    # TIM (KUMA2) è la sorgente primaria per la lista monitor.
    # Le altre sonde sono opzionali: se non rispondono, la dashboard funziona lo stesso.
    m1 = load_monitors(KUMA1["host"], KUMA1["slug"]) or {}
    m3 = load_monitors(KUMA3["host"], KUMA3["slug"]) or {}
    common = sorted(m2.keys())

    statuses = load_status()

    rows = []
    for name_norm in common:
        display = m2[name_norm]
        p = process_monitor(display, statuses, name_norm)

        rows.append(
            {
                "name": display,
                "k1": map_status(p["bg"]),
                "k2": map_status(p["tim"]),
                "k3": map_status(p["iliad"]),
                "n1": map_status(p["nodeping"]),
                "u1": map_status(p["uptime"]),
                "final": map_status(p["final"]),
                "severity": p["severity"],
                "history": p["history"],
                "link": extract_monitor_url(display, statuses),
            }
        )

    rows.sort(key=lambda x: 0 if x["final"] == "DOWN" else 1)

    severities = [r["severity"] for r in rows]
    global_state = compute_global_state(severities)

    return rows, global_state


# ============================================================================
# SERVICE WORKER — nuovo nome /sw.js
# ============================================================================
@app.route("/sw.js")
def service_worker():
    swdir = os.path.join(app.root_path, "static", "js")
    return send_from_directory(swdir, "sw.js", mimetype="application/javascript")


# ============================================================================
# PUSH SUBSCRIPTION/UNSUBSCRIPTION
# ============================================================================
@app.route("/push/subscribe", methods=["POST"])
@login_required
def push_subscribe():
    data = request.get_json(silent=True) or {}
    if "endpoint" not in data:
        return {"ok": False, "error": "no endpoint"}, 400

    threshold = data.get("threshold")
    if threshold is not None:
        if not validate_threshold(threshold):
            return {"ok": False, "error": "threshold must be an integer between 1 and 5"}, 400

    sub = {
        "endpoint": data["endpoint"],
        "keys": {
            "p256dh": data.get("keys", {}).get("p256dh", ""),
            "auth": data.get("keys", {}).get("auth", ""),
        },
    }
    if threshold is not None:
        sub["threshold"] = threshold
    add_subscription(sub)
    return {"ok": True}, 201


@app.route("/push/unsubscribe", methods=["POST"])
@login_required
def push_unsubscribe():
    data = request.get_json(silent=True) or {}

    endpoint = data.get("endpoint")
    if not endpoint:
        return {"ok": False, "error": "missing endpoint"}, 400

    remove_subscription(endpoint)

    return {"ok": True, "removed": True}


# ============================================================================
# PUSH THRESHOLD — aggiornamento soglia notifica
# ============================================================================
@app.route("/push/threshold", methods=["POST"])
@login_required
def push_threshold():
    data = request.get_json(silent=True) or {}
    endpoint = data.get("endpoint")
    threshold = data.get("threshold")

    if not endpoint:
        return {"ok": False, "error": "missing endpoint"}, 400
    if not validate_threshold(threshold):
        return {"ok": False, "error": "threshold must be an integer between 1 and 5"}, 400

    raw = _redis.hget("push:subs_by_endpoint", endpoint)
    if not raw:
        return {"ok": False, "error": "subscription not found"}, 404

    record = json.loads(raw)
    record["threshold"] = threshold
    _redis.hset("push:subs_by_endpoint", endpoint, json.dumps(record))
    return {"ok": True}, 200


@app.route("/push/apns/subscribe", methods=["POST"])
@login_required
def apns_subscribe():
    data = request.get_json(silent=True) or {}

    device_token = data.get("device_token")
    if not device_token:
        return {"ok": False, "error": "missing device_token"}, 400

    threshold = data.get("threshold", 1)
    if not validate_threshold(threshold):
        return {"ok": False, "error": "threshold must be an integer between 1 and 5"}, 400

    device_id = data.get("device_id", "")
    environment = data.get("environment", "production")
    categories = data.get("categories")  # lista o None
    add_apns_subscription(device_token, device_id, environment, threshold=threshold, categories=categories)
    return {"ok": True}, 201


@app.route("/push/apns/unsubscribe", methods=["POST"])
@login_required
def apns_unsubscribe():
    data = request.get_json(silent=True) or {}

    device_token = data.get("device_token")
    if not device_token:
        return {"ok": False, "error": "missing device_token"}, 400

    remove_apns_subscription(device_token)
    return {"ok": True}, 200


# ============================================================================
# APNS THRESHOLD — aggiornamento soglia notifica APNs
# ============================================================================
@app.route("/push/apns/threshold", methods=["POST"])
@login_required
def apns_threshold():
    data = request.get_json(silent=True) or {}
    device_token = data.get("device_token")
    threshold = data.get("threshold")

    if not device_token:
        return {"ok": False, "error": "missing device_token"}, 400
    if not validate_threshold(threshold):
        return {"ok": False, "error": "threshold must be an integer between 1 and 5"}, 400

    raw = _redis.hget("apns:subs_by_token", device_token)
    if not raw:
        return {"ok": False, "error": "subscription not found"}, 404

    record = json.loads(raw)
    record["threshold"] = threshold
    _redis.hset("apns:subs_by_token", device_token, json.dumps(record))
    return {"ok": True}, 200


# ============================================================================
# APNS CATEGORIES — aggiornamento categorie push per device
# ============================================================================
@app.route("/push/apns/categories", methods=["POST"])
@login_required
def apns_categories():
    """Aggiorna le categorie push abilitate per un device APNs iOS."""
    data = request.get_json(silent=True) or {}
    device_token = data.get("device_token")
    categories = data.get("categories")

    if not device_token:
        return {"ok": False, "error": "missing device_token"}, 400
    if categories is not None and not isinstance(categories, list):
        return {"ok": False, "error": "categories must be a list"}, 400

    raw = _redis.hget("apns:subs_by_token", device_token)
    if not raw:
        return {"ok": False, "error": "subscription not found"}, 404

    record = json.loads(raw)
    record["categories"] = categories or []
    _redis.hset("apns:subs_by_token", device_token, json.dumps(record))
    return {"ok": True}, 200


@app.route("/api/mac/apns/categories", methods=["POST"])
def api_mac_apns_categories():
    """Aggiorna le categorie push abilitate per un device APNs Mac."""
    token = request.headers.get("X-Watch-Token", "")
    if not WATCH_API_TOKEN or not hmac.compare_digest(token, WATCH_API_TOKEN):
        return {"ok": False, "error": "unauthorized"}, 401

    data = request.get_json(silent=True) or {}
    device_token = data.get("device_token")
    categories = data.get("categories")

    if not device_token:
        return {"ok": False, "error": "missing device_token"}, 400
    if categories is not None and not isinstance(categories, list):
        return {"ok": False, "error": "categories must be a list"}, 400

    raw = _redis.hget("apns:subs_by_token", device_token)
    if not raw:
        return {"ok": False, "error": "subscription not found"}, 404

    record = json.loads(raw)
    record["categories"] = categories or []
    _redis.hset("apns:subs_by_token", device_token, json.dumps(record))
    return {"ok": True}, 200


@app.route("/api/mac/apns/threshold", methods=["POST"])
def api_mac_apns_threshold():
    """Aggiorna soglia notifica APNs dal Mac. Autenticato con token API."""
    token = request.headers.get("X-Watch-Token", "")
    if not WATCH_API_TOKEN or not hmac.compare_digest(token, WATCH_API_TOKEN):
        return {"ok": False, "error": "unauthorized"}, 401

    data = request.get_json(silent=True) or {}
    device_token = data.get("device_token")
    threshold = data.get("threshold")

    if not device_token:
        return {"ok": False, "error": "missing device_token"}, 400
    if not validate_threshold(threshold):
        return {"ok": False, "error": "threshold must be an integer between 1 and 5"}, 400

    raw = _redis.hget("apns:subs_by_token", device_token)
    if not raw:
        return {"ok": False, "error": "subscription not found"}, 404

    record = json.loads(raw)
    record["threshold"] = threshold
    _redis.hset("apns:subs_by_token", device_token, json.dumps(record))
    return {"ok": True}, 200


# ============================================================================
# API MOBILE — login e 2FA JSON per l'app iOS
# ============================================================================

@app.route("/api/login", methods=["POST"])
def api_login():
    """Login JSON per l'app iOS. Restituisce requires_2fa o success."""
    ip = _client_ip()
    res = _rate_limited((rate_limit.LOGIN_IP, ip))
    if res:
        return _too_many_json(res)

    data = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    password = data.get("password", "").strip()

    if not username or not password:
        return {"ok": False, "error": "missing credentials"}, 400

    res = _rate_limited((rate_limit.LOGIN_USER, username))
    if res:
        return _too_many_json(res)

    if not verify_user(username, password):
        logger.warning("login fallito user=%s ip=%s", _log_safe(username), _log_safe(ip))
        return {"ok": False, "error": "invalid credentials"}, 401

    _start_pending(username)

    if must_change_password(username):
        session["password_change_pending"] = True
        return {"ok": True, "next": "change_password"}, 200

    if not is_totp_enrolled(username):
        # Enrollment TOTP pendente
        totp_secret = get_totp_secret(username)
        import pyotp
        totp_uri = pyotp.TOTP(totp_secret).provisioning_uri(
            name=username,
            issuer_name="INVA Dashboard"
        )
        session["totp_setup_pending"] = True
        return {"ok": True, "next": "totp_setup", "totp_secret": totp_secret, "totp_uri": totp_uri}, 200

    session["2fa_pending"] = True
    return {"ok": True, "next": "2fa"}, 200


@app.route("/api/2fa", methods=["POST"])
def api_2fa():
    """Verifica 2FA JSON per l'app iOS. Restituisce il token biometrico."""
    username = _get_pending_user("2fa_pending")
    if not username:
        return {"ok": False, "error": "no pending session"}, 401

    res = _rate_limited((rate_limit.TOTP_USER, username))
    if res:
        return _too_many_json(res)

    data = request.get_json(silent=True) or {}
    code = data.get("code", "")

    if not verify_totp(username, code):
        logger.warning("TOTP fallito user=%s ip=%s", _log_safe(username), _log_safe(_client_ip()))
        return {"ok": False, "error": "invalid code"}, 401

    epoch = session.get("pending_epoch", 0)
    _clear_pending()
    login_user(User(username, epoch), remember=True)

    # Genera token biometrico valido 90 giorni
    signed_token = _issue_biometric_token(username, epoch)

    return {"ok": True, "biometric_token": signed_token, "username": username}, 200


@app.route("/api/change-password", methods=["POST"])
def api_change_password():
    """Cambio password obbligatorio per l'app iOS."""
    username = _get_pending_user("password_change_pending")
    if not username:
        return {"ok": False, "error": "no pending password change"}, 401

    res = _rate_limited((rate_limit.CHPW_USER, username))
    if res:
        return _too_many_json(res)

    data = request.get_json(silent=True) or {}
    new_password = data.get("new_password", "").strip()

    try:
        change_password(username, new_password)
    except PasswordValidationError as e:
        return {"ok": False, "error": str(e)}, 400

    session.pop("password_change_pending", None)

    # Determina il prossimo step
    if not is_totp_enrolled(username):
        totp_secret = get_totp_secret(username)
        import pyotp
        totp_uri = pyotp.TOTP(totp_secret).provisioning_uri(
            name=username,
            issuer_name="INVA Dashboard"
        )
        session["totp_setup_pending"] = True
        return {"ok": True, "next": "totp_setup", "totp_secret": totp_secret, "totp_uri": totp_uri}, 200

    session["2fa_pending"] = True
    return {"ok": True, "next": "2fa"}, 200


@app.route("/api/totp/enroll", methods=["POST"])
def api_totp_enroll():
    """Completa l'enrollment TOTP per l'app iOS. Verifica il codice e segna come enrolled."""
    username = _get_pending_user("totp_setup_pending")
    if not username:
        return {"ok": False, "error": "no pending enrollment"}, 401

    res = _rate_limited((rate_limit.TOTP_USER, username))
    if res:
        return _too_many_json(res)

    data = request.get_json(silent=True) or {}
    code = data.get("code", "")

    if not enroll_totp(username, code):
        logger.warning("TOTP fallito user=%s ip=%s", _log_safe(username), _log_safe(_client_ip()))
        return {"ok": False, "error": "invalid code"}, 401

    epoch = session.get("pending_epoch", 0)
    _clear_pending()
    login_user(User(username, epoch), remember=True)

    # Genera token biometrico
    signed_token = _issue_biometric_token(username, epoch)

    return {"ok": True, "biometric_token": signed_token, "username": username}, 200


# ============================================================================
# BIOMETRIC AUTH — token monouso per Face ID / Touch ID
# ============================================================================

def _sign_biometric_token(token: str) -> str:
    """Firma un token biometrico con HMAC-SHA256."""
    return hmac.new(
        BIOMETRIC_SECRET.encode(),
        token.encode(),
        hashlib.sha256
    ).hexdigest()


_BIOMETRIC_TTL = 90 * 24 * 3600


def _issue_biometric_token(username: str, epoch: int) -> str:
    """Emette un token biometrico firmato (raw.hmac), valido 90 giorni e legato all'epoch."""
    raw_token = secrets.token_urlsafe(32)
    signature = _sign_biometric_token(raw_token)
    _redis.setex(f"biometric:{username}:{raw_token}", _BIOMETRIC_TTL, f"e{epoch}")
    return f"{raw_token}.{signature}"


@app.route("/auth/biometric/token", methods=["POST"])
@login_required
def biometric_get_token():
    """Genera un token biometrico monouso valido 90 giorni.
    Chiamato dall'app iOS dopo il primo login con password+2FA.
    Il token viene salvato in Redis con scadenza 90 giorni.
    """
    username = current_user.id
    try:
        epoch = get_session_epoch(username)
        if epoch is None:
            return {"ok": False, "error": "unauthorized"}, 401
        signed_token = _issue_biometric_token(username, epoch)
    except (redis_lib.RedisError, ValueError):
        logger.error("biometric token: Redis non disponibile")
        abort(503)

    return {"ok": True, "token": signed_token}, 200


@app.route("/auth/biometric/login", methods=["POST"])
def biometric_login():
    """Login con token biometrico — bypassa password e 2FA.
    Chiamato dall'app iOS dopo Face ID riuscito.
    """
    ip = _client_ip()
    res = _rate_limited((rate_limit.BIO_IP, ip))
    if res:
        return _too_many_json(res)

    data = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    signed_token = data.get("biometric_token", "")

    if not username or not signed_token or "." not in signed_token:
        return {"ok": False, "error": "invalid"}, 400

    parts = signed_token.rsplit(".", 1)
    if len(parts) != 2:
        return {"ok": False, "error": "invalid"}, 400

    raw_token, provided_sig = parts[0], parts[1]
    expected_sig = _sign_biometric_token(raw_token)

    # Verifica firma con confronto sicuro (timing-safe)
    if not hmac.compare_digest(expected_sig, provided_sig):
        logger.warning("biometric login fallito user=%s ip=%s", _log_safe(username), _log_safe(ip))
        return {"ok": False, "error": "invalid"}, 401

    # Verifica che il token esista in Redis e sia legato all'epoch corrente
    key = f"biometric:{username}:{raw_token}"
    try:
        value = _redis.get(key)
        if value is None:
            logger.warning("biometric login fallito user=%s ip=%s", _log_safe(username), _log_safe(ip))
            return {"ok": False, "error": "expired"}, 401
        current = get_session_epoch(username)
        valid = current is not None and (value == f"e{current}" or (value == "1" and current == 0))
        if not valid:
            # Token revocato da un reset password (o utente rimosso)
            _redis.delete(key)
            logger.warning("biometric login fallito user=%s ip=%s", _log_safe(username), _log_safe(ip))
            return {"ok": False, "error": "expired"}, 401
    except (redis_lib.RedisError, ValueError):
        logger.error("biometric login: Redis non disponibile")
        abort(503)

    # Login riuscito
    login_user(User(username, current), remember=True)
    return {"ok": True}, 200


# ============================================================================
# RESET PASSWORD SELF-SERVICE (via email)
# ============================================================================
def _handle_reset_request(raw, ip: str) -> None:
    """Crea il token e invia il link se possibile. Non restituisce nulla: il chiamante
    risponde sempre con lo stesso messaggio generico (anti-enumeration)."""
    username = raw.strip() if isinstance(raw, str) else ""
    if not is_valid_username(username):
        logger.info("richiesta reset user=%s ip=%s esito=utente_sconosciuto_o_senza_email",
                    _log_safe(username), _log_safe(ip))
        return
    if not PUBLIC_BASE_URL or not mailer.is_configured():
        logger.error("reset disabilitato: configurazione mancante")
        logger.info("richiesta reset user=%s ip=%s esito=disabilitato", _log_safe(username), _log_safe(ip))
        return
    try:
        result = create_password_reset_token(username)
    except redis_lib.RedisError:
        logger.error("richiesta reset: Redis non disponibile")
        return
    if result is None:
        logger.info("richiesta reset user=%s ip=%s esito=utente_sconosciuto_o_senza_email",
                    _log_safe(username), _log_safe(ip))
        return
    token, email = result
    mailer.send_reset_link_async(username, email, token)
    logger.info("richiesta reset user=%s ip=%s esito=inviata", _log_safe(username), _log_safe(ip))


def _reset_request_limits(raw, ip: str):
    """PWREQ_IP sempre; PWREQ_USER solo se lo username ha un formato valido."""
    pairs = [(rate_limit.PWREQ_IP, ip)]
    username = raw.strip() if isinstance(raw, str) else ""
    if is_valid_username(username):
        pairs.append((rate_limit.PWREQ_USER, username))
    return _rate_limited(*pairs)


@app.route("/forgot-password", methods=["GET", "POST"])
def forgot_password():
    if request.method == "POST":
        raw = request.form.get("username", "")
        ip = _client_ip()
        res = _reset_request_limits(raw, ip)
        if res:
            return _too_many_page(res, "forgot_password.html")
        _handle_reset_request(raw, ip)
        return render_template("forgot_password.html", sent=True, message=_RESET_REQUEST_MSG)

    return render_template("forgot_password.html")


@app.route("/api/password-reset/request", methods=["POST"])
def api_password_reset_request():
    """Richiesta del link di reset dalle app. Risposta sempre identica (anti-enumeration)."""
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return {"ok": False, "error": "invalid request"}, 400

    raw = data.get("username", "")
    if not isinstance(raw, str):
        raw = ""
    ip = _client_ip()
    res = _reset_request_limits(raw, ip)
    if res:
        return _too_many_json(res)

    _handle_reset_request(raw, ip)
    return {"ok": True, "message": _RESET_REQUEST_MSG}, 200


_SERVICE_UNAVAILABLE_MSG = "Servizio temporaneamente non disponibile, riprova più tardi."


def _reset_page(state: str, status: int, token: str = "", error: str | None = None, headers=None):
    body = render_template("reset_password.html", state=state,
                           token=token if state == "form" else "", error=error)
    return body, status, headers or {}


@app.route("/reset-password", methods=["GET", "POST"])
def reset_password():
    ip = _client_ip()

    if request.method == "GET":
        token = request.args.get("token", "")
        if not isinstance(token, str) or not RESET_TOKEN_RE.fullmatch(token):
            return _reset_page("invalid", 400)
        try:
            if not peek_reset_token(token):
                return _reset_page("invalid", 400)
        except redis_lib.RedisError:
            logger.error("reset password: Redis non disponibile")
            return _reset_page("invalid", 503, error=_SERVICE_UNAVAILABLE_MSG)
        return _reset_page("form", 200, token=token)

    token = request.form.get("token", "")
    well_formed = RESET_TOKEN_RE.fullmatch(token) is not None

    # 1. Rate limit (prima di qualsiasi lookup)
    res = _rate_limited((rate_limit.PWRESET_IP, ip), (rate_limit.PWRESET_TOKEN, token))
    if res:
        return _reset_page("form" if well_formed else "invalid", 429, token=token,
                           error=_RATE_LIMIT_MSG, headers={"Retry-After": str(res.retry_after)})

    try:
        # 2. Token valido?
        username = peek_reset_token(token)
        if not username:
            logger.warning("reset password: token non valido ip=%s", _log_safe(ip))
            return _reset_page("invalid", 400)

        # 3-4. Conferma e policy (il token resta valido)
        new_password = request.form.get("new_password", "").strip()
        confirm_password = request.form.get("confirm_password", "").strip()
        if new_password != confirm_password:
            return _reset_page("form", 400, token=token, error="Le password non corrispondono.")
        try:
            validate_new_password(username, new_password)
        except PasswordValidationError as e:
            return _reset_page("form", 400, token=token, error=str(e))

        # 5. Consumo atomico (tra due POST concorrenti ne vince una)
        username = consume_reset_token(token)
        if not username:
            logger.warning("reset password: token non valido ip=%s", _log_safe(ip))
            return _reset_page("invalid", 400)

        # 6. Password + 2FA + epoch in un'unica transazione
        try:
            complete_password_reset(username, new_password)
        except KeyError:
            logger.warning("reset password: utente rimosso user=%s ip=%s", _log_safe(username), _log_safe(ip))
            return _reset_page("invalid", 400)
        except PasswordValidationError as e:
            # Il token è già consumato: serve un nuovo link
            return _reset_page("invalid", 400, error=f"{e} Richiedi un nuovo link.")

        try:
            email = get_user_email(username)
        except redis_lib.RedisError:
            email = None
    except redis_lib.RedisError:
        logger.error("reset password: Redis non disponibile")
        return _reset_page("invalid", 503, error=_SERVICE_UNAVAILABLE_MSG)

    # 7. Notifiche asincrone (errori SMTP assorbiti dal mailer)
    when = datetime.now(ZoneInfo("Europe/Rome"))
    if email:
        mailer.send_reset_confirmation_async(username, email, when)
    mailer.send_admin_alert_async(username, when, ip)
    logger.info("reset completato user=%s ip=%s", _log_safe(username), _log_safe(ip))

    # 8. Nessun login automatico
    return _reset_page("done", 200)


# ============================================================================
# DASHBOARD
# ============================================================================
@app.route("/")
@login_required
def dashboard():
    rows, global_state = build_dashboard_data()
    inverter_data = fetch_inverter_data()

    return render_template(
        "dashboard.html",
        items=rows,
        global_state=global_state,
        inverter=inverter_data,
        current_year=datetime.now().year,
        vapid_public_key=PUSH_VAPID_PUBLIC_KEY if PUSH_ENABLED else "",
        randomize_version=random.randint(159827789,654987987),
    )


# ============================================================================
# API JSON
# ============================================================================
@app.route("/api/dashboard-data")
@login_required
def api_dashboard_data():
    rows, global_state = build_dashboard_data()
    return jsonify(
        {"items": rows, "global_state": global_state, "timestamp": datetime.now().isoformat()}
    )


@app.route("/api/inverter-data")
@login_required
def api_inverter_data():
    data = fetch_inverter_data()
    return jsonify(data)


@app.route("/api/probe-health")
@login_required
def api_probe_health():
    """Stato delle sonde di monitoraggio Kuma (check NodePing).

    Distinto dai portali: indica se gli agenti di monitoraggio stessi
    sono operativi. Include lo storico per-sonda (sparkline) da Redis.
    Autenticazione: sessione Flask (@login_required).
    """
    from probe_health_client import fetch_probe_health
    from redis_history import load_probe_history

    data = fetch_probe_health()

    # Arricchisci con lo storico per-sonda (gestito da noi in Redis, non dal webhook)
    history = {}
    if data.get("status") == "ok":
        for probe in data.get("probes", []):
            check_id = probe.get("check_id")
            if check_id:
                history[check_id] = load_probe_history(check_id)
    data["history"] = history

    return jsonify(data)


@app.route("/api/events")
@login_required
def api_events():
    """Storico eventi (monitor, sensori — esclude global).

    Autenticazione: sessione Flask (@login_required).
    Query params:
      - limit (int, default 50, max 200)
      - before (ISO 8601 timestamp per paginazione)
      - type (str, opzionale — filtra per tipo: monitor, sensor, global)
    """
    from redis_history import load_events

    limit = request.args.get("limit", 50, type=int)
    before = request.args.get("before", None, type=str)

    # Limita a max 200
    limit = min(limit, 200)

    events = load_events(limit=500, before=before)

    # Escludi eventi global (le app mostrano solo monitor e sensor)
    events = [e for e in events if e.get("type") != "global"]

    return jsonify({"events": events[:limit], "count": len(events[:limit])})


@app.route("/api/events/<event_id>", methods=["DELETE"])
@login_required
def api_delete_event(event_id):
    """Elimina un evento specifico dal log Redis.

    Autenticazione: sessione Flask (@login_required).
    """
    from redis_history import delete_event

    if not event_id:
        return {"ok": False, "error": "missing event_id"}, 400

    removed = delete_event(event_id)
    if removed:
        return {"ok": True}, 200
    return {"ok": False, "error": "event not found"}, 404


@app.route("/api/watch-data")
def api_watch_data():
    """Endpoint leggero per l'Apple Watch. Autenticato con token statico via header."""
    token = request.headers.get("X-Watch-Token", "")
    if not WATCH_API_TOKEN or not hmac.compare_digest(token, WATCH_API_TOKEN):
        return {"ok": False, "error": "unauthorized"}, 401

    rows, global_state = build_dashboard_data()

    # Sensor data (graceful degradation)
    inverter = fetch_inverter_data()
    sensor_payload = build_sensor_payload(inverter)

    # Probe health (sonde Kuma) — graceful degradation
    from probe_health_client import fetch_probe_health
    probe_data = fetch_probe_health()
    if probe_data.get("status") == "ok":
        watch_probes = [
            {"label": p.get("label", ""), "is_operative": bool(p.get("is_operative", True))}
            for p in probe_data.get("probes", [])
        ]
        probe_non_operative = probe_data.get("non_operative_count", 0)
    else:
        watch_probes = []
        probe_non_operative = 0

    response = {
        "items": rows,
        "global_state": global_state,
        "timestamp": datetime.now().isoformat(),
        "probes": watch_probes,
        "probe_non_operative_count": probe_non_operative,
    }
    response.update(sensor_payload)
    return jsonify(response)


@app.route("/api/mac/apns/subscribe", methods=["POST"])
def api_mac_apns_subscribe():
    """Registra device token APNs dal Mac. Autenticato con token API."""
    token = request.headers.get("X-Watch-Token", "")
    if not WATCH_API_TOKEN or not hmac.compare_digest(token, WATCH_API_TOKEN):
        return {"ok": False, "error": "unauthorized"}, 401

    data = request.get_json(silent=True) or {}
    device_token = data.get("device_token")
    if not device_token:
        return {"ok": False, "error": "missing device_token"}, 400

    threshold = data.get("threshold", 1)
    if not validate_threshold(threshold):
        return {"ok": False, "error": "threshold must be an integer between 1 and 5"}, 400

    device_id = data.get("device_id", "")
    environment = data.get("environment", "production")
    bundle_id = data.get("bundle_id")
    categories = data.get("categories")  # lista o None
    add_apns_subscription(device_token, device_id, environment, bundle_id=bundle_id, threshold=threshold, categories=categories)
    return {"ok": True}, 201


@app.route("/api/mac/apns/unsubscribe", methods=["POST"])
def api_mac_apns_unsubscribe():
    """Rimuove device token APNs dal Mac. Autenticato con token API."""
    token = request.headers.get("X-Watch-Token", "")
    if not WATCH_API_TOKEN or not hmac.compare_digest(token, WATCH_API_TOKEN):
        return {"ok": False, "error": "unauthorized"}, 401

    data = request.get_json(silent=True) or {}
    device_token = data.get("device_token")
    if not device_token:
        return {"ok": False, "error": "missing device_token"}, 400

    remove_apns_subscription(device_token)
    return {"ok": True}, 200