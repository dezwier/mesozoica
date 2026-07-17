"""Tests for Gemini Imagen client retry behavior."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.services.image_generation_service.client import (
    ImageGenerationError,
    generate_image_with_gemini,
    is_retryable_generation_error,
)


def test_is_retryable_generation_error_detects_service_unavailable():
    assert is_retryable_generation_error("The service is currently unavailable.")
    assert is_retryable_generation_error("HTTP 503: overloaded")
    assert is_retryable_generation_error(
        "Image generation failed with the following error: Fail to execute model for flow_id: flow-vertex-juno-v1-5-serving_default"
    )
    assert not is_retryable_generation_error("Invalid API key")


@patch("app.services.image_generation_service.client.time.sleep")
@patch("app.services.image_generation_service.client._generate_image_once")
def test_generate_image_retries_transient_503(mock_once, mock_sleep):
    mock_once.side_effect = [
        ImageGenerationError("The service is currently unavailable."),
        (b"png-bytes", {"images_generated": 1, "cost_usd": 0.06, "model_name": "test"}),
    ]

    image_bytes, usage = generate_image_with_gemini("test prompt")

    assert image_bytes == b"png-bytes"
    assert usage["images_generated"] == 1
    assert mock_once.call_count == 2
    mock_sleep.assert_called_once()


@patch("app.services.image_generation_service.client._generate_with_retries")
@patch("app.services.image_generation_service.client.settings")
def test_generate_image_falls_back_to_standard_model(mock_settings, mock_with_retries):
    mock_settings.gemini_image_model = "imagen-4.0-ultra-generate-001"
    mock_with_retries.side_effect = [
        ImageGenerationError("Fail to execute model for flow_id: flow-vertex-juno"),
        (b"png-bytes", {"images_generated": 1, "cost_usd": 0.04, "model_name": "imagen-4.0-generate-001"}),
    ]

    image_bytes, usage = generate_image_with_gemini("test prompt")

    assert image_bytes == b"png-bytes"
    assert mock_with_retries.call_count == 2
    assert mock_with_retries.call_args_list[0].kwargs["model_name"] == "imagen-4.0-ultra-generate-001"
    assert mock_with_retries.call_args_list[1].kwargs["model_name"] == "imagen-4.0-generate-001"


@patch("app.services.image_generation_service.client.settings")
@patch("app.services.image_generation_service.client.requests.post")
def test_generate_image_does_not_retry_auth_errors(mock_post, mock_settings):
    mock_settings.google_gemini_api_key = "test-key"
    mock_settings.gemini_image_model = "imagen-4.0-ultra-generate-001"

    fail_response = MagicMock()
    fail_response.ok = False
    fail_response.status_code = 401
    fail_response.json.return_value = {"error": {"message": "Invalid API key"}}
    fail_response.text = "unauthorized"
    mock_post.return_value = fail_response

    with pytest.raises(ImageGenerationError, match="Invalid API key"):
        generate_image_with_gemini("test prompt")

    assert mock_post.call_count == 1
