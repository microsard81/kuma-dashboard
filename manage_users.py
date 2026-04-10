#!/usr/bin/env python3
"""
CLI per gestire gli utenti del dashboard.
Salva username, password (hashata con bcrypt) e TOTP secret in Redis.
Il TOTP secret non viene mai mostrato nel terminale — l'utente lo configura al primo login.

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
from auth import validate_password_complexity, PasswordValidationError

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

    try:
        validate_password_complexity(password)
    except PasswordValidationError as e:
        print(f"Errore: {e}")
        sys.exit(1)

    totp_secret = pyotp.random_base32()
    password_hash = generate_password_hash(password)

    r.hset(key, mapping={
        "password_hash": password_hash,
        "totp_secret": totp_secret,
        "totp_enrolled": "0",
        "must_change_password": "1",
    })

    print(f"\nUtente '{username}' creato.")
    print("Al primo accesso dovrà cambiare la password e configurare il 2FA.")


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

    try:
        validate_password_complexity(password)
    except PasswordValidationError as e:
        print(f"Errore: {e}")
        sys.exit(1)

    # Reset admin: bypassa il controllo storico e azzera lo storico password
    password_hash = generate_password_hash(password)
    r.hset(key, "password_hash", password_hash)
    r.hset(key, "must_change_password", "1")
    r.hdel(key, "password_history")
    print(f"Password aggiornata per '{username}'. L'utente dovrà cambiarla al prossimo accesso.")


def cmd_reset_totp(username: str):
    key = user_key(username)
    if not r.exists(key):
        print(f"Errore: l'utente '{username}' non esiste.")
        sys.exit(1)

    totp_secret = pyotp.random_base32()
    r.hset(key, mapping={
        "totp_secret": totp_secret,
        "totp_enrolled": "0",
    })

    print(f"TOTP resettato per '{username}'.")
    print("L'utente dovrà riconfigurare il 2FA al prossimo accesso.")


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
