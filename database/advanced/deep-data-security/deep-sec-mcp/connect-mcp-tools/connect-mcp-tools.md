# Lab 3: Connect MCP Server Tools

## Introduction

Create or inspect OCI Database Tools MCP Server resources for the workshop database. You can use existing resources, create them with the OCI Console, or create them from Cloud Shell with the optional lab script.

Estimated Time: 25 minutes

### Objectives

In this lab, you will:

- Review the Database Tools connection.
- Create or inspect the Object Storage bucket, Database Tools connection, MCP server, and built-in SQL toolset.
- Connect an OAuth-enabled MCP client.
- Record the user flow for later security tests.

### Prerequisites

- Workshop database connection string.
- OCI identity domain for the MCP server and client.
- Compartment where Database Tools and MCP resources can be created. By default, use the same compartment as the workshop database.
- Object Storage bucket name for MCP server setup.
- MCP-capable client selected for the workshop.
- Permission to create or inspect Database Tools, Object Storage, and identity-domain applications.
- Optional `.deep-sec-mcp.env` file from Lab 1.

## Task 1: Choose the Setup Method

1. Choose how you will provide the Database Tools MCP resources.

    Use one of these paths:

    - **ADB-S bootstrap:** if Lab 1 used `setup_adbs_oci_iam.sh`, most Database Tools and MCP input values are already in `.deep-sec-mcp.env`.
    - **Existing resources:** use a Database Tools connection and MCP server that were already created for you.
    - **Cloud Shell script:** create the bucket, Database Tools connection, MCP server, and built-in SQL toolset from `.deep-sec-mcp.env`.
    - **Terraform or Resource Manager:** use the Terraform package under `terraform/` to create as much of the sandbox as your tenancy allows.

2. For this lab, prefer token-based Database Tools access when you are testing MCP end-user identity.

    Token mode lets the MCP path use the authenticated user's identity. Password mode is useful for early connectivity smoke tests, but it does not prove end-user least privilege by itself.

3. Source the lab environment.

    ```bash
    cd ~/security/database/advanced/deep-data-security/deep-sec-mcp
    source ./.deep-sec-mcp.env
    ```

## Task 2: Discover OCI Inputs

1. If Lab 1 used `setup_adbs_oci_iam.sh`, review the generated values first.

    ```bash
    grep -E 'ADB_OCID|DATABASE_TOOLS_CONNECTION_STRING|MCP_COMPARTMENT|MCP_IDENTITY_DOMAIN|MCP_BUCKET|MCP_SERVER' .deep-sec-mcp.env
    ```

2. Run discovery from Cloud Shell if you used pre-existing resources or want to refresh the generated values.

    ```bash
    ./discover_mcp_inputs.sh
    ```

    The discovery helper queries the tenancy for values it can determine safely:

    - Object Storage namespace
    - tenancy OCID
    - compartment OCID, when `ADB_OCID` or `MCP_COMPARTMENT_NAME` is available
    - identity domain OCID, when `OCI_DOMAIN_URL`, `MCP_IDENTITY_DOMAIN_NAME`, or a single active domain is available
    - existing Database Tools connection by display name
    - existing MCP server by display name
    - existing built-in SQL toolset by display name

3. Review `.deep-sec-mcp.env`.

    ```bash
    grep -E 'NAMESPACE|TENANCY_OCID|MCP_COMPARTMENT|MCP_IDENTITY_DOMAIN|DATABASE_TOOLS_CONNECTION_ID|MCP_SERVER_ID|MCP_BUILT_IN_SQL_TOOLSET_ID' .deep-sec-mcp.env
    ```

4. If discovery reports multiple possible values, set a display-name filter and rerun discovery.

    ```bash
    export MCP_COMPARTMENT_NAME="<compartment_display_name>"
    export MCP_IDENTITY_DOMAIN_NAME="<identity_domain_display_name>"
    ./discover_mcp_inputs.sh
    ```

## Task 3: Review or Override Cloud Shell Creation Inputs

1. Review the values the scripts can infer.

    ```bash
    source ./.deep-sec-mcp.env
    grep -E 'ADB_OCID|MCP_COMPARTMENT_OCID|MCP_IDENTITY_DOMAIN_OCID|MCP_BUCKET_NAME|MCP_SERVER_NAME|DATABASE_TOOLS_CONNECTION_NAME|DATABASE_TOOLS_CONNECTION_STRING|DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE|DATABASE_TOOLS_RUNTIME_IDENTITY|MCP_RUNTIME_IDENTITY' .deep-sec-mcp.env
    ```

    If Lab 1 used `setup_adbs_oci_iam.sh`, the Cloud Shell creation helper can usually determine:

    - `MCP_COMPARTMENT_OCID` from `ADB_OCID`, so the MCP resources are created in the same compartment as the database
    - `MCP_IDENTITY_DOMAIN_OCID` from `OCI_DOMAIN_URL`
    - `MCP_BUCKET_NAME`, `MCP_SERVER_NAME`, `MCP_BUILT_IN_SQL_TOOLSET_NAME`, and `DATABASE_TOOLS_CONNECTION_NAME`
    - `DATABASE_TOOLS_CONNECTION_STRING` from the ADB metadata or wallet
    - token-based runtime identity settings

2. If the values are missing or you want to refresh them before creation, run discovery.

    ```bash
    ./discover_mcp_inputs.sh
    source ./.deep-sec-mcp.env
    ```

3. Override only the values that are not discoverable in your tenancy.

    For example, set a different compartment only if you do not want MCP resources created beside the database.

    ```bash
    export MCP_COMPARTMENT_OCID="<different_compartment_ocid>"
    ```

4. Keep token-based MCP access for the identity-aware path.

    The defaults are:

    ```bash
    export DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE="TOKEN"
    export DATABASE_TOOLS_RUNTIME_IDENTITY="AUTHENTICATED_PRINCIPAL"
    export MCP_RUNTIME_IDENTITY="AUTHENTICATED_PRINCIPAL"
    ```

5. If you must use password mode for a connectivity smoke test, set a Vault secret OCID instead.

    ```bash
    export DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE="PASSWORD"
    export DATABASE_TOOLS_CONNECTION_USER_NAME="WORKSHOP_USER"
    export DATABASE_TOOLS_PASSWORD_SECRET_OCID="<vault_secret_ocid>"
    ```

6. If Database Tools must reach a private database listener, set the Database Tools private endpoint OCID.

    ```bash
    export DATABASE_TOOLS_PRIVATE_ENDPOINT_OCID="<database_tools_private_endpoint_ocid>"
    ```

7. If you want the connection associated with a known database or DB system, set the related resource values.

    ```bash
    export DATABASE_TOOLS_RELATED_RESOURCE_TYPE="DATABASE"
    export DATABASE_TOOLS_RELATED_RESOURCE_OCID="<database_ocid>"
    ```

## Task 4: Create the Database Tools MCP Resources

1. Run the helper script.

    ```bash
    source ./.deep-sec-mcp.env
    ./create_mcp_server_tools.sh
    ```

    The script creates or confirms:

    - Object Storage bucket
    - Database Tools connection
    - Database Tools MCP server
    - built-in SQL MCP toolset

2. Confirm that the script wrote the generated OCIDs back to `.deep-sec-mcp.env`.

    ```bash
    grep -E 'DATABASE_TOOLS_CONNECTION_ID|MCP_SERVER_ID|MCP_BUILT_IN_SQL_TOOLSET_ID' .deep-sec-mcp.env
    ```

3. If the script fails during connection creation, check the most common causes.

    - The compartment policy does not allow Database Tools or Object Storage creation.
    - The identity domain OCID is not in the same tenancy context.
    - The database listener is private and no Database Tools private endpoint was supplied.
    - Password mode was selected but the Vault secret OCID was not supplied.
    - The built-in SQL toolset version is different in your region. Set `MCP_BUILT_IN_SQL_TOOLSET_VERSION` to the supported version and rerun the script.

## Task 5: Create or Inspect the MCP Server in the Console

1. Open **Developer Services**, then **Database Tools**.

2. Open **Model Context Protocol Servers**.

3. Create or inspect the MCP server for this workshop.

    The public OCI Database Tools documentation lists the required values:

    - compartment
    - identity domain
    - database connection
    - Object Storage bucket
    - runtime identity

4. Confirm the compartment, domain, connection, bucket, and runtime identity.

5. If you use the OCI CLI directly, start from this command shape and replace each placeholder.

    ```bash
    oci dbtools mcp-server create-mcp-server-default \
      --compartment-id <compartment_ocid> \
      --connection-id <database_tools_connection_ocid> \
      --display-name <mcp_server_name> \
      --domain-id <identity_domain_ocid> \
      --storage '{"type":"OBJECT_STORAGE","bucket":{"namespace":"<namespace>","bucketName":"<bucket_name>"}}' \
      --runtime-identity AUTHENTICATED_PRINCIPAL
    ```

6. Record the runtime identity type.

7. Create or inspect the built-in SQL toolset for the MCP server.

    If you use the OCI CLI directly, start from this command shape and replace each placeholder.

    ```bash
    oci dbtools mcp-toolset create-mcp-toolset-built-in-sql-tools \
      --compartment-id <compartment_ocid> \
      --display-name <toolset_name> \
      --mcp-server-id <mcp_server_ocid> \
      --toolset-version 1 \
      --default-execution-type SYNCHRONOUS
    ```

8. To print the optional Terraform and OCI CLI command shapes, run:

    ```bash
    cd ~/security/database/advanced/deep-data-security/deep-sec-mcp
    source ./.deep-sec-mcp.env
    ./07_print_mcp_commands.sh
    ```

## Task 6: Review the Identity Flow

1. Confirm the MCP client is an integrated app in the identity domain.

2. Confirm the MCP server OAuth resource settings.

3. Trace the user flow:

    - The MCP client requests a user OAuth token.
    - The MCP server exchanges that context through OCI identity services.
    - The database receives access in the end-user context.

4. Confirm that the data-role mapping in Lab 5 uses `IAM_GROUP_NAME` for the MCP token path.

## Task 7: Connect the MCP Client

1. Register or configure the MCP client.

2. Open the MCP server details page and copy the endpoint URL.

3. Record the endpoint in `.deep-sec-mcp.env`.

    ```bash
    export MCP_SERVER_ENDPOINT="<mcp_server_endpoint>"
    ```

4. Connect the client to the MCP server.

    ```bash
    echo "$MCP_SERVER_ENDPOINT"
    ```

5. Confirm that the client lists the database tools.

6. Record the tool names and inputs for the next lab.

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
