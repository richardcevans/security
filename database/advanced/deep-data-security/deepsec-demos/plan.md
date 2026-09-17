# Deep Sec AI Demo Labs: Authoring Plan

## Scope

Turn the five `deepsec-demos-*` source directories into five independent
LiveLabs labs. The source directories remain the executable/reference
material; this workshop root contains the learner-facing Markdown and the
LiveLabs Desktop manifest.

Assumption for this first iteration: Desktop/Cloud Shell delivery, about 175
minutes for all five labs after the required OCI, database, and identity
access is available. The exact runtime and delivery variant remain an SME
decision and are recorded in `needs-assistance.md`.

## Lab map and dependency decisions

| Order | LiveLabs lab | Source directory | Dependency decision |
| --- | --- | --- | --- |
| 1 | LangChain HR Agent with OCI IAM | `deepsec-demos-ananya-single-agent-oci-demo` | Independent. Includes ADB/IAM setup scripts and the LangChain app. |
| 2 | OCI IAM-Protected Oracle SQL MCP Server | `deepsec-demos-mcp-oci-script-demo` | Independent. Includes ADB/IAM setup scripts and the local MCP server/client. |
| 3 | Reusable Python Oracle SQL MCP Server | `deepsec-demos-python-mcp-server` | Independent application-only pattern. Requires existing IAM, wallet, database, and MCP resource configuration; may reuse Lab 2 resources but does not require Lab 2. |
| 4 | Select AI Agent Team | `deepsec-demos-select-ai-oci-demo` | Independent. Uses database-native Select AI Agent objects and its own SQL setup. |
| 5 | LangChain HR and Compensation Agents with Microsoft Entra ID | `deepsec-demos-ananya-langchain-demo` | Independent alternate identity-provider path. Assumes a working Oracle database and Entra registrations. |

The manifest follows this order for comparison and setup completeness. It does
not imply that a learner must complete the preceding lab. Every lab states
its own prerequisites and ends with its own verification checkpoint.

## Iteration checklist

- [x] Inventory all five source directories and review `deep-sec-local-genai`
      and the existing Deep Sec MCP workshop for structure.
- [x] Scaffold a dedicated LiveLabs workshop root with a Desktop loader.
- [x] Write workshop details and the independence/order explanation.
- [x] Write the introduction and five task-oriented lab guides.
- [x] Add official Oracle documentation and blog links in `Learn More`.
- [x] Render the ordered Desktop manifest and verify the loader.
- [x] Add per-lab required-file/package/configuration tables.
- [x] Add the production-readiness checklist and release gates.
- [x] Re-run the final static validator, loader smoke test, and source checks.
- [ ] Runtime-test each lab in a clean disposable environment.
- [ ] Test one selected lab on `132.145.156.225` after the host session
      resumes; host changes are deferred at the owner's request.
- [ ] Confirm the final delivery variant, source archive/PAR strategy, current
      screenshots, and WMS metadata with the lab owner.
- [ ] Run the final validator after any runtime-driven corrections.

## Current authoring decisions

- Use the existing source README files as the source of commands and runtime
  behavior; do not duplicate secrets or environment-specific identifiers.
- Treat the local FastMCP projects as local OAuth resource-server demos. Do not
  label them as the managed OCI Database Tools MCP Server.
- Explain that database policy is authoritative while application prompts,
  agent instructions, and SQL guards are additional controls.
- Keep destructive setup warnings next to the steps that invoke them.

## Review Status

This planning file supports the authoring workflow. Review the unchecked items
before publishing the workshop.

Estimated Time: 5 minutes

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - September 2026
