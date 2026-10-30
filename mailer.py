# mailer.py — Invio email (reset password) via SMTP con TLS obbligatorio
#
# - Porta 465: SMTP_SSL (TLS implicito); altre porte: STARTTLS obbligatorio.
# - send_email() non solleva mai: ritorna True/False e logga solo log_ref e il
#   tipo di errore (mai credenziali, destinatario, corpo o token).
# - Gli invii dei builder sono asincroni (ThreadPoolExecutor per processo).
# I valori di configurazione si leggono come config.X così i test possono patcharli.

import html
import logging
import smtplib
import ssl
import threading
from concurrent.futures import ThreadPoolExecutor
from email.message import EmailMessage
from email.utils import formatdate, make_msgid, parseaddr
from urllib.parse import quote

import auth
import config

logger = logging.getLogger("kuma.mailer")

_SMTP_TIMEOUT = 10
_executor: ThreadPoolExecutor | None = None
_executor_lock = threading.Lock()


def is_configured() -> bool:
    """True se host, mittente e porta SMTP sono validi."""
    return bool(config.SMTP_HOST) and bool(config.SMTP_FROM) and isinstance(config.SMTP_PORT, int)


def _open_connection():
    """Apre la connessione SMTP cifrata, oppure None se il TLS non è garantito."""
    ctx = ssl.create_default_context()
    if config.SMTP_PORT == 465:
        return smtplib.SMTP_SSL(config.SMTP_HOST, config.SMTP_PORT, context=ctx, timeout=_SMTP_TIMEOUT)
    if not config.SMTP_STARTTLS:
        logger.error("TLS obbligatorio: invio rifiutato")
        return None
    conn = smtplib.SMTP(config.SMTP_HOST, config.SMTP_PORT, timeout=_SMTP_TIMEOUT)
    try:
        conn.ehlo()
        conn.starttls(context=ctx)
        conn.ehlo()
    except BaseException:
        conn.close()
        raise
    return conn


def _msgid_domain() -> str | None:
    address = parseaddr(config.SMTP_FROM)[1]
    _, sep, domain = address.rpartition("@")
    return domain if sep and domain else None


def send_email(to: str, subject: str, text: str, html_body: str, log_ref: str) -> bool:
    """Invia un'email multipart (testo + HTML). Non solleva mai eccezioni."""
    if not is_configured():
        logger.error("Invio email fallito ref=%s errore=%s", log_ref, "NotConfigured")
        return False
    try:
        if not isinstance(to, str) or "\r" in to or "\n" in to:
            raise ValueError("destinatario non valido")
        recipient = auth.validate_email(to)

        msg = EmailMessage()
        msg["From"] = config.SMTP_FROM
        msg["To"] = recipient
        msg["Subject"] = subject
        msg["Date"] = formatdate(localtime=True)
        msg["Message-ID"] = make_msgid(domain=_msgid_domain())
        msg["Auto-Submitted"] = "auto-generated"
        msg.set_content(text)
        msg.add_alternative(html_body, subtype="html")

        conn = _open_connection()
        if conn is None:
            return False
        try:
            if config.SMTP_USERNAME:
                conn.login(config.SMTP_USERNAME, config.SMTP_PASSWORD)
            conn.send_message(msg)
        finally:
            try:
                conn.quit()
            except (smtplib.SMTPException, OSError):
                conn.close()
        return True
    except (smtplib.SMTPException, ssl.SSLError, OSError, ValueError) as e:
        logger.error("Invio email fallito ref=%s errore=%s", log_ref, type(e).__name__)
        return False


def _log_future_exception(future) -> None:
    exc = future.exception()
    if exc is not None:
        logger.error("Errore imprevisto nel thread mailer: %s", type(exc).__name__)


def submit(fn, *args) -> None:
    """Esegue fn(*args) in background (executor creato lazy, per processo)."""
    global _executor
    with _executor_lock:
        if _executor is None:
            _executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="mailer")
    future = _executor.submit(fn, *args)
    future.add_done_callback(_log_future_exception)


def _format_when(when) -> str:
    return when.strftime("%d/%m/%Y alle %H:%M")


def _html_page(paragraphs: list[str]) -> str:
    """Paragrafi già escapati -> documento HTML minimale."""
    body = "\n".join(f"<p>{p}</p>" for p in paragraphs)
    return f'<!DOCTYPE html>\n<html lang="it"><body>\n{body}\n</body></html>'


# ----------------------------------------------------------------------
# Builder
# ----------------------------------------------------------------------

def send_reset_link_async(username: str, email: str, token: str) -> None:
    """Email con il link di reimpostazione password."""
    if not config.PUBLIC_BASE_URL:
        logger.error("Invio email fallito ref=%s errore=%s", "reset_link", "PublicBaseUrlMissing")
        return
    link = f"{config.PUBLIC_BASE_URL}/reset-password?token={quote(token)}"
    minutes = config.PASSWORD_RESET_TOKEN_TTL_MINUTES
    subject = "INVA Dashboard: reimpostazione password"
    text = (
        f"Ciao {username},\n\n"
        "è stata richiesta la reimpostazione della password del tuo account INVA Dashboard.\n"
        f"Per scegliere una nuova password apri questo link:\n\n{link}\n\n"
        f"Il link è valido per {minutes} minuti e può essere usato una sola volta.\n"
        "Dopo il reset il 2FA verrà reimpostato e tutte le sessioni chiuse: "
        "al prossimo accesso dovrai riconfigurare il 2FA.\n\n"
        "Se non hai richiesto tu il reset, ignora questa email: la password resta invariata.\n"
    )
    e_link = html.escape(link, quote=True)
    html_body = _html_page([
        f"Ciao {html.escape(username)},",
        "è stata richiesta la reimpostazione della password del tuo account INVA Dashboard.",
        f'Per scegliere una nuova password apri questo link:<br><a href="{e_link}">{e_link}</a>',
        f"Il link è valido per {html.escape(str(minutes))} minuti e può essere usato una sola volta.",
        "Dopo il reset il 2FA verrà reimpostato e tutte le sessioni chiuse: "
        "al prossimo accesso dovrai riconfigurare il 2FA.",
        "Se non hai richiesto tu il reset, ignora questa email: la password resta invariata.",
    ])
    submit(send_email, email, subject, text, html_body, "reset_link")


def send_reset_confirmation_async(username: str, email: str, when) -> None:
    """Email di conferma della password modificata."""
    when_s = _format_when(when)
    subject = "INVA Dashboard: password modificata"
    sentence = (
        f"La tua password è stata modificata il {when_s}. "
        "Il 2FA è stato reimpostato: al prossimo accesso dovrai riconfigurarlo. "
        "Se non sei stato tu contatta l'amministratore."
    )
    text = f"Ciao {username},\n\n{sentence}\n"
    html_body = _html_page([f"Ciao {html.escape(username)},", html.escape(sentence)])
    submit(send_email, email, subject, text, html_body, "reset_confirmation")


def send_admin_alert_async(username: str, when, ip: str) -> None:
    """Avviso all'amministratore (solo se ADMIN_NOTIFY_EMAIL è valida)."""
    admin = config.ADMIN_NOTIFY_EMAIL
    if not admin:
        return
    try:
        admin = auth.validate_email(admin)
    except ValueError:
        logger.warning("ADMIN_NOTIFY_EMAIL non valida: avviso admin non inviato")
        return
    when_s = _format_when(when)
    subject = "INVA Dashboard: reset password eseguito"
    lines = [
        "È stato completato un reset password self-service.",
        f"Utente: {username}",
        f"Data: {when_s}",
        f"IP da cui è stato completato il reset: {ip}",
    ]
    text = "\n".join(lines) + "\n"
    html_body = _html_page([html.escape(line) for line in lines])
    submit(send_email, admin, subject, text, html_body, "admin_alert")
