# Deep Data Security with Autonomous Database and MCP Server Tools

## Introduction

AI-assisted applications often need controlled access to enterprise data. MCP server tools can expose database actions to AI clients. The database must still enforce access rules, limit data, and record activity.

In this workshop, you run a simple AI application, connect OCI Database Tools MCP Server access to Autonomous Database, demonstrate overprivileged access, and apply Deep Data Security controls.

### Prerequisites

- Autonomous Database Serverless or Autonomous AI Database instance.
- Access to create or configure the lab schema objects.
- Deep Data Security enabled or available in the target environment.
- Prebuilt simple AI application package or repository.
- OCI Database Tools connection and permission to create an MCP server.
- OCI identity domain and Object Storage bucket for MCP server setup.
- MCP-capable client for tool discovery and testing.

### Objectives

- Review the workshop architecture and trust boundaries.
- Explore the sample schema, sensitive data, users, and access paths.
- Run a simple AI application against Autonomous Database.
- Connect MCP server tools and demonstrate AI overreach.
- Apply and validate least-privilege access with Deep Data Security.

Estimated Workshop Time: 110 minutes

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
