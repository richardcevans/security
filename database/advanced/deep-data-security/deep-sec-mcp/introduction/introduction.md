# Deep Data Security with Autonomous Database and MCP Server Tools

## Introduction

AI-assisted applications often need controlled access to enterprise data. MCP server tools can expose database actions to AI clients. The database must still enforce access rules, limit data, and record activity.

In this workshop, you run a controlled prompt-to-tool application, connect OCI Database Tools MCP Server access to Autonomous Database, demonstrate overprivileged access, and apply Deep Data Security controls. The goal is to prove that least-privilege access belongs at the data layer, where the same policy can govern AI-style access, MCP tool access, and direct SQL.

The workshop flow uses this architecture:

- A user enters an AI-style prompt.
- The prompt-to-tool application maps the prompt to a database tool call.
- OCI Database Tools MCP Server resources provide the MCP resource path.
- Autonomous Database evaluates the active user, role, and data grants.
- Deep Data Security controls determine which rows and sensitive attributes are returned.

Use the same prompt set before and after the security controls are applied.

| Prompt | Access Path | Expected Before Controls | Expected After Controls |
| --- | --- | --- | --- |
| Show all employees, including salary, SSN, phone number, manager, and department. | ADMIN-backed prompt-to-tool call | Full sensitive result set | Not used for least-privilege validation |
| Show my employee profile. | OCI IAM employee context | Overbroad result if the path is shared or overprivileged | Employee sees only their own row |
| Show my direct reports. | OCI IAM manager context | Overbroad result if the path is shared or overprivileged | Manager sees self and direct reports |
| Show salary and SSN. | OCI IAM end-user context | Sensitive attributes may be exposed | Database policy filters, masks, or blocks data according to role |

### Prerequisites

- Autonomous Database Serverless or Autonomous AI Database instance.
- Access to create or configure the lab schema objects.
- Deep Data Security enabled or available in the target environment.
- Included AI prompt and tool-access simulator scripts.
- OCI Database Tools connection and permission to create an MCP server.
- OCI identity domain and Object Storage bucket for MCP server setup.
- Optional external MCP client for additional tool discovery and testing.

### Objectives

- Review the workshop architecture and trust boundaries.
- Explore the sample schema, sensitive data, users, and access paths.
- Run AI-style prompts that map to database tool calls against Autonomous Database.
- Connect MCP server tools and demonstrate AI overreach.
- Apply and validate least-privilege access with Deep Data Security.
- Optionally connect VS Code and Cline as an external MCP client.

Estimated Workshop Time: 110 minutes

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
