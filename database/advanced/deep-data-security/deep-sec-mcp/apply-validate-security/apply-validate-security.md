# Lab 5: Apply and Test Deep Data Security

## Introduction

Apply Deep Data Security controls. Then rerun the same AI, MCP, SQL, and analytics checks.

Estimated Time: 35 minutes

### Objectives

In this lab, you will:

- Configure identity-aware data rules.
- Run overreach checks as restricted and privileged users.
- Complete a results matrix for AI, MCP, SQL, and analytics access.
- Explain how end-user identity maps to database data roles.

### Prerequisites

- Overreach baseline from Lab 4.
- At least two users, roles, groups, tokens, or app contexts.
- Deep Data Security rules for the scenario.
- Identity-domain group or application-role names for the test users.
- Optional `.deep-sec-mcp.env` file from Lab 1.

## Task 1: Apply Deep Data Security Rules

1. Create or inspect the data roles used by the lab.

    The optional scripts use OCI IAM group names and database data roles. For the Database Tools MCP path, use `IAM_GROUP_NAME` because the MCP server can pass the end-user IAM group context through its token path.

    ```bash
    cd ~/security/database/advanced/deep-data-security/deep-sec-mcp
    source ./.deep-sec-mcp.env
    ./01_enable_oci_iam.sh
    ./03_create_data_roles_and_grants.sh
    ./verify_db_setup.sh
    ```

    The data role mapping uses this format:

    ```sql
    CREATE OR REPLACE DATA ROLE hrapp_employees
      MAPPED TO 'IAM_GROUP_NAME=example-domain/deepsec-employees';
    ```

    If you are testing direct SQL*Plus OAuth tokens instead of the MCP token path, set `DATA_ROLE_MAPPING_TYPE=IAM_OAUTH_GROUP` in `.deep-sec-mcp.env`.

2. Grant the appropriate data access to each data role.

    The script creates an employee grant and a manager grant over `hr.employees`.

3. If the AI application uses an application identity, create or inspect that identity.

    ```sql
    CREATE APPLICATION IDENTITY hcm_app
      MAPPED TO 'IAM_OAUTH_CLIENT_ID=<client_id>';
    ```

    TODO: Replace `hcm_app` and `<client_id>` with the final app identity values.

4. Grant only the required data roles to the application identity.

    ```sql
    GRANT DATA ROLE employee_data_role TO hcm_app;
    ```

5. Confirm the rule state before testing.

## Task 2: Validate Restricted Access

1. Switch to the restricted context.

    Get an OCI IAM OAuth token as the restricted employee user, then verify direct SQL behavior.

    ```bash
    rm -rf "${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}"
    ./04_get_iam_oauth_token.sh --headless
    ./06_verify_as_employee.sh
    ```

2. Re-run the AI app prompt, MCP tool call, direct SQL query, and analytics check.

3. Confirm that the database filters, redacts, or blocks restricted data.

## Task 3: Validate Privileged Access

1. Switch to the privileged context.

    Get an OCI IAM OAuth token as the manager user, then verify direct SQL behavior.

    ```bash
    rm -rf "${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}"
    ./04_get_iam_oauth_token.sh --headless
    ./05_verify_as_manager.sh
    ```

2. Re-run the same checks.

3. Confirm that permitted data still appears.

## Task 4: Complete the Results Matrix

1. Record the expected and actual result for each path.

    | Access Path | Identity Context | Restricted Result | Privileged Result |
    | --- | --- | --- | --- |
    | AI application | TODO | TODO | TODO |
    | MCP tool call | TODO | TODO | TODO |
    | Direct SQL | TODO | TODO | TODO |
    | Analytics or reporting | TODO | TODO | TODO |

2. Explain which database rule produced each difference.

    TODO: Replace this placeholder with the final policy explanation.

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
