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
from auth import verify_user, verify_totp
from config import (
    KUMA1,
    KUMA2,
    KUMA3,
    PUSH_ENABLED,
    PUSH_VAPID_PUBLIC_KEY,
    PUSH_NOTIFY_ON,
)
from push_utils import (
    add_subscription,
    send_push_to_all,
    load_subscriptions,
    save_subscriptions
)
from redis_history import get_global_state, set_global_state
import os

app = Flask(__name__)
app.secret_key = (
    "f88b5914fd3a8f5338ef758d0d3ba41fb7a203c5d70d50a8bdf26054a705f195"
)

# Remember me durata 1 anno
app.config["REMEMBER_COOKIE_DURATION"] = timedelta(days=365)

login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = "login"

# Stato globale precedente
LAST_GLOBAL_STATE = None


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
            session["2fa_pending"] = True
            session["remember_choice"] = remember
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
                "final": map_status(p["final"]),
                "severity": p["severity"],
                "history": p["history"],
                "link": extract_monitor_url(display, statuses),
            }
        )

    rows.sort(key=lambda x: 0 if x["final"] == "DOWN" else 1)

    any_final_down = any(r["final"] == "DOWN" for r in rows)
    any_mismatch = any(
        (r["k1"] != r["k2"] or r["k1"] != r["k3"] or r["k2"] != r["k3"]) and (r["final"] != "DOWN") for r in rows
    )

    if any_final_down:
        global_state = "RED"
    elif any_mismatch:
        global_state = "YELLOW"
    else:
        global_state = "GREEN"

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

    add_subscription(data)
    return {"ok": True}, 201


@app.route("/push/unsubscribe", methods=["POST"])
@login_required
def push_unsubscribe():
    data = request.get_json(silent=True) or {}

    endpoint = data.get("endpoint")
    if not endpoint:
        return {"ok": False, "error": "missing endpoint"}, 400

    subs = load_subscriptions()
    new_subs = [s for s in subs if s.get("endpoint") != endpoint]

    save_subscriptions(new_subs)

    return {"ok": True, "removed": True}

# ============================================================================
# DASHBOARD
# ============================================================================
@app.route("/")
@login_required
def dashboard():
    rows, global_state = build_dashboard_data()

    # ---- Notifiche push basate su transizione di stato globale ----
    previous = get_global_state()
    set_global_state(global_state)  # aggiorniamo sempre lo stato in Redis

    if PUSH_ENABLED and previous is not None:
        # 1) DOWN definitivo (RED)
        if (
            PUSH_NOTIFY_ON.get("final_down", False)
            and previous != "RED"
            and global_state == "RED"
        ):
            send_push_to_all(
                "🔔 Servizio IN.VA DOWN",
                "Una o più risorse risultano DOWN su entrambe le sonde.",
                {"state": "RED"},
            )

        # 2) Mismatch tra sonde (YELLOW)
        if (
            PUSH_NOTIFY_ON.get("probe_mismatch", False)
            and previous != "YELLOW"
            and global_state == "YELLOW"
        ):
            send_push_to_all(
                "🔔 Incongruenza tra sonde",
                "Una o più risorse hanno stato diverso tra le sonde.",
                {"state": "YELLOW"},
            )

        # 3) Ritorno a tutto OK (GREEN)
        if (
            PUSH_NOTIFY_ON.get("back_to_green", False)
            and previous in ("RED", "YELLOW")
            and global_state == "GREEN"
        ):
            send_push_to_all(
                "✅ IN.VA – tutto OK",
                "Tutte le risorse risultano UP su entrambe le sonde.",
                {"state": "GREEN"},
            )

    return render_template(
        "dashboard.html",
        items=rows,
        global_state=global_state,
        current_year=datetime.now().year,
        vapid_public_key=PUSH_VAPID_PUBLIC_KEY if PUSH_ENABLED else "",
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