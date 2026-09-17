# DB Security - Deep Data Security AI Demo Labs

## Introduction

AI applications can be useful only when they can reach the data they need, but
the application should not become the authority for deciding which rows or
columns a person may see. These labs demonstrate Oracle Deep Data Security at
that boundary. A signed-in identity reaches an Oracle database through several
AI integration patterns, and the database applies the matching data roles and
data grants before results are returned.

The five labs are separate demonstrations. Select a lab based on the
integration you want to study. The suggested order moves from a complete OCI
IAM and LangChain setup, through two MCP patterns, to database-native Select
AI Agent orchestration and an alternate Microsoft Entra ID path. No lab is a
mandatory prerequisite for another. Lab 3 may reuse resources created during
Lab 2, but it must be configured as its own application.

| Lab | Focus | Required relationship |
| --- | --- | --- |
| 1 | LangChain HR Agent on OCI | Standalone setup and application |
| 2 | Local Oracle SQL MCP with setup scripts | Standalone setup and application |
| 3 | Reusable Python Oracle SQL MCP server | Existing IAM, database, wallet, and app configuration |
| 4 | Select AI Agent Team | Standalone database object and CLI setup |
| 5 | LangChain HR and Compensation Agents | Existing Oracle database and Microsoft Entra configuration |

### Prerequisites

- Use a non-production or disposable environment. Several source scripts
  create or drop database objects, IAM resources, users, groups, or wallets.
- Have access to an Oracle Autonomous AI Database or the database environment
  specified by the selected lab.
- Have OCI IAM Identity Domain access for Labs 1–4 when the lab uses OCI IAM,
  and Microsoft Entra ID administrative access for Lab 5.
- Have OCI Generative AI access and model quota for labs that call a model.
- Have OCI Cloud Shell or a Linux host with Bash, Python, SQL*Plus or SQLcl,
  and an extracted wallet when the selected lab needs them.
- Do not place passwords, client secrets, private keys, wallets, bearer tokens,
  or generated `.env` files in the repository.

### Shared file and host layout

The guides use `LAB_ROOT` for the parent of the five source directories. In a
prebuilt host, place the source files under:

```text
/home/oracle/dbsec-labs/deep-data-security/
  deepsec-demos-ananya-single-agent-oci-demo/
  deepsec-demos-ananya-langchain-demo/
  deepsec-demos-mcp-oci-script-demo/
  deepsec-demos-python-mcp-server/
  deepsec-demos-select-ai-oci-demo/
```

The exact Python version, Oracle client, wallet, IAM, and GenAI requirements
vary by lab. Each lab lists them next to its commands. On Oracle Linux, common
host prerequisites include the RPMs `python3` or `python3.12`, the matching
pip package, `git-core`, `unzip`, `curl`, `wget`, `openssl`, `ca-certificates`,
`libffi`, `gcc`, and `make` when a dependency needs a local build. Install only
missing packages through the approved image or package source. The labs do
not assume that an RPM supplies `sqlplus`; install the Oracle client or SQLcl
separately and configure its `PATH`. OCI CLI and the Entra lab's `oratst` test
harness are also separate tools.

### Objectives

- Identify the identity, application, database, and authorization boundary in
  each AI access pattern.
- Run the selected sample application or database-native agent.
- Compare the results returned to users with different Deep Data Security
  roles or end-user contexts.
- Recognize which setup values and runtime checks still require environment
  owner confirmation.

Review the [production-readiness checklist](../production-readiness.md) before
using any demo outside a disposable learning environment.

Estimated Workshop Time: 175 minutes for all five labs after the required
environment is available. Each lab lists its own estimated time.

## Suggested lab order

1. Lab 1: Run a LangChain HR Agent with OCI IAM and Deep Data Security.
2. Lab 2: Run an OCI IAM-Protected Oracle SQL MCP Server.
3. Lab 3: Configure the Reusable Python Oracle SQL MCP Server.
4. Lab 4: Run a Select AI Agent Team with Deep Data Security.
5. Lab 5: Run LangChain HR and Compensation Agents with Microsoft Entra ID.

The order is for comparison. It is not a dependency chain.

## Learn More

- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
- [Building Trusted Generative AI Experiences with Oracle Deep Data Security](https://blogs.oracle.com/database/building-trusted-genai-experiences-with-oracle-deep-data-security)
- [Oracle Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/mcp-servers.html)
- [Integrate Database Tools MCP Server with Oracle Deep Data Security](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/integrate-database-tools-mcp-server.html)
- [Getting Started with Select AI Agent](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/getting-started-select-ai-agent.html)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - September 2026
