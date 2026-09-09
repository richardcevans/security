# Introduction to Deep Sec GreenButton and OCI Generative AI

## Introduction

This workshop is a guided build of Oracle Deep Data Security on Oracle Autonomous AI Database. You will create database end users, data roles, data grants, cross-table data grants, and an end user context, then test the resulting policies from the Customer Sales App and OCI Generative AI.

You begin with a working Customer Sales App and its ordinary Oracle objects. You create Marvin and Emma as local database end users, build employee and manager data roles, and define row- and column-level access with data grants. You then extend those policies to Order History through a cross-table data grant and use an end user context to add manager access. At each stage, you test the results with ordinary queries and with different natural-language questions in Customer Insights. OCI Generative AI receives only the rows and columns Oracle has already authorized for the signed-in user; changing the question cannot override or bypass database authorizations.

Estimated Workshop Time: 60 minutes after the Stack is ready. Allow additional time for Autonomous AI Database provisioning and VM bootstrap. GreenButton publishes the checked-in Iceberg sample during bootstrap, so it does not wait for a Data Flow Spark run.

### Objectives

- Deploy the GreenButton Oracle Cloud Infrastructure stack.
- Create local Deep Data Security end users, data roles, and data grants.
- Verify database-enforced row and column authorization in the Customer Sales App.
- Extend authorization to Order History through a cross-table data grant.
- Add manager access through an end user context.
- Query Order History through an Apache Iceberg external table without copying its data into Oracle.
- Use OCI Generative AI to test different questions against the authorized customer data.
- Show that GenAI queries cannot override or bypass database authorizations.

## Architecture

```text
Browser
  |
  v
Customer Sales App / Deep Sec Demo Setup on Compute
  |
  | direct local database-user session
  v
Autonomous AI Database 26ai
  |
  | Deep Data Security data roles and grants
  v
Only authorized rows and columns
  |
  | authorized customer result set
  v
OCI Generative AI / Customer Insights
```

The Stack creates a private Object Storage bucket, publishes the checked-in
Iceberg files into it, and points ADB at the direct metadata JSON. The VM
rewrites the complete metadata and manifest graph for the generated bucket
prefix before creating the external table. ADB reads the existing files as an
external table; the data is not copied into database storage.

Customer Insights sends the signed-in user's Oracle-authorized customer rows to
OCI Generative AI. The AI service can answer different questions about that
result set, but it does not receive or independently query rows and columns
that Oracle did not authorize.

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
4. Configure the following core inputs. The current GreenButton path generates
   the shared database password after deployment, so `adb_admin_password` is
   intentionally not an input.

   | Input | What it means |
   | --- | --- |
   | `tenancy_ocid` | The OCID of the OCI tenancy where Resource Manager will create tenancy-scoped resources. |
   | `compartment_ocid` | The target compartment for the database, compute instance, networking, and lab resources. |
   | `adb_admin_password` | Not entered for this Stack. GreenButton generates the shared ADB `ADMIN`, JupyterLab, and Marvin password and exposes it in **Application Information** after Apply. |
   | `ssh_public_key` | The public half of the SSH key that will be authorized on the application Compute instance. Keep the private key; it is not uploaded to the Stack. |
   | `allowed_ingress_home_ip_address` | The public IPv4 address or CIDR allowed to reach the lab services. A single address is treated as `/32`; restrict the default `0.0.0.0/0` before broader use. |
   | `create_genai_iam` | Whether Terraform creates a dynamic group and policy that allow the new Compute instance to call OCI Generative AI. Enable it when the tenancy does not already authorize that instance through an existing policy; leave the current default unchanged when the required authorization already exists or tenancy quota is constrained. |

   The Stack also requires the Order History reader identity and matching OCI
   Auth Token. `order_history_oci_username` must use
   `<identity-domain>/<username>` form. Enter the matching
   `order_history_oci_auth_token` as a sensitive value.
5. Leave the retired Customer Secret Key, user-bucket, shared-dataset, and
   Data Flow inputs empty or disabled. The Stack creates its own private
   Iceberg bucket.
6. Select **Plan**. Review the plan and confirm it completes successfully
   before continuing.
7. Select **Apply**. Apply waits for the application VM bootstrap health gate.
8. In **Application Information**, unlock the generated shared password. Open
   the Admin Console URL on port `7778`, Customer Sales App on port `7777`,
   or JupyterLab on port `8888`.

9. If you need to diagnose the deployment, SSH to the Compute public IP and
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
