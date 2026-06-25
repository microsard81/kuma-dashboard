#!/usr/bin/env python3
"""
CLI per gestire lo storico eventi (events:log in Redis).

Uso:
    python manage_events.py list                # Ultimi 50 eventi
    python manage_events.py list 20             # Ultimi 20 eventi
    python manage_events.py list all            # Tutti gli eventi (max 500)
    python manage_events.py count               # Conteggio totale
    python manage_events.py delete <event_id>   # Elimina un singolo evento per ID
    python manage_events.py clear               # Cancella tutti gli eventi
    python manage_events.py add <tipo> <desc>   # Aggiunge un evento di test
"""

import json
import sys
from datetime import datetime, timezone

from redis_history import r, load_events, push_event

_EVENTS_KEY = "events:log"


def cmd_list(limit: int = 50):
    """Mostra gli ultimi N eventi."""
    events = load_events(limit=limit)
    if not events:
        print("Nessun evento in Redis.")
        return

    print(f"{'ID':<38} {'Timestamp':<20} {'Tipo':<9} {'Nome':<35} {'Da':<10} {'A':<10} Dettaglio")
    print("-" * 150)
    for e in events:
        eid = e.get("id", "?")[:36]
        ts = e["ts"][:19].replace("T", " ")
        tipo = e.get("type", "?")
        nome = e.get("name", "")[:34]
        da = e.get("from", "")[:9]
        a = e.get("to", "")[:9]
        detail = e.get("detail", "")[:40]
        print(f"{eid:<38} {ts:<20} {tipo:<9} {nome:<35} {da:<10} {a:<10} {detail}")

    print(f"\n— {len(events)} eventi mostrati (totale in Redis: {r.llen(_EVENTS_KEY)})")


def cmd_count():
    """Mostra il conteggio totale."""
    count = r.llen(_EVENTS_KEY)
    print(f"Eventi in Redis: {count}")


def cmd_clear():
    """Cancella tutti gli eventi."""
    count = r.llen(_EVENTS_KEY)
    if count == 0:
        print("Nessun evento da cancellare.")
        return
    confirm = input(f"Cancellare {count} eventi? (s/N): ").strip().lower()
    if confirm == "s":
        r.delete(_EVENTS_KEY)
        print(f"Cancellati {count} eventi.")
    else:
        print("Annullato.")


def cmd_delete(event_id: str):
    """Elimina un singolo evento per ID."""
    from redis_history import delete_event
    if delete_event(event_id):
        print(f"Evento {event_id} eliminato.")
    else:
        print(f"Evento {event_id} non trovato.")


def cmd_add(event_type: str, detail: str):
    """Aggiunge un evento di test."""
    push_event(event_type, "test", "GREEN", "GREEN", detail=detail, severity=0)
    print(f"Evento aggiunto: [{event_type}] {detail}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    cmd = sys.argv[1]

    if cmd == "list":
        if len(sys.argv) > 2:
            arg = sys.argv[2]
            limit = 500 if arg == "all" else int(arg)
        else:
            limit = 50
        cmd_list(limit)

    elif cmd == "count":
        cmd_count()

    elif cmd == "clear":
        cmd_clear()

    elif cmd == "delete":
        if len(sys.argv) < 3:
            print("Uso: python manage_events.py delete <event_id>")
            sys.exit(1)
        cmd_delete(sys.argv[2])

    elif cmd == "add":
        if len(sys.argv) < 4:
            print("Uso: python manage_events.py add <tipo> <descrizione>")
            print("  tipo: global, monitor, sensor")
            print("  esempio: python manage_events.py add global 'Test evento manuale'")
            sys.exit(1)
        event_type = sys.argv[2]
        detail = " ".join(sys.argv[3:])
        cmd_add(event_type, detail)

    else:
        print(f"Comando sconosciuto: {cmd}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
