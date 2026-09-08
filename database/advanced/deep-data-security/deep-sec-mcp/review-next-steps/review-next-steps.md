# Lab 3: Review and Clean Up MCP Resources

## Introduction

Review the MCP Server Tools architecture and remove the OCI resources created by this extension lab. Cleanup never changes the ADB OCI IAM or Deep Security GenAI Demo prerequisite environments.

### Objectives

- Identify the resource and cleanup boundary for each prerequisite lab.
- Remove only the MCP resources created by this extension.

Estimated Time: 10 minutes

## Task 1: Review the Boundary

| Lab | Resources it owns | Cleanup command |
| --- | --- | --- |
| `adb-oci-iam` | ADB, OCI IAM OAuth setup, users, groups, HR schema, data roles, and data grants | Use its own cleanup script only |
| `deep-sec-gen-ai-demo` | Local service, virtual environment, and `DEEPSEC_HR_EMPLOYEES_AUDIT` | `99_disable_hr_employees_audit.sh` removes only the audit policy |
| `deep-sec-mcp` | Database Tools connection, MCP server, built-in SQL toolset, optional MCP bucket, and `.deep-sec-mcp.env` | `08_cleanup_deepsec_mcp.sh` |

This MCP lab removes only the resources in its own row. It does not delete the
GenAI audit policy or local service files, and it does not change the ADB OCI
IAM database or identity configuration.

## Task 2: Clean Up MCP Resources

1. Remove the MCP toolset, MCP server, and Database Tools connection.

    ```bash
    <copy>
    cd "$HOME/dbsec-labs/deep-data-security/deep-sec-mcp"
    source ./.deep-sec-mcp.env
    ./08_cleanup_deepsec_mcp.sh
    </copy>
    ```

2. Select one cleanup action when you do not want to remove every MCP resource.

    `--delete-server` removes the MCP server and all of its associated toolsets, matching the Console's **Delete all associated MCP toolsets** option. Delete the MCP server before its connection; a connection cannot be deleted while an MCP server references it.

    ```bash
    <copy>
    ./08_cleanup_deepsec_mcp.sh --delete-toolset
    ./08_cleanup_deepsec_mcp.sh --delete-server
    ./08_cleanup_deepsec_mcp.sh --delete-connection
    ./08_cleanup_deepsec_mcp.sh --delete-matching-resources
    ./08_cleanup_deepsec_mcp.sh --delete-bucket
    ./08_cleanup_deepsec_mcp.sh --delete-local-env
    </copy>
    ```

    Use `--delete-matching-resources` to remove every duplicate toolset, server, and connection with the lab's configured display names. It always removes dependencies in this order: toolsets, servers, then connections.

3. To delete every MCP resource, including the bucket and local environment file, run:

    ```bash
    <copy>
    ./08_cleanup_deepsec_mcp.sh --remove-all
    </copy>
    ```

    The ADB OCI IAM database, users, groups, OAuth applications, HR schema, data
    roles, and data grants are deliberately retained. The GenAI lab's local
    service, virtual environment, and audit policy are also retained.

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
