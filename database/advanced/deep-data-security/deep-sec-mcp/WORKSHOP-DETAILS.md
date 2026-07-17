# DeepSec MCP Workshop Details

## Purpose

This workshop is an MCP-only extension to the ADB OCI IAM workshop. It uses
the database, OCI IAM users and groups, OAuth configuration, HR schema, data
roles, and data grants that the prerequisite workshop already created.

## Workshop Flow

1. Import the ADB OCI IAM environment into `.deep-sec-mcp.env`.
2. Discover and create OCI Database Tools MCP resources.
3. Optionally connect an external MCP client.
4. Remove only the MCP resources created by this extension.

## Out of Scope

- Autonomous Database provisioning
- OCI IAM user, group, and OAuth application provisioning
- HR schema and sample-data creation
- Deep Data Security data-role, data-grant, and OAuth token setup

Those tasks remain in `adb-oci-iam`.
