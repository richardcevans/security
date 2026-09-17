# Traceability Summary

Estimated Time: 5 minutes

| Workshop Area | Source | Evidence Type | Notes |
| --- | --- | --- | --- |
| Introduction | `deepsec-demos/WORKSHOP-DETAILS.md`; `deepsec-demos-*/README.md`; [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf) | claim | Defines the common problem, five independent demos, and shared prerequisites. |
| Lab 1 | `deepsec-demos-ananya-single-agent-oci-demo/README.md`; `langchain-agent-oci/adb-oci-iam/*.sh`; `langchain-agent-oci/langchain_app.py` | command and result | Supplies the complete OCI IAM/ADB setup, Marvin and Emma checks, and LangChain execution path. |
| Lab 2 | `deepsec-demos-mcp-oci-script-demo/README.md`; `src/oracle_sql_mcp/{server,client_app,token_verifier,database,sql}.py`; `adb-oci-iam/*.sh` | command and architecture | Supplies local Streamable HTTP MCP startup, OAuth introspection, read-only tools, and end-user database identity propagation. |
| Lab 3 | `deepsec-demos-python-mcp-server/README.md`; `src/oracle_sql_mcp/*.py`; `.env.example` | command and architecture | Supplies the application-only MCP pattern and its independently configured OAuth/database boundary. |
| Lab 4 | `deepsec-demos-select-ai-oci-demo/README.md`; `setup_demo_database.sql`; `setup_select_ai_access.sql`; `setup_select_ai.sql`; `select_ai_agent_app.py` | command and result | Supplies the destructive sample setup, Select AI profile and Team sequence, and user-scoped CLI prompts. |
| Lab 5 | `deepsec-demos-ananya-langchain-demo/README.md`; `setup.sql`; `langchain_app.py`; `langchain_tools.py` | command and architecture | Supplies the Entra application sequence, mapped data roles, compensation application identity, and two-agent flow. |
| Production readiness | `production-readiness.md`; all five source READMEs and runtime modules | release gate | Records the untested runtime boundaries, per-lab security/deployment risks, required evidence, and LiveLabs publication acceptance criteria. |
| Learn More | [Deep Data Security blog](https://blogs.oracle.com/database/building-trusted-genai-experiences-with-oracle-deep-data-security); [Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/mcp-servers.html); [Select AI Agent](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/getting-started-select-ai-agent.html) | external reference | Official Oracle context added to each relevant lab without replacing the local source commands. |

## Notes

- Runtime execution against an OCI tenancy and Oracle database remains open.
- No screenshots, archive/PAR links, or source-download URLs were invented.
- The local MCP projects are documented as FastMCP applications, not as the
  managed OCI Database Tools MCP Server.

## Acknowledgements

* **Traceability Compiled By** - Richard Evans
* **Last Updated By/Date** - September 2026
