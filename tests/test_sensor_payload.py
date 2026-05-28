"""Unit tests for build_sensor_payload()."""
import pytest
from app import build_sensor_payload


class TestBuildSensorPayloadError:
    """Tests for error path — when inverter_data contains an error."""

    def test_error_returns_empty_sensors(self):
        data = {"error": "Timeout connessione a invadcstatus"}
        result = build_sensor_payload(data)
        assert result["sensors"] == []

    def test_error_returns_zero_alert_counts(self):
        data = {"error": "Connection refused"}
        result = build_sensor_payload(data)
        assert result["sensor_alerts"] == {"warning_count": 0, "critical_count": 0}

    def test_error_returns_sensor_error_field(self):
        msg = "Timeout connessione a invadcstatus"
        data = {"error": msg}
        result = build_sensor_payload(data)
        assert result["sensor_error"] == msg

    def test_error_returns_empty_sensor_history(self):
        data = {"error": "some error"}
        result = build_sensor_payload(data)
        assert result["sensor_history"] == {}

    def test_error_preserves_thresholds_if_present(self):
        thresholds = {"temperature": {"warning": 35, "critical": 45}}
        data = {"error": "fail", "thresholds": thresholds}
        result = build_sensor_payload(data)
        assert result["thresholds"] == thresholds

    def test_error_returns_empty_thresholds_if_missing(self):
        data = {"error": "fail"}
        result = build_sensor_payload(data)
        assert result["thresholds"] == {}


class TestBuildSensorPayloadSuccess:
    """Tests for success path — when inverter_data has no error."""

    def test_returns_all_sensors(self):
        sensors = [
            {"id": "S1", "name": "S1", "category": "temperature", "value": 25.0, "unit": "°C"},
            {"id": "S2", "name": "S2", "category": "power", "value": 10.0, "unit": "kW"},
        ]
        data = {"sensors": sensors, "thresholds": {}, "history": {}}
        result = build_sensor_payload(data)
        assert result["sensors"] == sensors

    def test_returns_thresholds(self):
        thresholds = {
            "temperature": {"warning": 35.0, "critical": 45.0},
            "power": {"warning": 5.0, "critical": 2.0},
        }
        data = {"sensors": [], "thresholds": thresholds, "history": {}}
        result = build_sensor_payload(data)
        assert result["thresholds"] == thresholds

    def test_returns_sensor_history(self):
        history = {"S1": [{"t": "2024-01-01T00:00:00", "v": 23.0}]}
        data = {"sensors": [], "thresholds": {}, "history": history}
        result = build_sensor_payload(data)
        assert result["sensor_history"] == history

    def test_no_sensor_error_field_on_success(self):
        data = {"sensors": [], "thresholds": {}, "history": {}}
        result = build_sensor_payload(data)
        assert "sensor_error" not in result

    def test_counts_warnings(self):
        sensors = [
            {"id": "S1", "name": "S1", "category": "temperature", "value": 40.0, "unit": "°C"},
        ]
        thresholds = {"temperature": {"warning": 35.0, "critical": 45.0}}
        data = {"sensors": sensors, "thresholds": thresholds, "history": {}}
        result = build_sensor_payload(data)
        assert result["sensor_alerts"]["warning_count"] == 1
        assert result["sensor_alerts"]["critical_count"] == 0

    def test_counts_criticals(self):
        sensors = [
            {"id": "S1", "name": "S1", "category": "temperature", "value": 50.0, "unit": "°C"},
        ]
        thresholds = {"temperature": {"warning": 35.0, "critical": 45.0}}
        data = {"sensors": sensors, "thresholds": thresholds, "history": {}}
        result = build_sensor_payload(data)
        assert result["sensor_alerts"]["warning_count"] == 0
        assert result["sensor_alerts"]["critical_count"] == 1

    def test_counts_mixed_alerts(self):
        sensors = [
            {"id": "S1", "name": "S1", "category": "temperature", "value": 50.0, "unit": "°C"},
            {"id": "S2", "name": "S2", "category": "temperature", "value": 40.0, "unit": "°C"},
            {"id": "S3", "name": "S3", "category": "power", "value": 1.0, "unit": "kW"},
            {"id": "S4", "name": "S4", "category": "power", "value": 10.0, "unit": "kW"},
        ]
        thresholds = {
            "temperature": {"warning": 35.0, "critical": 45.0},
            "power": {"warning": 5.0, "critical": 2.0},
        }
        data = {"sensors": sensors, "thresholds": thresholds, "history": {}}
        result = build_sensor_payload(data)
        # S1: temp 50 > 45 = critical
        # S2: temp 40 > 35 = warning
        # S3: power 1.0 < 2.0 = critical
        # S4: power 10.0 >= 5.0 = normal
        assert result["sensor_alerts"]["warning_count"] == 1
        assert result["sensor_alerts"]["critical_count"] == 2

    def test_empty_sensors_returns_zero_counts(self):
        data = {"sensors": [], "thresholds": {}, "history": {}}
        result = build_sensor_payload(data)
        assert result["sensor_alerts"] == {"warning_count": 0, "critical_count": 0}
