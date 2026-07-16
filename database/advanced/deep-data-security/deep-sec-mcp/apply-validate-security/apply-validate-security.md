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
    <copy>
    cd "$HOME/dbsec-labs/deep-data-security/deep-sec-mcp"
    source ./.deep-sec-mcp.env
    ./01_enable_oci_iam.sh
    ./03_create_data_roles_and_grants.sh
    ./verify_db_setup.sh
    </copy>
    ```

    The data role mapping uses this format:

    ```sql
    <copy>
    CREATE OR REPLACE DATA ROLE hrapp_employees
      MAPPED TO 'IAM_GROUP_NAME=example-domain/deepsec-employees';
    </copy>
    ```

    If you are testing direct SQL*Plus OAuth tokens instead of the MCP token path, set `DATA_ROLE_MAPPING_TYPE=IAM_OAUTH_GROUP` in `.deep-sec-mcp.env`.

2. Grant the appropriate data access to each data role.

    The script creates an employee grant and a manager grant over `hr.employees`.

3. Confirm the rule state before testing.

## Task 2: Validate Restricted Access

1. Switch to the restricted context.

    Get an OCI IAM OAuth token as the restricted employee user, then verify direct SQL behavior.

    ```bash
    <copy>
    rm -rf "${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}"
    ./04_get_iam_oauth_token.sh --headless
    ./06_verify_as_employee.sh
    </copy>
    ```

2. Re-run the same AI prompt and database tool call through the current OAuth token.

    ```bash
    <copy>
    ./simulate_ai_tool_access.sh --mode oauth --prompt all
    </copy>
    ```

3. Confirm that the database filters, redacts, or blocks restricted data.

    Emma should see her own employee row through the sensitive-data prompt. She should not see Marvin's direct reports or unrelated employee rows.

## Task 3: Validate Privileged Access

1. Switch to the privileged context.

    Get an OCI IAM OAuth token as the manager user, then verify direct SQL behavior.

    ```bash
    <copy>
    rm -rf "${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}"
    ./04_get_iam_oauth_token.sh --headless
    ./05_verify_as_manager.sh
    </copy>
    ```

2. Re-run the same AI prompt and database tool call through the current OAuth token.

    ```bash
    <copy>
    ./simulate_ai_tool_access.sh --mode oauth --prompt all
    </copy>
    ```

3. Confirm that permitted data still appears.

    Marvin should see himself and his direct reports. The same prompt and SQL tool call now returns a manager-appropriate result set.

## Task 4: Complete the Results Matrix

1. Compare the prompts against the expected results.

    | Prompt | Identity Context | Expected Result After Controls |
    | --- | --- | --- |
    | Show my employee profile. | Employee | Employee sees only their own row |
    | Show my direct reports. | Manager | Manager sees self and direct reports |
    | Show salary and SSN. | Employee or manager | Sensitive values follow the active data grants |

2. Record the expected and actual result for each path.

    | Access Path | Identity Context | Restricted Result | Privileged Result |
    | --- | --- | --- | --- |
    | AI application | OCI IAM end user | Emma sees only her own row | Marvin sees himself and direct reports |
    | MCP tool call | OCI IAM end user | Same database-filtered result | Same manager-filtered result |
    | Direct SQL | OCI IAM end user | Same database-filtered result | Same manager-filtered result |
    | Analytics or reporting | OCI IAM end user | Same database-filtered result | Same manager-filtered result |

3. Explain which database rule produced each difference.

    `HRAPP_EMPLOYEES_ACCESS` allows employees to see their own row. `HRAPP_MANAGER_ACCESS` allows managers to see direct reports, but excludes SSN for those report rows. The same SQL returns different results because the database evaluates data grants from the active end-user data roles.

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
