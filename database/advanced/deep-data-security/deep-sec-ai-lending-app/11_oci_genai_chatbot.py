import json
import os
import re
from pathlib import Path

import oci
from dotenv import load_dotenv
from oci.generative_ai_inference import GenerativeAiInferenceClient
from oci.generative_ai_inference.models import (
    ChatDetails,
    GenericChatRequest,
    Message,
    OnDemandServingMode,
    UserMessage,
)

from deal_tools import (
    get_application_detail,
    get_loan_applications,
    search_policies,
)


load_dotenv()


TOOLS = {
    "get_loan_applications": get_loan_applications,
    "get_application_detail": get_application_detail,
    "search_policies": search_policies,
}


def required_env(name):
    value = os.getenv(name)
    if value:
        value = value.strip().strip('"').strip("'")
    if (
        not value
        or value.startswith("replace-")
        or value.startswith("your-")
        or "replace" in value.lower()
    ):
        raise RuntimeError(f"Set {name} in .env before running this script.")
    return value


def oci_client():
    config_file = Path(os.getenv("OCI_CONFIG_FILE", "~/.oci/config")).expanduser()
    profile = os.getenv("OCI_PROFILE", "DEFAULT")
    config = oci.config.from_file(str(config_file), profile)
    return GenerativeAiInferenceClient(
        config=config,
        service_endpoint=required_env("OCI_GENAI_ENDPOINT"),
    )


def message_text(chat_response):
    data = chat_response.data
    if hasattr(data, "chat_response") and hasattr(data.chat_response, "choices"):
        choice = data.chat_response.choices[0]
        return choice.message.content[0].text
    serialized = oci.util.to_dict(data)
    return json.dumps(serialized)


def chat_once(client, prompt):
    request = GenericChatRequest(
        api_format=GenericChatRequest.API_FORMAT_GENERIC,
        messages=[
            UserMessage(
                role=Message.ROLE_USER,
                content=[{"type": "TEXT", "text": prompt}],
            )
        ],
        max_tokens=500,
        temperature=0,
    )
    details = ChatDetails(
        compartment_id=required_env("OCI_GENAI_COMPARTMENT_ID"),
        serving_mode=OnDemandServingMode(model_id=required_env("OCI_GENAI_MODEL_ID")),
        chat_request=request,
    )
    return message_text(client.chat(details))


def choose_action(client, end_user, question):
    prompt = f"""
You are DEAL, a lending assistant running as end user {end_user}.
Choose exactly one tool call for the user's request.
Return only JSON with keys tool and arguments.

Available tools:
- get_loan_applications: {{}}
- get_application_detail: {{"app_id": number}}
- search_policies: {{"query": string}}

User request: {question}
"""
    raw = chat_once(client, prompt).strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw, re.DOTALL)
        if fenced:
            return json.loads(fenced.group(1))
        start = raw.find("{")
        end = raw.rfind("}")
        if start >= 0 and end > start:
            return json.loads(raw[start : end + 1])
        raise


def run_tool(end_user, action):
    tool_name = action["tool"]
    arguments = action.get("arguments", {})
    if tool_name not in TOOLS:
        raise ValueError(f"Unknown tool requested by model: {tool_name}")
    return TOOLS[tool_name](end_user, **arguments)


def answer_with_result(client, end_user, question, action, result):
    prompt = f"""
You are DEAL, a lending assistant running as end user {end_user}.
The database has already enforced Oracle Deep Data Security.
Answer the user briefly from the tool result only.
If the tool result is a list of loan applications, count the list and list the id values exactly.
If the tool result is a list of policies, list only the returned policy titles.
Do not say that no rows or policies were found unless the tool result is an empty list.

User request: {question}
Tool action: {json.dumps(action)}
Tool result: {json.dumps(result, default=str)}
"""
    return chat_once(client, prompt)


def run_session(client, end_user, questions):
    print(f"\n========================")
    print(f"OCI GenAI DEAL session: {end_user}")
    print(f"========================")
    for question in questions:
        action = choose_action(client, end_user, question)
        result = run_tool(end_user, action)
        answer = answer_with_result(client, end_user, question, action, result)
        print(f"\nUser: {question}")
        print(f"Tool: {action['tool']} {action.get('arguments', {})}")
        print(f"DEAL: {answer}")


client = oci_client()

run_session(
    client,
    "linda",
    [
        "Which loan applications can I see?",
        "Find policy guidance about credit risk.",
    ],
)

run_session(
    client,
    "wendy",
    [
        "Which applications are in my underwriting queue?",
        "Find policy guidance about credit risk.",
    ],
)
