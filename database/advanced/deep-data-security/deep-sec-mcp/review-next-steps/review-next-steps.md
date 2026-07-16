# Lab 6: Review Architecture, Clean Up, and Next Steps

## Introduction

Review the secure AI access pattern and remove workshop resources that should not remain in the tenancy. Use this lab to connect the hands-on steps to customer architecture decisions.

Estimated Time: 10 minutes

### Objectives

In this lab, you will:

- Summarize the final architecture.
- Review production design considerations.
- Clean up workshop resources.

### Prerequisites

- Completed validation matrix from Lab 5.
- Access to the OCI resources and database objects created for the workshop.

## Task 1: Review the Architecture

1. Review how the AI application, MCP server, identity domain, Database Tools connection, and Autonomous Database fit together.

2. Identify where Deep Data Security enforces access decisions.

## Task 2: Clean Up Resources

1. For most workshop runs, remove only the DeepSec MCP-specific Database Tools resources.

    This keeps ADB-S, OCI IAM OAuth applications, groups, users, wallet, and database objects.

    ```bash
    <copy>
    cd "$HOME/dbsec-labs/deep-data-security/deep-sec-mcp"
    source ./.deep-sec-mcp.env
    ./08_cleanup_deepsec_mcp.sh --post-adb-oci-iam
    </copy>
    ```

2. To remove MCP resources and the MCP Object Storage bucket, add `--delete-bucket`.

    ```bash
    <copy>
    ./08_cleanup_deepsec_mcp.sh --post-adb-oci-iam --delete-bucket
    </copy>
    ```

3. To remove the DeepSec MCP database demo objects, run the default cleanup.

    ```bash
    <copy>
    ./08_cleanup_deepsec_mcp.sh
    </copy>
    ```

4. To remove both database objects and MCP Server Tools resources, run:

    ```bash
    <copy>
    ./08_cleanup_deepsec_mcp.sh --mcp-resources
    </copy>
    ```

## Task 3: Troubleshoot Common Issues

1. If SQL*Plus returns `ORA-12154`, confirm the wallet and service variables are loaded.

    ```bash
    <copy>
    source ./.deep-sec-mcp.env
    env | grep -E '^(ADB_SERVICE|TNS_ADMIN|WALLET_DIR|DB_NAME)=' | sort
    ./verify_db_setup.sh
    </copy>
    ```

2. If MCP server creation fails with a runtime identity error, confirm the MCP server uses resource principal.

    ```bash
    <copy>
    env | grep -E '^(DATABASE_TOOLS_RUNTIME_IDENTITY|MCP_RUNTIME_IDENTITY)=' | sort
    </copy>
    ```

    The expected values for this lab are `DATABASE_TOOLS_RUNTIME_IDENTITY=AUTHENTICATED_PRINCIPAL` and `MCP_RUNTIME_IDENTITY=RESOURCE_PRINCIPAL`.

3. If a Database Tools connection was created but the script did not find it, run discovery and reload the environment.

    ```bash
    <copy>
    ./discover_mcp_inputs.sh
    source ./.deep-sec-mcp.env
    env | grep -E '^(DATABASE_TOOLS_CONNECTION_ID|MCP_SERVER_ID|MCP_BUILT_IN_SQL_TOOLSET_ID)=' | sort
    </copy>
    ```

4. If `.deep-sec-mcp.env` is missing, recreate it from the lab scripts.

    ```bash
    <copy>
    ./00_configure_lab_env.sh
    source ./.deep-sec-mcp.env
    </copy>
    ```

5. If an OCI command fails with an authentication error, refresh your Cloud Shell session or rerun the OCI login flow used by your tenancy.

6. If an OCI command fails with an authorization error, confirm your compartment policy allows the required Object Storage and Database Tools operations.

## Task 4: Plan Next Steps

1. Identify which customer AI workflows use shared, broad, or weakly scoped database access.

2. Map those workflows to the secure pattern from this workshop.

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
