# Introduction to Deep Sec GreenButton

## Introduction

This workshop shows that Oracle AI Database, rather than customer-sales application code or an AI coding assistant, determines the rows and columns each end user can access.

You begin with a working customer-sales application and its ordinary Oracle objects. You then create Deep Data Security roles and grants, restrict Marvin to his own accounts, extend his access as a manager, and verify the results in Oracle Customer Sales. The optional Vibe Coding stage creates a new runtime Customer Sales report page, but it cannot override database authorization.

Estimated workshop time: 60 minutes after the Stack is ready. Allow additional time for Autonomous AI Database provisioning and VM bootstrap. GreenButton publishes the checked-in Iceberg sample during bootstrap, so it does not wait for a Data Flow Spark run.

### Objectives

- Deploy the GreenButton Oracle Cloud Infrastructure stack.
- Create data roles, data grants, and local database end users.
- Verify database-enforced row and column authorization in Oracle Customer Sales.
- Add manager access through an end user context.
- Query Order History through an Apache Iceberg external table without copying its data into Oracle.
- See why application changes made with Vibe cannot bypass database authorization.

## Architecture

```text
Browser
  |
  v
Oracle Customer Sales / Deep Sec DEMO Setup on Compute
  |
  | direct local database-user session
  v
Autonomous AI Database 26ai
  |
  | Deep Data Security data roles and grants
  v
Only authorized rows and columns
```

The Stack creates a private Object Storage bucket, publishes the checked-in
Iceberg files into it, and points ADB at the direct metadata JSON. The VM
rewrites the complete metadata and manifest graph for the generated bucket
prefix before creating the external table. ADB reads the existing files as an
external table; the data is not copied into database storage.

## Prerequisites

- An isolated, non-production OCI compartment.
- Permission to create the Stack resources or the supplied Stack inputs from the lab owner.
- An SSH public key for the Compute instance.
- An Oracle-SSO user Auth Token for the ADB Iceberg reader, entered only as a sensitive Stack variable.
- Access to the supplied compute image in the selected OCI region.

## Deploy the GreenButton Stack

1. From the `deep-sec-local-genai` project directory, build both archives:

   ```bash
   bash build_greenbutton_app_zip.sh
   bash build_greenbutton_terraform_zip.sh
   ```

   The Terraform ZIP embeds the application ZIP and the checked-in Iceberg
   sample. Only the Terraform ZIP is uploaded to Resource Manager.
2. In the OCI Console, open **Developer Services**, select **Resource Manager**, then select **Stacks** and **Create stack**.
3. Select **My configuration** and upload the ZIP. Set the working directory to `terraform`.
4. Enter the target tenancy, compartment, region, SSH public key, and the
   ADB reader credential. `order_history_oci_username` must use
   `<identity-domain>/<username>` form. Enter the matching
   `order_history_oci_auth_token` as a sensitive value.
5. Leave the retired Customer Secret Key, user-bucket, shared-dataset, and
   Data Flow inputs empty or disabled. The Stack creates its own private
   Iceberg bucket.
6. Run **Plan**, review the successful plan, and run **Apply**. Apply waits
   for the application VM bootstrap health gate.
7. In **Application Information**, unlock the generated shared password. Open
   the Admin Console URL on port `7778`, Oracle Customer Sales on port `7777`,
   or JupyterLab on port `8888`.

8. If you need to diagnose the deployment, SSH to the Compute public IP and
   run:

   ```bash
   sudo cat /var/lib/deep-sec/bootstrap-status
   sudo tail -n 200 /var/log/deep-sec-bootstrap.log
   ```

   The status file should contain `COMPLETE`.

> The GreenButton Stack currently defaults the browser CIDR to `0.0.0.0/0` for hands-on-lab use. Restrict it before broader use.

You may now proceed to the next lab.

## Acknowledgements

- **Author** - Richard Evans
- **Last Updated** - September 2026
