# Lab 3: Review and Clean Up MCP Resources

## Introduction

Review the MCP Server Tools architecture and remove the OCI resources created by this extension lab. Cleanup never changes the ADB OCI IAM prerequisite environment.

Estimated Time: 10 minutes

## Task 1: Review the Boundary

The ADB OCI IAM workshop owns the database and identity configuration. This lab owns the Database Tools connection, MCP server, built-in SQL toolset, and optional MCP Object Storage bucket.

## Task 2: Clean Up MCP Resources

1. Remove the MCP toolset, MCP server, and Database Tools connection.

    ```bash
    <copy>
    cd "$HOME/dbsec-labs/deep-data-security/deep-sec-mcp"
    source ./.deep-sec-mcp.env
    ./08_cleanup_deepsec_mcp.sh
    </copy>
    ```

2. To also remove the Object Storage bucket created for MCP, run:

    ```bash
    <copy>
    ./08_cleanup_deepsec_mcp.sh --delete-bucket
    </copy>
    ```

The ADB OCI IAM database, users, groups, OAuth applications, HR schema, data roles, and data grants are deliberately retained.

## Task 3: Troubleshoot

If MCP resource creation fails, confirm the imported environment and rerun discovery:

```bash
<copy>
source ./.deep-sec-mcp.env
./discover_mcp_inputs.sh
./verify_mcp_resources.sh
</copy>
```

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
