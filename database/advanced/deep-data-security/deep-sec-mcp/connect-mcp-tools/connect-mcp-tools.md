# Lab 3: Connect MCP Server Tools

## Introduction

Create the OCI Database Tools resources used by the MCP server path. This lab uses the workshop scripts to create or confirm the Object Storage bucket, Database Tools connection, MCP server, and built-in SQL toolset. You then review the resources in the OCI Console.

Estimated Time: 20 minutes

### Objectives

In this lab, you will:

- Confirm the MCP setup values loaded from `.deep-sec-mcp.env`.
- Create or reuse the Database Tools connection and MCP server resources.
- Verify the generated resource OCIDs are loaded in the current shell.
- Review the Database Tools connection, MCP server, and built-in SQL toolset in the OCI Console.

### Prerequisites

- Completed Lab 1.
- Workshop database connection values in `.deep-sec-mcp.env`.
- Permission to create or inspect Database Tools, Object Storage, and identity-domain resources.

## Task 1: Review the Loaded MCP Inputs

1. Source the lab environment.

    ```bash
    <copy>
    cd "$HOME/dbsec-labs/deep-data-security/deep-sec-mcp"
    source ./.deep-sec-mcp.env
    </copy>
    ```

2. Confirm the MCP setup values loaded into your current shell.

    ```bash
    <copy>
    env | grep -E '^(ADB_OCID|DATABASE_TOOLS_CONNECTION_NAME|DATABASE_TOOLS_CONNECTION_STRING|DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE|DATABASE_TOOLS_RUNTIME_IDENTITY|MCP_COMPARTMENT_OCID|MCP_IDENTITY_DOMAIN_OCID|MCP_BUCKET_NAME|MCP_SERVER_NAME|MCP_RUNTIME_IDENTITY)=' | sort
    </copy>
    ```

    For Object Storage-backed MCP servers, `MCP_RUNTIME_IDENTITY` must be `RESOURCE_PRINCIPAL`, or the referenced Database Tools connection runtime identity must be `RESOURCE_PRINCIPAL`. This lab uses a token-based Database Tools connection and `MCP_RUNTIME_IDENTITY=RESOURCE_PRINCIPAL`.

3. If any required value is missing, refresh the generated values and reload the environment.

    ```bash
    <copy>
    ./discover_mcp_inputs.sh
    source ./.deep-sec-mcp.env
    env | grep -E '^(ADB_OCID|DATABASE_TOOLS_CONNECTION_NAME|DATABASE_TOOLS_CONNECTION_STRING|DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE|DATABASE_TOOLS_RUNTIME_IDENTITY|MCP_COMPARTMENT_OCID|MCP_IDENTITY_DOMAIN_OCID|MCP_BUCKET_NAME|MCP_SERVER_NAME|MCP_RUNTIME_IDENTITY)=' | sort
    </copy>
    ```

## Task 2: Create the Database Tools MCP Resources

1. Run the MCP creation helper.

    ```bash
    <copy>
    ./create_mcp_server_tools.sh
    source ./.deep-sec-mcp.env
    </copy>
    ```

    The script creates or confirms:

    - Object Storage bucket
    - Database Tools connection
    - Database Tools MCP server
    - built-in SQL MCP toolset

2. Confirm the generated OCIDs loaded into your current shell.

    ```bash
    <copy>
    env | grep -E '^(DATABASE_TOOLS_CONNECTION_ID|MCP_SERVER_ID|MCP_BUILT_IN_SQL_TOOLSET_ID)=' | sort
    </copy>
    ```

3. If the script reports that it cannot find a resource after creation, rerun discovery and reload the environment.

    ```bash
    <copy>
    ./discover_mcp_inputs.sh
    source ./.deep-sec-mcp.env
    env | grep -E '^(DATABASE_TOOLS_CONNECTION_ID|MCP_SERVER_ID|MCP_BUILT_IN_SQL_TOOLSET_ID)=' | sort
    </copy>
    ```

## Task 3: Review Resources in the OCI Console

1. In the OCI Console, open **Developer Services**, then **Database Tools**.

2. Open **Connections**.

3. Open the connection named by `DATABASE_TOOLS_CONNECTION_NAME`.

4. Confirm the connection is active and points to the workshop database.

5. Open **Model Context Protocol Servers**.

6. Open the MCP server named by `MCP_SERVER_NAME`.

7. Confirm the MCP server uses:

    - the Database Tools connection from this lab
    - the Object Storage bucket from this lab
    - authenticated principal runtime identity
    - the built-in SQL toolset

## Task 4: Review the MCP Client Boundary

1. Use the OCI Console to create, inspect, and validate Database Tools and MCP resources.

    The OCI Console is not the MCP client for this lab. Later labs use the prompt simulator and SQL checks to prove the data-access behavior. If you connect an external MCP client, use the MCP server details page to get the endpoint and tool information.

2. Review the identity flow for the MCP path.

    - The user authenticates through OCI IAM.
    - The MCP server receives the user context through the token path.
    - Database data roles map OCI IAM group context to database privileges.
    - Deep Data Security controls apply at the data layer.

3. Confirm that Lab 5 will use `IAM_GROUP_NAME` mappings for the MCP token path.

    ```bash
    <copy>
    env | grep -E '^(DATA_ROLE_MAPPING_TYPE|OCI_IAM_EMPLOYEE_GROUP|OCI_IAM_MANAGER_GROUP)=' | sort
    </copy>
    ```

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
