# auth.py

import pyotp
from werkzeug.security import check_password_hash, generate_password_hash

# DIZIONARIO UTENTI
USERS = {
    "itcarmat": {
        "password_hash": generate_password_hash("FWFoivbB77aXuDe2qo__@h-"),
        "totp_secret": "KBCOP2YC642U5HPL7PARG7SZYSHXE4RB"
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