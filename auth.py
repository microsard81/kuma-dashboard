# auth.py

import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

import pyotp
from werkzeug.security import check_password_hash

AUTH_PASSWORD_HASH = os.environ["AUTH_PASSWORD_HASH"]
AUTH_TOTP_SECRET = os.environ["AUTH_TOTP_SECRET"]

# DIZIONARIO UTENTI
USERS = {
    "itcarmat": {
        "password_hash": AUTH_PASSWORD_HASH,
        "totp_secret": AUTH_TOTP_SECRET,
    }
}

def verify_user(username, password):
    user = USERS.get(username)
    if not user:
        return False

    return check_password_hash(user["password_hash"], password)

def verify_totp(username, code):
    user = USERS.get(username)
    if not user:
        return False

    totp = pyotp.TOTP(user["totp_secret"])
    return totp.verify(code)
