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

1. To return to a state similar to the end of the `adb-oci-iam` lab, remove only the DeepSec MCP-specific Database Tools resources.

    This keeps ADB-S, OCI IAM OAuth applications, groups, users, wallet, and database objects.

    ```bash
    <copy>
    cd ~/security/database/advanced/deep-data-security/deep-sec-mcp
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

## Task 3: Plan Next Steps

1. Identify which customer AI workflows use shared, broad, or weakly scoped database access.

2. Map those workflows to the secure pattern from this workshop.

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
