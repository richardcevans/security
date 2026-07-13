# Workshop Details

Estimated Time: 5 minutes

### Objectives

Use this page to summarize the workshop scope, outline, prerequisites, and open delivery notes.

## Short Description

Run a simple AI application with OCI Database Tools MCP Server access to Autonomous Database Serverless, then apply Oracle Deep Data Security controls so AI, MCP tools, SQL, and analytics follow the same least-privilege data policies.

## Long Description

This workshop shows how AI-powered applications can reach enterprise data through database tools, and why database-layer authorization still matters. Learners explore a prepared Autonomous Database Serverless environment, run a simple AI application, connect OCI Database Tools MCP Server access, and observe how overprivileged access can expose sensitive data.

Learners then apply Deep Data Security controls and rerun the same AI, MCP, SQL, and analytics checks. The outcome is a repeatable secure AI access pattern where users, agents, applications, and direct database paths follow consistent least-privilege rules at the data layer.

## Workshop Outline

1. Introduction: Review the architecture, prerequisites, and expected outcome.
2. Lab 1: Explore the Environment.
3. Lab 2: Run the AI Application.
4. Lab 3: Connect MCP Server Tools.
5. Lab 4: Demonstrate AI Overreach.
6. Lab 5: Apply and Test Deep Data Security.
7. Lab 6: Review Architecture, Clean Up, and Next Steps.

## Workshop Prerequisites

- Autonomous Database Serverless or Autonomous AI Database instance.
- Oracle Database user with privileges to create or configure the required lab schema objects.
- Deep Data Security feature availability in the target database environment.
- Prebuilt simple AI application package or repository.
- OCI Database Tools connection and permissions to create an MCP server.
- OCI identity domain for the MCP server and registered MCP client.
- Object Storage bucket for the MCP server.
- MCP-capable client for testing tool discovery and tool calls.

## Notes

- Target duration: 110 minutes.
- Draft lab count: five hands-on labs plus a short wrap-up.
- Current mode: draft skeleton.
- Scope decision: learners configure and run a working simple app instead of building an app from scratch.
- SME gap: confirm the simple app implementation, source package, setup commands, model provider, and runtime requirements.
- SME gap: confirm the MCP client used in the workshop and the exact OAuth or client registration steps.
- SME gap: confirm whether the MCP server runtime identity uses authenticated principal or resource principal.
- SME gap: confirm the public Deep Data Security syntax for mapped data roles, application identity, and data grants before publishing.
- Source guidance: use the internal Database Tools MCP server integration functional specification only for SME validation; use public Oracle documentation for customer-facing claims and commands.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
