# MCP Server Tools for an ADB OCI IAM Environment

## Introduction

This is an MCP-only extension lab. It adds OCI Database Tools MCP Server resources to the Autonomous Database and OCI IAM environment created by the ADB OCI IAM workshop. It does not create or change the database, IAM users or groups, OAuth applications, HR schema, database data roles, or data grants.

The ADB OCI IAM workshop remains the owner of identity and database security setup. This workshop owns only the Database Tools connection, MCP server, built-in SQL toolset, MCP client registration, and their cleanup.

### Prerequisites

- Complete the ADB OCI IAM workshop and retain its `.adb-oci-iam.env` file.
- An Autonomous AI Database version supported by MCP Server Tools.
- OCI permissions to create Database Tools connections, MCP servers, and the required Object Storage bucket.
- An MCP-compatible client if you complete the optional client lab.

### Objectives

- Import the existing ADB OCI IAM lab environment.
- Create and verify Database Tools MCP Server resources.
- Grant MCP application access to the existing `EMPLOYEES` group.
- Connect an external MCP client and inspect the available tools.
- Remove only the MCP resources created by this workshop.

Estimated Workshop Time: 45 minutes

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
