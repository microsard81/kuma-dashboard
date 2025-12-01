# send_test_push.py

import sys
from push_utils import send_push_to_all

def main():
    title = "🔔 Notifica di importante"
    body = "Questa è una notifica inviata manualmente dalla tua dashboard IN.VA."

    if len(sys.argv) > 1:
        body = " ".join(sys.argv[1:])

    print("Invio notifica ai dispositivi iscritti...")
    send_push_to_all(title, body, {"test": True})
    print("Fatto! (se nessuna notifica arriva, verifica che il device sia iscritto)")

if __name__ == "__main__":
    main()
