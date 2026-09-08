# MCP Server Tools for an ADB OCI IAM Environment

## Introduction

This is an MCP-only extension lab. It follows the ADB OCI IAM and Deep Security GenAI Demo labs, then adds OCI Database Tools MCP Server resources to their existing Autonomous Database and OCI IAM environment. It does not create or change the database, IAM users or groups, OAuth applications, HR schema, database data roles, or data grants.

The ADB OCI IAM workshop remains the owner of identity and database security setup. The Deep Security GenAI Demo proves OCI IAM token propagation, Deep Data Security authorization, and auditing before MCP resources are introduced. This workshop owns only the Database Tools connection, MCP server, built-in SQL toolset, MCP client registration, and their cleanup.

### Prerequisites

- Complete the ADB OCI IAM workshop and retain its `.adb-oci-iam.env` file.
- Complete the `deep-sec-gen-ai-demo` lab against that same ADB. Verify its token-preserving service and reviewed HR query tools before beginning this MCP extension.
- An Autonomous AI Database version supported by MCP Server Tools.
- OCI permissions to create Database Tools connections, MCP servers, and the required Object Storage bucket.
- An MCP-compatible client if you complete the optional client lab.

### Objectives

- Import the existing ADB OCI IAM lab environment.
- Create and verify Database Tools MCP Server resources.
- Grant MCP application access to the existing `EMPLOYEES` group.
- Connect an external MCP client and inspect the available tools.
- Remove only the MCP resources created by this workshop.

### Lab Ownership and Cleanup

| Lab | Owns | Cleanup owner |
| --- | --- | --- |
| `adb-oci-iam` | ADB, OCI IAM OAuth setup, users, groups, HR schema, data roles, and data grants | Its ADB cleanup script only |
| `deep-sec-gen-ai-demo` | Local token-preserving service, local virtual environment, and `DEEPSEC_HR_EMPLOYEES_AUDIT` | `99_disable_hr_employees_audit.sh` removes only the audit policy |
| `deep-sec-mcp` | Database Tools connection, MCP server, MCP toolset, optional MCP bucket, and `.deep-sec-mcp.env` | `08_cleanup_deepsec_mcp.sh` only |

The MCP cleanup script never removes ADB OCI IAM or GenAI-lab resources. The
GenAI cleanup script never removes MCP resources.

Estimated Workshop Time: 45 minutes

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
