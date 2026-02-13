import json

import requests

_session = requests.Session()


_CONTEXT_PROMPT_SUFFIX = (
    "\n\nThe user has provided surrounding context in <context> tags. "
    "Use it to understand tone, topic, and intent. Fix only the text "
    "inside <text_to_fix> tags. Return only the corrected text, without any tags."
)


def _format_input_with_context(text, context):
    if not context:
        return text
    return (
        f"<context>\n{context}\n</context>\n\n"
        f"<text_to_fix>\n{text}\n</text_to_fix>"
    )


def extract_output_text(payload):
    output = []
    for item in payload.get("output", []):
        if item.get("type") != "message":
            continue
        for content in item.get("content", []):
            if content.get("type") == "output_text":
                output.append(content.get("text", ""))
    return "".join(output).strip()


def extract_anthropic_text(payload):
    output = []
    for item in payload.get("content", []):
        if item.get("type") == "text":
            output.append(item.get("text", ""))
    return "".join(output).strip()


def rewrite_text(
    text,
    api_key,
    model,
    system_prompt,
    temperature,
    max_output_tokens,
    timeout=30,
    session=None,
    context=None,
):
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    input_text = _format_input_with_context(text, context)
    effective_prompt = system_prompt
    if context:
        effective_prompt = system_prompt + _CONTEXT_PROMPT_SUFFIX
    payload = {
        "model": model,
        "instructions": effective_prompt,
        "input": input_text,
        "temperature": temperature,
        "max_output_tokens": max_output_tokens,
    }

    client = session or _session
    try:
        response = client.post(
            "https://api.openai.com/v1/responses",
            headers=headers,
            json=payload,
            timeout=timeout,
        )
    except requests.RequestException as exc:
        return "", f"Network error: {exc}"

    if response.status_code >= 400:
        detail = ""
        try:
            data = response.json()
            detail = data.get("error", {}).get("message", "")
            if not detail:
                detail = json.dumps(data)
        except ValueError:
            detail = getattr(response, "text", "").strip()
        message = f"API error {response.status_code}"
        if detail:
            message = f"{message}: {detail}"
        return "", message

    try:
        data = response.json()
    except ValueError:
        return "", "Invalid response from server."

    return extract_output_text(data), ""


def rewrite_text_anthropic(
    text,
    api_key,
    model,
    system_prompt,
    temperature,
    max_output_tokens,
    timeout=30,
    session=None,
    context=None,
):
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    input_text = _format_input_with_context(text, context)
    effective_prompt = system_prompt
    if context:
        effective_prompt = system_prompt + _CONTEXT_PROMPT_SUFFIX
    payload = {
        "model": model,
        "max_tokens": max_output_tokens,
        "messages": [{"role": "user", "content": input_text}],
    }
    if effective_prompt:
        payload["system"] = effective_prompt
    if temperature is not None:
        payload["temperature"] = temperature

    client = session or _session
    try:
        response = client.post(
            "https://api.anthropic.com/v1/messages",
            headers=headers,
            json=payload,
            timeout=timeout,
        )
    except requests.RequestException as exc:
        return "", f"Network error: {exc}"

    if response.status_code >= 400:
        detail = ""
        try:
            data = response.json()
            detail = data.get("error", {}).get("message", "")
            if not detail:
                detail = data.get("message", "")
            if not detail:
                detail = json.dumps(data)
        except ValueError:
            detail = getattr(response, "text", "").strip()
        message = f"API error {response.status_code}"
        if detail:
            message = f"{message}: {detail}"
        return "", message

    try:
        data = response.json()
    except ValueError:
        return "", "Invalid response from server."

    return extract_anthropic_text(data), ""
