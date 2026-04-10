#!/usr/bin/env python3
"""
CLI per gestire gli utenti del dashboard.
Salva username, password (hashata con bcrypt) e TOTP secret in Redis.

Uso:
    python manage_users.py add <username>
    python manage_users.py remove <username>
    python manage_users.py list
    python manage_users.py reset-password <username>
    python manage_users.py reset-totp <username>
"""

import sys
import getpass
import pyotp
import redis
from werkzeug.security import generate_password_hash

from config import REDIS_HOST, REDIS_PORT, REDIS_DB

USER_PREFIX = "user:"

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)


def user_key(username: str) -> str:
    return f"{USER_PREFIX}{username}"


def cmd_add(username: str):
    key = user_key(username)
    if r.exists(key):
        print(f"Errore: l'utente '{username}' esiste già.")
        sys.exit(1)

    password = getpass.getpass("Password: ")
    confirm = getpass.getpass("Conferma password: ")
    if password != confirm:
        print("Errore: le password non corrispondono.")
        sys.exit(1)
    if len(password) < 8:
        print("Errore: la password deve avere almeno 8 caratteri.")
        sys.exit(1)

    totp_secret = pyotp.random_base32()
    password_hash = generate_password_hash(password)

    r.hset(key, mapping={
        "password_hash": password_hash,
        "totp_secret": totp_secret,
    })

    totp_uri = pyotp.TOTP(totp_secret).provisioning_uri(
        name=username,
        issuer_name="INVA Dashboard"
    )

    print(f"\nUtente '{username}' creato.")
    print(f"\nTOTP Secret: {totp_secret}")
    print(f"URI per app authenticator:\n{totp_uri}")
    print("\nAggiungi questo URI alla tua app authenticator (Google Authenticator, Authy, ecc.)")


def cmd_remove(username: str):
    key = user_key(username)
    if not r.exists(key):
        print(f"Errore: l'utente '{username}' non esiste.")
        sys.exit(1)

    confirm = input(f"Sei sicuro di voler eliminare '{username}'? (s/N): ")
    if confirm.lower() != "s":
        print("Annullato.")
        return

    # Rimuovi anche eventuali token biometrici
    bio_keys = r.keys(f"biometric:{username}:*")
    for bk in bio_keys:
        r.delete(bk)

    r.delete(key)
    print(f"Utente '{username}' eliminato.")


def cmd_list():
    keys = r.keys(f"{USER_PREFIX}*")
    if not keys:
        print("Nessun utente registrato.")
        return

    print("Utenti registrati:")
    for key in sorted(keys):
        username = key.removeprefix(USER_PREFIX)
        print(f"  - {username}")


def cmd_reset_password(username: str):
    key = user_key(username)
    if not r.exists(key):
        print(f"Errore: l'utente '{username}' non esiste.")
        sys.exit(1)

    password = getpass.getpass("Nuova password: ")
    confirm = getpass.getpass("Conferma password: ")
    if password != confirm:
        print("Errore: le password non corrispondono.")
        sys.exit(1)
    if len(password) < 8:
        print("Errore: la password deve avere almeno 8 caratteri.")
        sys.exit(1)

    password_hash = generate_password_hash(password)
    r.hset(key, "password_hash", password_hash)
    print(f"Password aggiornata per '{username}'.")


def cmd_reset_totp(username: str):
    key = user_key(username)
    if not r.exists(key):
        print(f"Errore: l'utente '{username}' non esiste.")
        sys.exit(1)

    totp_secret = pyotp.random_base32()
    r.hset(key, "totp_secret", totp_secret)

    totp_uri = pyotp.TOTP(totp_secret).provisioning_uri(
        name=username,
        issuer_name="INVA Dashboard"
    )

    print(f"Nuovo TOTP Secret per '{username}': {totp_secret}")
    print(f"URI:\n{totp_uri}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == "list":
        cmd_list()
    elif command == "add":
        if len(sys.argv) < 3:
            print("Uso: python manage_users.py add <username>")
            sys.exit(1)
        cmd_add(sys.argv[2])
    elif command == "remove":
        if len(sys.argv) < 3:
            print("Uso: python manage_users.py remove <username>")
            sys.exit(1)
        cmd_remove(sys.argv[2])
    elif command == "reset-password":
        if len(sys.argv) < 3:
            print("Uso: python manage_users.py reset-password <username>")
            sys.exit(1)
        cmd_reset_password(sys.argv[2])
    elif command == "reset-totp":
        if len(sys.argv) < 3:
            print("Uso: python manage_users.py reset-totp <username>")
            sys.exit(1)
        cmd_reset_totp(sys.argv[2])
    else:
        print(f"Comando sconosciuto: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
