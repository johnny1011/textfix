import unittest
from unittest.mock import patch

import requests

import textfix_core


class FakeResponse:
    def __init__(self, status_code=200, json_data=None, text=""):
        self.status_code = status_code
        self._json_data = json_data
        self.text = text

    def json(self):
        if isinstance(self._json_data, Exception):
            raise self._json_data
        return self._json_data


class TestExtractOutputText(unittest.TestCase):
    def test_extracts_output_text(self):
        payload = {
            "output": [
                {
                    "type": "message",
                    "content": [
                        {"type": "output_text", "text": "Hello"},
                        {"type": "output_text", "text": " world"},
                    ],
                }
            ]
        }
        self.assertEqual(textfix_core.extract_output_text(payload), "Hello world")

    def test_ignores_non_message(self):
        payload = {
            "output": [
                {"type": "other", "content": [{"type": "output_text", "text": "Nope"}]},
                {"type": "message", "content": [{"type": "output_text", "text": "Yep"}]},
            ]
        }
        self.assertEqual(textfix_core.extract_output_text(payload), "Yep")


class TestRewriteText(unittest.TestCase):
    @patch("textfix_core.requests.post")
    def test_rewrite_text_success(self, mock_post):
        payload = {
            "output": [
                {"type": "message", "content": [{"type": "output_text", "text": "Fixed"}]}
            ]
        }
        mock_post.return_value = FakeResponse(status_code=200, json_data=payload)
        text, error = textfix_core.rewrite_text(
            "hi",
            "key",
            "model",
            "prompt",
            0.0,
            16,
        )
        self.assertEqual(text, "Fixed")
        self.assertEqual(error, "")

    @patch("textfix_core.requests.post")
    def test_rewrite_text_api_error(self, mock_post):
        mock_post.return_value = FakeResponse(
            status_code=401, json_data={"error": {"message": "bad key"}}
        )
        text, error = textfix_core.rewrite_text(
            "hi",
            "key",
            "model",
            "prompt",
            0.0,
            16,
        )
        self.assertEqual(text, "")
        self.assertIn("API error 401", error)
        self.assertIn("bad key", error)

    @patch("textfix_core.requests.post")
    def test_rewrite_text_network_error(self, mock_post):
        mock_post.side_effect = requests.RequestException("boom")
        text, error = textfix_core.rewrite_text(
            "hi",
            "key",
            "model",
            "prompt",
            0.0,
            16,
        )
        self.assertEqual(text, "")
        self.assertIn("Network error", error)

    @patch("textfix_core.requests.post")
    def test_rewrite_text_invalid_json(self, mock_post):
        mock_post.return_value = FakeResponse(
            status_code=200, json_data=ValueError("bad json")
        )
        text, error = textfix_core.rewrite_text(
            "hi",
            "key",
            "model",
            "prompt",
            0.0,
            16,
        )
        self.assertEqual(text, "")
        self.assertEqual(error, "Invalid response from server.")


class TestRewriteTextAnthropic(unittest.TestCase):
    @patch("textfix_core.requests.post")
    def test_rewrite_text_anthropic_success(self, mock_post):
        payload = {"content": [{"type": "text", "text": "Fixed"}]}
        mock_post.return_value = FakeResponse(status_code=200, json_data=payload)
        text, error = textfix_core.rewrite_text_anthropic(
            "hi",
            "key",
            "claude-3-7-sonnet-20250219",
            "prompt",
            0.0,
            16,
        )
        self.assertEqual(text, "Fixed")
        self.assertEqual(error, "")

    @patch("textfix_core.requests.post")
    def test_rewrite_text_anthropic_api_error(self, mock_post):
        mock_post.return_value = FakeResponse(
            status_code=401, json_data={"error": {"message": "bad key"}}
        )
        text, error = textfix_core.rewrite_text_anthropic(
            "hi",
            "key",
            "claude-3-7-sonnet-20250219",
            "prompt",
            0.0,
            16,
        )
        self.assertEqual(text, "")
        self.assertIn("API error 401", error)
        self.assertIn("bad key", error)


if __name__ == "__main__":
    unittest.main()
