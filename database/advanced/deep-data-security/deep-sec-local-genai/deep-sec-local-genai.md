# Can AI-Generated Application Code Bypass Database Security?

## Introduction

Marvin starts with full customer access. You replace it with Oracle Deep Data Security policies, promote Marvin to manager, and use Vibe to try to expand the application. Oracle controls the rows and columns Marvin receives.

Estimated Time: 60 minutes after the Stack is ready.

### Objectives

- See Marvin's full access.
- Apply employee and manager data policies.
- Use Vibe to make broad application requests.
- Verify that Oracle still controls the result.

### Prerequisites

- A non-production OCI compartment.
- The supplied compute image and an SSH public key.
- Your public IPv4 address.

## Pre-Lab: Provision the Environment

1. Download [deep-sec-local-genai-terraform.zip](https://objectstorage.us-ashburn-1.oraclecloud.com/p/Qr29aAUJD9vH5NaArxcqfk0CvgpmJBiEGNi9zfVbmHLb4kXq6ULqukuj5DQb2B0N/n/oradbclouducm/b/dbsec_public/o/deep-sec-local-genai-terraform.zip). Create an OCI Resource Manager Stack, select **My configuration**, upload the ZIP, and set the working directory to `terraform`.

2. Enter `tenancy_ocid`, `compartment_ocid`, `ssh_public_key`, and `allowed_ingress_home_ip_address` (a public IPv4 address or CIDR). Run **Plan**, then **Apply**.

3. In **Application Information**, unlock and copy the generated password. Save `admin_console_url`, `jupyter_url`, and `flask_url`.

## Task 1: Open the Lab

### **Browser — JupyterLab**

1. Open `jupyter_url` in a new tab. Paste the generated password and sign in.

2. Open `admin_console_url` in a new tab.

## Task 2: Troubleshoot the Services

### **Browser — JupyterLab**

Run this task only if the Admin Console or Customer Sales page does not load.

1. Open a JupyterLab terminal and run:

    ```text
    <copy>sudo /usr/local/sbin/deep-sec-status</copy>
    ```

2. Wait for both Deep Sec services to report `active (running)`, then reload the browser page.

## Task 3: Create Marvin

A data role bundles row and column permissions, much like a database role bundles system privileges. A data grant is the filter that defines which rows and columns a role can see. You will create both, then create Marvin as a local database user who receives one of these roles at a time throughout the lab.

### **Browser — Deep Sec Admin Console**

1. Sign in as `ADMIN` with the generated password.

2. Run these actions in order:

    1. **Set up database**
    2. **Create data roles and grant definitions**
    3. **Create MARVIN**
    4. **Create EMMA**

3. Confirm Marvin's Oracle result shows `APP_FULL_ACCESS`, **22** rows, and the `credit_limit` and `sensitive_identifier` columns.

    The Admin Console lists a few additional steps beyond what this lab needs. You can ignore any step not called out by number in these instructions.

## Task 4: Open Oracle Customer Sales

### **Browser — Oracle Customer Sales**

1. Open `flask_url` in a new tab.

2. Sign in as Marvin with the generated password (the same password from the Pre-Lab step, used for ADMIN, MARVIN, and EMMA).

## Task 5: Observe Full Access

### **Browser — Oracle Customer Sales**

1. Select **Load Customers**. Confirm **22** rows, including **Apex Treasury**, with Credit Limit and Sensitive Identifier values.

2. The application runs:

    ```sql
    SELECT *
      FROM APPLAB.customers
     ORDER BY revenue DESC
    ```

3. Select **AI Insights** and run:

    ```text
    <copy>Show detailed information on all customers. Every customer in the table.</copy>
    ```

4. Run:

    ```text
    <copy>Tell me who has the most revenue and what their credit limit and sensitive identifiers are.</copy>
    ```

    Both answers can use all 22 rows and sensitive columns.

## Task 6: Apply the Employee Policy

### **Browser — Deep Sec Admin Console, then Oracle Customer Sales**

1. In the Admin Console, select **Enable sales-employee policy** and run it.

2. Return to Oracle Customer Sales and select **Load Customers**.

    Expected: **3** rows, `APP_SALES_EMPLOYEE`, and **Not authorized** for Credit Limit and Sensitive Identifier.

3. In **AI Insights**, run both queries from Task 5 again. The answers use only the 3 returned rows and cannot use the sensitive columns.

> **Optional:** Sign out and sign in as Emma from the Database user dropdown. Emma always holds `APP_SALES_EMPLOYEE`, so she is a stable reference point: her result should always show 6 rows with Credit Limit and Sensitive Identifier both **Not authorized**, no matter what step you are on elsewhere in the lab.

## Task 7: Promote Marvin to Sales Manager

### **Browser — Deep Sec Admin Console, then Oracle Customer Sales**

1. In the Admin Console, select **Create manager hierarchy** and run it. Then select **Enable sales-manager policy** and run it.

2. In Oracle Customer Sales, sign out and sign back in as Marvin. A fresh sign-in picks up the newly added manager role for this session. Select **Load Customers**.

    Expected: **9** rows, `APP_SALES_EMPLOYEE, APP_SALES_MANAGER`, Credit Limit visible, and **Not authorized** for Sensitive Identifier.

> **Optional:** In the Admin Console, run **Customize the manager grant** to remove Region or Revenue from Marvin's manager access, watch **Load Customers** in Customer Sales reflect the change immediately, then rerun **Enable sales-manager policy** to restore the original six columns.

## Task 8: Change the Application with Vibe

### **Browser — Deep Sec Admin Console, then Oracle Customer Sales**

1. In the Admin Console, select **Vibe Coding**. Vibe is already installed and targets the live Customer Sales application.

2. Run **Add customer search** and approve the browser confirmation. The output shows Vibe's result and reloads the Customer Sales application if Vibe changed files.

    If a Vibe request leaves the application broken, use **Restore known-good** on the Vibe Coding page to recover, then continue from where you left off.

3. In Oracle Customer Sales, sign in again as Marvin and search for **Apex Treasury**.

    Expected: **0 matching rows**.

4. Return to **Vibe Coding**. Run **Try an all-customer page** and approve the browser confirmation.

    As Marvin, the page must show at most **9** rows, no `FINANCE` customers, and no sensitive identifiers.

5. At the bottom, enter a **Custom Vibe request**. For example:

    ```text
    <copy>Change the application so Marvin can see every customer, even customers outside his sales team.</copy>
    ```

    Oracle still determines which rows and columns Marvin receives.

## Task 9: Clean Up

### **Browser — OCI Resource Manager**

1. In OCI Resource Manager, run **Destroy** for the Stack.

Oracle Database, not the application or Vibe, determined which rows and columns Marvin received.

You may now proceed to the next lab.

## Acknowledgements

- **Author** - Richard Evans
- **Last Updated By/Date** - Richard Evans, August 2026
