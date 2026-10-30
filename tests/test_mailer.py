"""Test unitari per mailer.py (smtplib mockato, nessuna connessione reale)."""
import smtplib
from datetime import datetime
from unittest.mock import MagicMock

import pytest

import config
import mailer


SECRET_PW = "SuperSegreta!123"
RECIPIENT = "mario.rossi@example.com"


@pytest.fixture
def smtp_conf(monkeypatch):
    monkeypatch.setattr(config, "SMTP_HOST", "smtp.example.com")
    monkeypatch.setattr(config, "SMTP_PORT", 587)
    monkeypatch.setattr(config, "SMTP_USERNAME", "mailer-user")
    monkeypatch.setattr(config, "SMTP_PASSWORD", SECRET_PW)
    monkeypatch.setattr(config, "SMTP_FROM", "noreply@example.com")
    monkeypatch.setattr(config, "SMTP_STARTTLS", True)
    monkeypatch.setattr(config, "PUBLIC_BASE_URL", "https://kuma.example.com")
    monkeypatch.setattr(config, "PASSWORD_RESET_TOKEN_TTL_MINUTES", 30)
    monkeypatch.setattr(config, "ADMIN_NOTIFY_EMAIL", "")


@pytest.fixture
def smtp_mocks(monkeypatch):
    smtp_cls = MagicMock(name="SMTP")
    ssl_cls = MagicMock(name="SMTP_SSL")
    monkeypatch.setattr(mailer.smtplib, "SMTP", smtp_cls)
    monkeypatch.setattr(mailer.smtplib, "SMTP_SSL", ssl_cls)
    return smtp_cls, ssl_cls


@pytest.fixture
def sync_submit(monkeypatch):
    calls = []

    def fake_submit(fn, *args):
        calls.append(args)
        return fn(*args)

    monkeypatch.setattr(mailer, "submit", fake_submit)
    return calls


def _send():
    return mailer.send_email(RECIPIENT, "Oggetto", "testo", "<p>html</p>", "test_ref")


def test_is_configured(smtp_conf, monkeypatch):
    assert mailer.is_configured()
    monkeypatch.setattr(config, "SMTP_PORT", None)
    assert not mailer.is_configured()


def test_port_465_uses_smtp_ssl(smtp_conf, smtp_mocks, monkeypatch):
    smtp_cls, ssl_cls = smtp_mocks
    monkeypatch.setattr(config, "SMTP_PORT", 465)
    monkeypatch.setattr(config, "SMTP_STARTTLS", False)
    assert _send() is True
    ssl_cls.assert_called_once()
    assert ssl_cls.call_args.kwargs["timeout"] == 10
    assert "context" in ssl_cls.call_args.kwargs
    smtp_cls.assert_not_called()
    conn = ssl_cls.return_value
    conn.login.assert_called_once_with("mailer-user", SECRET_PW)
    conn.send_message.assert_called_once()
    conn.quit.assert_called_once()


def test_port_587_starttls(smtp_conf, smtp_mocks):
    smtp_cls, ssl_cls = smtp_mocks
    assert _send() is True
    smtp_cls.assert_called_once_with("smtp.example.com", 587, timeout=10)
    conn = smtp_cls.return_value
    conn.starttls.assert_called_once()
    assert "context" in conn.starttls.call_args.kwargs
    conn.send_message.assert_called_once()
    ssl_cls.assert_not_called()


def test_no_login_without_username(smtp_conf, smtp_mocks, monkeypatch):
    smtp_cls, _ = smtp_mocks
    monkeypatch.setattr(config, "SMTP_USERNAME", "")
    assert _send() is True
    smtp_cls.return_value.login.assert_not_called()


def test_port_587_without_starttls_refused(smtp_conf, smtp_mocks, monkeypatch, caplog):
    smtp_cls, ssl_cls = smtp_mocks
    monkeypatch.setattr(config, "SMTP_STARTTLS", False)
    with caplog.at_level("ERROR"):
        assert _send() is False
    smtp_cls.assert_not_called()
    ssl_cls.assert_not_called()
    assert "TLS obbligatorio" in caplog.text


def test_smtp_exception_returns_false_without_leaking(smtp_conf, smtp_mocks, caplog):
    smtp_cls, _ = smtp_mocks
    smtp_cls.return_value.send_message.side_effect = smtplib.SMTPException("boom")
    with caplog.at_level("DEBUG"):
        assert _send() is False
    assert "Invio email fallito ref=test_ref errore=SMTPException" in caplog.text
    assert SECRET_PW not in caplog.text
    assert RECIPIENT not in caplog.text


def test_connection_error_returns_false(smtp_conf, smtp_mocks):
    smtp_cls, _ = smtp_mocks
    smtp_cls.side_effect = OSError("unreachable")
    assert _send() is False


def test_message_is_multipart_text_html(smtp_conf, smtp_mocks):
    smtp_cls, _ = smtp_mocks
    assert _send() is True
    msg = smtp_cls.return_value.send_message.call_args.args[0]
    assert msg.is_multipart()
    types = [p.get_content_type() for p in msg.iter_parts()]
    assert types == ["text/plain", "text/html"]
    assert msg["To"] == RECIPIENT
    assert msg["From"] == "noreply@example.com"
    assert msg["Auto-Submitted"] == "auto-generated"
    assert msg["Date"]
    assert msg["Message-ID"].endswith("@example.com>")


@pytest.mark.parametrize("bad_to", [
    RECIPIENT + "\r\nBcc: attacker@example.com",
    RECIPIENT + "\r\n",
    "non-una-email",
])
def test_invalid_recipient_returns_false(smtp_conf, smtp_mocks, bad_to):
    smtp_cls, ssl_cls = smtp_mocks
    assert mailer.send_email(bad_to, "Oggetto", "t", "<p>h</p>", "ref") is False
    smtp_cls.assert_not_called()
    ssl_cls.assert_not_called()


def test_not_configured_returns_false(smtp_conf, smtp_mocks, monkeypatch):
    smtp_cls, _ = smtp_mocks
    monkeypatch.setattr(config, "SMTP_HOST", "")
    assert _send() is False
    smtp_cls.assert_not_called()


def test_reset_link_email_contains_link_and_duration(smtp_conf, smtp_mocks, sync_submit, monkeypatch):
    smtp_cls, _ = smtp_mocks
    monkeypatch.setattr(config, "PASSWORD_RESET_TOKEN_TTL_MINUTES", 45)
    token = "A" * 43
    mailer.send_reset_link_async("mario", RECIPIENT, token)
    msg = smtp_cls.return_value.send_message.call_args.args[0]
    assert msg["Subject"] == "INVA Dashboard: reimpostazione password"
    text = msg.get_body(("plain",)).get_content()
    html_part = msg.get_body(("html",)).get_content()
    link = f"https://kuma.example.com/reset-password?token={token}"
    assert link in text
    assert link in html_part
    assert "valido per 45 minuti" in text
    assert "valido per 45 minuti" in html_part
    assert "ignora questa email" in text


def test_reset_link_html_escapes_username(smtp_conf, smtp_mocks, sync_submit):
    smtp_cls, _ = smtp_mocks
    mailer.send_reset_link_async("<b>x</b>", RECIPIENT, "B" * 43)
    msg = smtp_cls.return_value.send_message.call_args.args[0]
    html_part = msg.get_body(("html",)).get_content()
    assert "<b>x</b>" not in html_part
    assert "&lt;b&gt;x&lt;/b&gt;" in html_part


def test_confirmation_email_date_format(smtp_conf, smtp_mocks, sync_submit):
    smtp_cls, _ = smtp_mocks
    when = datetime(2026, 10, 30, 9, 5)
    mailer.send_reset_confirmation_async("mario", RECIPIENT, when)
    msg = smtp_cls.return_value.send_message.call_args.args[0]
    assert msg["Subject"] == "INVA Dashboard: password modificata"
    assert "30/10/2026 alle 09:05" in msg.get_body(("plain",)).get_content()


def test_admin_alert_disabled_when_empty(smtp_conf, smtp_mocks, sync_submit):
    mailer.send_admin_alert_async("mario", datetime(2026, 1, 1, 10, 0), "203.0.113.7")
    assert sync_submit == []


def test_admin_alert_invalid_address_warns(smtp_conf, smtp_mocks, sync_submit, monkeypatch, caplog):
    monkeypatch.setattr(config, "ADMIN_NOTIFY_EMAIL", "non valida")
    with caplog.at_level("WARNING"):
        mailer.send_admin_alert_async("mario", datetime(2026, 1, 1, 10, 0), "203.0.113.7")
    assert sync_submit == []
    assert "ADMIN_NOTIFY_EMAIL" in caplog.text


def test_admin_alert_sent(smtp_conf, smtp_mocks, sync_submit, monkeypatch):
    smtp_cls, _ = smtp_mocks
    monkeypatch.setattr(config, "ADMIN_NOTIFY_EMAIL", "admin@example.com")
    mailer.send_admin_alert_async("mario", datetime(2026, 1, 1, 10, 0), "203.0.113.7")
    msg = smtp_cls.return_value.send_message.call_args.args[0]
    assert msg["To"] == "admin@example.com"
    assert msg["Subject"] == "INVA Dashboard: reset password eseguito"
    text = msg.get_body(("plain",)).get_content()
    assert "mario" in text
    assert "IP da cui è stato completato il reset: 203.0.113.7" in text
