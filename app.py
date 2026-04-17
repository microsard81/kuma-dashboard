from flask import (
    Flask,
    render_template,
    request,
    redirect,
    url_for,
    session,
    send_from_directory,
    jsonify,
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

from kuma_client import load_monitors
from status_client import load_status, process_monitor
from auth import verify_user, verify_totp, is_totp_enrolled, get_totp_secret, enroll_totp, must_change_password, change_password, validate_password_complexity, PasswordValidationError
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

app = Flask(__name__)
app.secret_key = FLASK_SECRET_KEY

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
    def __init__(self, username: str):
        self.id = username


@login_manager.user_loader
def load_user(uid):
    return User(uid)


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

        if verify_user(username, password):
            session["pending_user"] = username
            session["remember_choice"] = remember

            if must_change_password(username):
                session["password_change_pending"] = True
                return redirect(url_for("force_change_password"))

            if not is_totp_enrolled(username):
                session["totp_setup_pending"] = True
                return redirect(url_for("totp_setup"))

            session["2fa_pending"] = True
            return redirect(url_for("twofa"))

        return render_template("login.html", error="Credenziali non valide.")

    return render_template("login.html")


@app.route("/2fa", methods=["GET", "POST"])
def twofa():
    if "pending_user" not in session:
        return redirect(url_for("login"))

    username = session["pending_user"]

    if request.method == "POST":
        code = request.form.get("code", "")

        if verify_totp(username, code):
            remember = session.get("remember_choice", False)

            session.pop("pending_user", None)
            session.pop("2fa_pending", None)
            session.pop("remember_choice", None)

            login_user(User(username), remember=remember)
            return redirect(url_for("dashboard"))

        return render_template("2fa.html", error="Codice 2FA non valido.")

    return render_template("2fa.html")


@app.route("/totp-setup", methods=["GET", "POST"])
def totp_setup():
    """Pagina di enrollment TOTP — mostrata al primo login."""
    if "pending_user" not in session or not session.get("totp_setup_pending"):
        return redirect(url_for("login"))

    username = session["pending_user"]
    totp_secret = get_totp_secret(username)

    if not totp_secret:
        return redirect(url_for("login"))

    import pyotp
    totp_uri = pyotp.TOTP(totp_secret).provisioning_uri(
        name=username,
        issuer_name="INVA Dashboard"
    )

    if request.method == "POST":
        code = request.form.get("code", "")
        if enroll_totp(username, code):
            remember = session.get("remember_choice", False)
            session.pop("pending_user", None)
            session.pop("totp_setup_pending", None)
            session.pop("remember_choice", None)
            login_user(User(username), remember=remember)
            return redirect(url_for("dashboard"))
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
    if "pending_user" not in session or not session.get("password_change_pending"):
        return redirect(url_for("login"))

    username = session["pending_user"]

    if request.method == "POST":
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
# COSTRUZIONE DATI DASHBOARD
# ============================================================================
def build_dashboard_data():
    m1 = load_monitors(KUMA1["host"], KUMA1["slug"])
    m2 = load_monitors(KUMA2["host"], KUMA2["slug"])
    m3 = load_monitors(KUMA3["host"], KUMA3["slug"])
    common = sorted(set(m1.keys()) & set(m2.keys()) & set(m3.keys()))

    statuses = load_status()

    rows = []
    for name_norm in common:
        display = m1[name_norm]
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
    add_apns_subscription(device_token, device_id, environment, threshold=threshold)
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
    data = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    password = data.get("password", "").strip()

    if not username or not password:
        return {"ok": False, "error": "missing credentials"}, 400

    if not verify_user(username, password):
        return {"ok": False, "error": "invalid credentials"}, 401

    session["pending_user"] = username

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
    import redis as redis_lib
    from config import REDIS_HOST, REDIS_PORT, REDIS_DB
    r = redis_lib.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)

    if "pending_user" not in session:
        return {"ok": False, "error": "no pending session"}, 401

    data = request.get_json(silent=True) or {}
    code = data.get("code", "")
    username = session["pending_user"]

    if not verify_totp(username, code):
        return {"ok": False, "error": "invalid code"}, 401

    session.pop("pending_user", None)
    session.pop("2fa_pending", None)
    login_user(User(username), remember=True)

    # Genera token biometrico valido 90 giorni
    raw_token = secrets.token_urlsafe(32)
    signature = _sign_biometric_token(raw_token)
    signed_token = f"{raw_token}.{signature}"
    key = f"biometric:{username}:{raw_token}"
    r.setex(key, 90 * 24 * 3600, "1")

    return {"ok": True, "biometric_token": signed_token, "username": username}, 200


@app.route("/api/change-password", methods=["POST"])
def api_change_password():
    """Cambio password obbligatorio per l'app iOS."""
    if "pending_user" not in session or not session.get("password_change_pending"):
        return {"ok": False, "error": "no pending password change"}, 401

    data = request.get_json(silent=True) or {}
    new_password = data.get("new_password", "").strip()

    username = session["pending_user"]

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
    import redis as redis_lib
    from config import REDIS_HOST, REDIS_PORT, REDIS_DB
    r = redis_lib.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)

    if "pending_user" not in session or not session.get("totp_setup_pending"):
        return {"ok": False, "error": "no pending enrollment"}, 401

    data = request.get_json(silent=True) or {}
    code = data.get("code", "")
    username = session["pending_user"]

    if not enroll_totp(username, code):
        return {"ok": False, "error": "invalid code"}, 401

    session.pop("totp_setup_pending", None)
    session.pop("pending_user", None)
    login_user(User(username), remember=True)

    # Genera token biometrico
    raw_token = secrets.token_urlsafe(32)
    signature = _sign_biometric_token(raw_token)
    signed_token = f"{raw_token}.{signature}"
    key = f"biometric:{username}:{raw_token}"
    r.setex(key, 90 * 24 * 3600, "1")

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


@app.route("/auth/biometric/token", methods=["POST"])
@login_required
def biometric_get_token():
    """Genera un token biometrico monouso valido 90 giorni.
    Chiamato dall'app iOS dopo il primo login con password+2FA.
    Il token viene salvato in Redis con scadenza 90 giorni.
    """
    import redis as redis_lib
    from config import REDIS_HOST, REDIS_PORT, REDIS_DB
    r = redis_lib.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)

    username = current_user.id
    raw_token = secrets.token_urlsafe(32)
    signature = _sign_biometric_token(raw_token)
    signed_token = f"{raw_token}.{signature}"

    # Salva in Redis con scadenza 90 giorni
    key = f"biometric:{username}:{raw_token}"
    r.setex(key, 90 * 24 * 3600, "1")

    return {"ok": True, "token": signed_token}, 200


@app.route("/auth/biometric/login", methods=["POST"])
def biometric_login():
    """Login con token biometrico — bypassa password e 2FA.
    Chiamato dall'app iOS dopo Face ID riuscito.
    """
    import redis as redis_lib
    from config import REDIS_HOST, REDIS_PORT, REDIS_DB
    r = redis_lib.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)

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
        return {"ok": False, "error": "invalid"}, 401

    # Verifica che il token esista in Redis
    key = f"biometric:{username}:{raw_token}"
    if not r.exists(key):
        return {"ok": False, "error": "expired"}, 401

    # Login riuscito
    login_user(User(username), remember=True)
    return {"ok": True}, 200


# ============================================================================
# DASHBOARD
# ============================================================================
@app.route("/")
@login_required
def dashboard():
    rows, global_state = build_dashboard_data()

    return render_template(
        "dashboard.html",
        items=rows,
        global_state=global_state,
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


@app.route("/api/watch-data")
def api_watch_data():
    """Endpoint leggero per l'Apple Watch. Autenticato con token statico via header."""
    token = request.headers.get("X-Watch-Token", "")
    if not WATCH_API_TOKEN or not hmac.compare_digest(token, WATCH_API_TOKEN):
        return {"ok": False, "error": "unauthorized"}, 401

    rows, global_state = build_dashboard_data()
    return jsonify(
        {"items": rows, "global_state": global_state, "timestamp": datetime.now().isoformat()}
    )


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
    add_apns_subscription(device_token, device_id, environment, bundle_id=bundle_id, threshold=threshold)
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