import pytest
from unittest.mock import MagicMock, patch
from backend.src.utils.notifier import send_alert, _resolve_queue_url


def test_resolve_queue_url():
    arn = "arn:aws:sqs:us-east-1:430118856212:telegram-bot-stack-queue"
    url, region = _resolve_queue_url(arn)
    assert url == "https://sqs.us-east-1.amazonaws.com/430118856212/telegram-bot-stack-queue"
    assert region == "us-east-1"

    direct_url = "https://sqs.us-east-1.amazonaws.com/430118856212/otra-cola"
    url2, region2 = _resolve_queue_url(direct_url)
    assert url2 == direct_url
    assert region2 is None


def test_send_alert_no_url_configured(monkeypatch):
    monkeypatch.delenv("ALERTS_QUEUE", raising=False)
    result = send_alert("Mensaje de prueba")
    assert result is False


def test_send_alert_with_arn(monkeypatch):
    monkeypatch.setenv("ALERTS_QUEUE", "arn:aws:sqs:us-east-1:430118856212:telegram-bot-stack-queue")
    
    mock_sqs = MagicMock()
    with patch("boto3.client", return_value=mock_sqs) as mock_boto:
        result = send_alert("Alerta con ARN")
        assert result is True
        mock_boto.assert_called_once_with("sqs", region_name="us-east-1")
        mock_sqs.send_message.assert_called_once_with(
            QueueUrl="https://sqs.us-east-1.amazonaws.com/430118856212/telegram-bot-stack-queue",
            MessageBody="Alerta con ARN"
        )


def test_send_alert_with_direct_url(monkeypatch):
    monkeypatch.setenv("ALERTS_QUEUE", "https://sqs.us-east-1.amazonaws.com/123456789012/direct-queue")
    
    mock_sqs = MagicMock()
    with patch("boto3.client", return_value=mock_sqs) as mock_boto:
        result = send_alert("Alerta con URL directa")
        assert result is True
        mock_sqs.send_message.assert_called_once_with(
            QueueUrl="https://sqs.us-east-1.amazonaws.com/123456789012/direct-queue",
            MessageBody="Alerta con URL directa"
        )


def test_send_alert_failure_does_not_raise(monkeypatch):
    monkeypatch.setenv("ALERTS_QUEUE", "arn:aws:sqs:us-east-1:430118856212:telegram-bot-stack-queue")
    
    mock_sqs = MagicMock()
    mock_sqs.send_message.side_effect = Exception("SQS Service Unavailable")
    with patch("boto3.client", return_value=mock_sqs):
        result = send_alert("Alerta que fallará")
        assert result is False
