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

## Task 1: Apply Deep Data Security Rules

1. Create or inspect the data roles used by the lab.

    Map identity-domain groups or application roles to database data roles. For example:

    ```sql
    CREATE DATA ROLE employee_data_role
      MAPPED TO 'IAM_GROUP_NAME=employee';
    ```

    TODO: Replace this example with the verified group naming format.

2. Grant the appropriate data access to each data role.

    TODO: Add the final Deep Data Security grant syntax.

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

    TODO: Add the verified identity-switching procedure.

2. Re-run the AI app prompt, MCP tool call, direct SQL query, and analytics check.

3. Confirm that the database filters, redacts, or blocks restricted data.

## Task 3: Validate Privileged Access

1. Switch to the privileged context.

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
