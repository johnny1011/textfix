import json

import requests


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
):
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": model,
        "instructions": system_prompt,
        "input": text,
        "temperature": temperature,
        "max_output_tokens": max_output_tokens,
    }

    client = session or requests
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
):
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    payload = {
        "model": model,
        "max_tokens": max_output_tokens,
        "messages": [{"role": "user", "content": text}],
    }
    if system_prompt:
        payload["system"] = system_prompt
    if temperature is not None:
        payload["temperature"] = temperature

    client = session or requests
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
