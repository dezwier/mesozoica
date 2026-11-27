"""Tests for OpenAI image client retry behavior."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.services.image_generation_service.client import (
    ImageGenerationError,
    generate_image_with_openai,
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

    image_bytes, usage = generate_image_with_openai("test prompt")

    assert image_bytes == b"png-bytes"
    assert usage["images_generated"] == 1
    assert mock_once.call_count == 2
    mock_sleep.assert_called_once()


@patch("app.services.image_generation_service.client._generate_with_retries")
@patch("app.services.image_generation_service.client.settings")
def test_generate_image_falls_back_to_fast_model(mock_settings, mock_with_retries):
    mock_settings.openai_api_key = "test-key"
    mock_settings.openai_image_model = "gpt-image-2.5-flare"
    mock_settings.openai_image_size = "1024x1024"
    mock_settings.openai_image_quality = "low"
    mock_with_retries.side_effect = [
        ImageGenerationError("Fail to execute model for flow_id: flow-vertex-juno"),
        (b"png-bytes", {"images_generated": 1, "cost_usd": 0.02, "model_name": "gpt-image-1-mini"}),
    ]

    image_bytes, usage = generate_image_with_openai("test prompt")

    assert image_bytes == b"png-bytes"
    assert mock_with_retries.call_count == 2
    assert mock_with_retries.call_args_list[0].kwargs["model_name"] == "gpt-image-2.5-flare"
    assert mock_with_retries.call_args_list[1].kwargs["model_name"] == "gpt-image-1-mini"


@patch("app.services.image_generation_service.client._generate_with_retries")
@patch("app.services.image_generation_service.client.settings")
def test_generate_image_does_not_fallback_for_deprecated_model_error(mock_settings, mock_with_retries):
    mock_settings.openai_api_key = "test-key"
    mock_settings.openai_image_model = "gpt-image-2.5-flare"
    mock_settings.openai_image_size = "1024x1024"
    mock_settings.openai_image_quality = "low"
    mock_with_retries.side_effect = ImageGenerationError(
        "This model gpt-image-legacy is no longer available to new users."
    )

    with pytest.raises(ImageGenerationError, match="no longer available"):
        generate_image_with_openai("test prompt")

    assert mock_with_retries.call_count == 1


@patch("app.services.image_generation_service.client.settings")
@patch("app.services.image_generation_service.client.requests.post")
def test_generate_image_does_not_retry_auth_errors(mock_post, mock_settings):
    mock_settings.openai_api_key = "test-key"
    mock_settings.openai_image_model = "gpt-image-2.5-flare"
    mock_settings.openai_image_size = "1024x1024"
    mock_settings.openai_image_quality = "low"

    fail_response = MagicMock()
    fail_response.ok = False
    fail_response.status_code = 401
    fail_response.json.return_value = {"error": {"message": "Invalid API key"}}
    fail_response.text = "unauthorized"
    mock_post.return_value = fail_response

    with pytest.raises(ImageGenerationError, match="Invalid API key"):
        generate_image_with_openai("test prompt")

    assert mock_post.call_count == 1
