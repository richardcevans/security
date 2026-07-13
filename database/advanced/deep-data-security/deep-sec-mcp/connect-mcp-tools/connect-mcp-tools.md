# Lab 3: Connect MCP Server Tools

## Introduction

Create or inspect an OCI Database Tools MCP Server for the workshop database. Connect a client and find the database tools.

Estimated Time: 25 minutes

### Objectives

In this lab, you will:

- Review the Database Tools connection.
- Create or inspect the MCP server.
- Connect an OAuth-enabled MCP client.
- Record the user flow for later security tests.

### Prerequisites

- Database Tools connection for the workshop database.
- OCI identity domain for the MCP server and client.
- Object Storage bucket for MCP server setup.
- MCP-capable client selected for the workshop.
- Permission to create or inspect apps in the identity domain.

## Task 1: Review the Database Tools Connection

1. Open OCI Database Tools.

2. Confirm the connection for the workshop database.

3. Record the connection OCID for CLI-based setup.

4. Confirm that the connection uses the approved authentication method.

## Task 2: Create or Inspect the MCP Server

1. Open Model Context Protocol Servers in OCI Database Tools.

2. Create or inspect the MCP server for this workshop.

    The public OCI Database Tools documentation lists the required values:

    - compartment
    - identity domain
    - database connection
    - Object Storage bucket
    - runtime identity

3. Confirm the compartment, domain, connection, bucket, and runtime identity.

4. If you use the OCI CLI, start from this command shape and replace each placeholder.

    ```bash
    oci dbtools mcp-server create-mcp-server-default \
      --compartment-id <compartment_ocid> \
      --connection-id <database_tools_connection_ocid> \
      --display-name <mcp_server_name> \
      --domain-id <identity_domain_ocid>
    ```

5. Record the runtime identity type.

## Task 3: Review the Identity Flow

1. Confirm the MCP client is an integrated app in the identity domain.

2. Confirm the MCP server OAuth resource settings.

3. Trace the user flow:

    - The MCP client requests a user OAuth token.
    - The MCP server exchanges that context through OCI identity services.
    - The database receives access in the end-user context.

    TODO: Replace this flow with the exact token and client setup steps.

## Task 4: Connect the MCP Client

1. Register or configure the MCP client.

2. Connect the client to the MCP server.

    TODO: Add the final OAuth/client registration steps.

3. Confirm that the client lists the database tools.

4. Record the tool names and inputs for the next lab.

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
