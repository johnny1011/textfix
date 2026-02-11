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
    @patch("textfix_core._session.post")
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

    @patch("textfix_core._session.post")
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

    @patch("textfix_core._session.post")
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

    @patch("textfix_core._session.post")
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
    @patch("textfix_core._session.post")
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

    @patch("textfix_core._session.post")
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


class TestFormatInputWithContext(unittest.TestCase):
    def test_no_context_returns_text_unchanged(self):
        self.assertEqual(textfix_core._format_input_with_context("hello", None), "hello")
        self.assertEqual(textfix_core._format_input_with_context("hello", ""), "hello")

    def test_with_context_wraps_both(self):
        result = textfix_core._format_input_with_context("fix me", "some context")
        self.assertIn("<context>", result)
        self.assertIn("some context", result)
        self.assertIn("<text_to_fix>", result)
        self.assertIn("fix me", result)


class TestRewriteTextWithContext(unittest.TestCase):
    @patch("textfix_core._session.post")
    def test_rewrite_text_with_context(self, mock_post):
        payload = {
            "output": [
                {"type": "message", "content": [{"type": "output_text", "text": "Fixed"}]}
            ]
        }
        mock_post.return_value = FakeResponse(status_code=200, json_data=payload)
        text, error = textfix_core.rewrite_text(
            "hi", "key", "model", "prompt", 0.0, 16, context="email thread here"
        )
        self.assertEqual(text, "Fixed")
        self.assertEqual(error, "")
        sent_payload = mock_post.call_args[1]["json"]
        self.assertIn("<context>", sent_payload["input"])
        self.assertIn("email thread here", sent_payload["input"])
        self.assertIn("<text_to_fix>", sent_payload["input"])
        self.assertIn("hi", sent_payload["input"])
        self.assertIn("context", sent_payload["instructions"])

    @patch("textfix_core._session.post")
    def test_rewrite_text_without_context_no_tags(self, mock_post):
        payload = {
            "output": [
                {"type": "message", "content": [{"type": "output_text", "text": "Fixed"}]}
            ]
        }
        mock_post.return_value = FakeResponse(status_code=200, json_data=payload)
        textfix_core.rewrite_text("hi", "key", "model", "prompt", 0.0, 16, context=None)
        sent_payload = mock_post.call_args[1]["json"]
        self.assertEqual(sent_payload["input"], "hi")
        self.assertEqual(sent_payload["instructions"], "prompt")

    @patch("textfix_core._session.post")
    def test_rewrite_text_anthropic_with_context(self, mock_post):
        payload = {"content": [{"type": "text", "text": "Fixed"}]}
        mock_post.return_value = FakeResponse(status_code=200, json_data=payload)
        text, error = textfix_core.rewrite_text_anthropic(
            "hi", "key", "claude-3-7-sonnet-20250219", "prompt", 0.0, 16,
            context="thread context"
        )
        self.assertEqual(text, "Fixed")
        self.assertEqual(error, "")
        sent_payload = mock_post.call_args[1]["json"]
        self.assertIn("<context>", sent_payload["messages"][0]["content"])
        self.assertIn("thread context", sent_payload["messages"][0]["content"])
        self.assertIn("<text_to_fix>", sent_payload["messages"][0]["content"])
        self.assertIn("context", sent_payload["system"])

    @patch("textfix_core._session.post")
    def test_rewrite_text_anthropic_without_context_no_tags(self, mock_post):
        payload = {"content": [{"type": "text", "text": "Fixed"}]}
        mock_post.return_value = FakeResponse(status_code=200, json_data=payload)
        textfix_core.rewrite_text_anthropic(
            "hi", "key", "claude-3-7-sonnet-20250219", "prompt", 0.0, 16, context=None
        )
        sent_payload = mock_post.call_args[1]["json"]
        self.assertEqual(sent_payload["messages"][0]["content"], "hi")
        self.assertEqual(sent_payload["system"], "prompt")


if __name__ == "__main__":
    unittest.main()
