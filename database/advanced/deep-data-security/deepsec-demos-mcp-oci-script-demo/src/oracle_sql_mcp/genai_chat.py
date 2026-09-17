# Copyright (c) 2026, Oracle and/or its affiliates.
# Adapts OCI Generative AI native function calls to the client-owned MCP tool loop.
# Depends on the OCI Python SDK and this package's GenAI configuration.

"""Native OCI Generative AI function-calling adapter for MCP tools."""

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from typing import Any

import oci

from .config import GenAISettings


@dataclass(frozen=True)
class RequestedToolCall:
    id: str
    name: str
    arguments: dict[str, Any]


@dataclass(frozen=True)
class ModelTurn:
    text: str
    tool_calls: list[RequestedToolCall]


class OCIChat:
    """Map OCI Generic Chat function calls to the CLI-owned MCP tool loop."""

    def __init__(self, settings: GenAISettings, system_prompt: str, tools: list[Any]) -> None:
        settings.require()
        self._impl: _ChatImplementation = _GenericOCIChat(settings, system_prompt, tools)

    async def ask(self, user_text: str) -> ModelTurn:
        return await self._impl.ask(user_text)

    async def continue_after_tools(self, results: list[tuple[RequestedToolCall, str]]) -> ModelTurn:
        return await self._impl.continue_after_tools(results)


class _ChatImplementation:
    async def ask(self, user_text: str) -> ModelTurn:
        raise NotImplementedError

    async def continue_after_tools(self, results: list[tuple[RequestedToolCall, str]]) -> ModelTurn:
        raise NotImplementedError


class _GenericOCIChat(_ChatImplementation):
    """OCI native Generic Chat API implementation."""

    def __init__(self, settings: GenAISettings, system_prompt: str, tools: list[Any]) -> None:
        self._settings = settings
        self._system_prompt = system_prompt
        self._tools = [
            oci.generative_ai_inference.models.FunctionDefinition(
                name=tool.name,
                description=tool.description or "",
                parameters=tool.inputSchema,
            )
            for tool in tools
        ]
        config = oci.config.from_file(settings.oci_config_file, settings.oci_profile)
        signer = _signer_from_config(config, settings.auth_type)
        self._client = oci.generative_ai_inference.GenerativeAiInferenceClient(
            config, service_endpoint=settings.endpoint, signer=signer
        )
        models = oci.generative_ai_inference.models
        self._messages: list[Any] = [
            models.SystemMessage(content=[models.TextContent(text=system_prompt)])
        ]

    async def ask(self, user_text: str) -> ModelTurn:
        models = oci.generative_ai_inference.models
        self._messages.append(models.UserMessage(content=[models.TextContent(text=user_text)]))
        return await self._run_chat()

    async def continue_after_tools(self, results: list[tuple[RequestedToolCall, str]]) -> ModelTurn:
        models = oci.generative_ai_inference.models
        for tool_call, result in results:
            self._messages.append(
                models.ToolMessage(
                    tool_call_id=tool_call.id,
                    content=[models.TextContent(text=result)],
                )
            )
        return await self._run_chat()

    async def _run_chat(self) -> ModelTurn:
        return await asyncio.to_thread(self._run_chat_sync)

    def _run_chat_sync(self) -> ModelTurn:
        models = oci.generative_ai_inference.models
        request = models.GenericChatRequest(
            messages=self._messages,
            tools=self._tools,
            tool_choice=models.ToolChoiceAuto(),
            max_tokens=self._settings.max_tokens,
            is_parallel_tool_calls=False,
        )
        response = self._client.chat(
            models.ChatDetails(
                compartment_id=self._settings.compartment_id,
                serving_mode=models.OnDemandServingMode(model_id=self._settings.model_id),
                chat_request=request,
            )
        ).data.chat_response
        choice = response.choices[0]
        message = choice.message
        self._messages.append(message)

        text_parts: list[str] = []
        tool_calls: list[RequestedToolCall] = []
        for content in message.content or []:
            if isinstance(content, models.TextContent):
                text_parts.append(content.text)
        for function_call in message.tool_calls or []:
            if not isinstance(function_call, models.FunctionCall):
                raise RuntimeError(f"Unsupported OCI tool call type: {function_call.type}")
            raw_arguments = function_call.arguments or "{}"
            try:
                arguments = json.loads(raw_arguments)
            except json.JSONDecodeError as exc:
                raise RuntimeError(
                    f"Model returned invalid arguments for {function_call.name}: {raw_arguments}"
                ) from exc
            if not isinstance(arguments, dict):
                raise RuntimeError(f"Model returned non-object arguments for {function_call.name}.")
            tool_calls.append(
                RequestedToolCall(
                    id=function_call.id, name=function_call.name, arguments=arguments
                )
            )
        return ModelTurn(text="\n".join(part for part in text_parts if part).strip(), tool_calls=tool_calls)


def _signer_from_config(config: dict[str, str], auth_type: str = "auto"):
    """Create the OCI signer specified by an API-key or session-token profile.

    OCI session-token profiles contain ``security_token_file`` and ``key_file``.
    API-key profiles use ``tenancy``, ``user``, ``fingerprint``, and ``key_file``.
    Constructing both explicitly avoids relying on SDK defaults and keeps this
    client aligned with the profile that the OCI CLI validates.
    """
    token_file = config.get("security_token_file", "").strip()
    key_file = config.get("key_file", "").strip()
    if not key_file:
        raise RuntimeError("OCI profile is missing key_file.")
    use_security_token = auth_type == "security_token" or (
        auth_type == "auto" and bool(token_file)
    )
    if not use_security_token:
        required = ("tenancy", "user", "fingerprint")
        missing = [name for name in required if not config.get(name, "").strip()]
        if missing:
            raise RuntimeError("OCI API-key profile is missing: " + ", ".join(missing))
        return oci.signer.Signer(
            tenancy=config["tenancy"],
            user=config["user"],
            fingerprint=config["fingerprint"],
            private_key_file_location=key_file,
            pass_phrase=config.get("pass_phrase"),
        )
    if not token_file:
        raise RuntimeError(
            "GENAI_AUTH_TYPE=security_token was selected, but the profile has no security_token_file."
        )
    try:
        with open(token_file, encoding="utf-8") as token_stream:
            token = token_stream.read().strip()
    except OSError as exc:
        raise RuntimeError(f"Unable to read OCI security token file: {token_file}") from exc
    if not token:
        raise RuntimeError(f"OCI security token file is empty: {token_file}")
    private_key = oci.signer.load_private_key_from_file(key_file)
    return oci.auth.signers.SecurityTokenSigner(token, private_key)
