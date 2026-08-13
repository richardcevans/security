# Introduction to Local Deep Data Security and Vibe Coding

## Introduction

You are Marvin, a sales user. An AI coding assistant can modify your customer application and ask Oracle Database for data you should not see. This workshop demonstrates the control that stops generated application code from becoming the final security boundary: Oracle Deep Data Security.

The browser UI is a small Flask application. It begins with intentionally excessive database access, then runs the same query after Deep Data Security replaces that broad grant with employee and manager policies. Vibe can change the application, but it cannot independently grant Marvin more database authorization.

Marvin is a local database-managed end user. He does not require an OCI IAM identity, application registration, or database-access token. The compute instance principal is used separately by Customer Insights and Vibe to call OCI Generative AI; it does not grant either component broader database access than Oracle returns for Marvin.

Estimated Workshop Time: 60 minutes after infrastructure provisioning. Allow additional time for Autonomous Database creation and Python package installation.

### Objectives

- Provision an Autonomous AI Database 26ai instance and retrieve its wallet.
- Create local Deep Data Security end users, data roles, and row- and column-level data grants.
- Deploy a Flask web application that connects directly as Marvin.
- Demonstrate that the same SQL produces database-enforced differences in rows and column values.
- Show that Vibe application changes cannot override database authorization.

## Architecture

```text
Browser local-user sign-in
          |
          v
Flask application on OL9
          |
          | direct password-authenticated local end-user session
          v
Autonomous AI Database 26ai
          |
          | Deep Data Security data roles and data grants
          v
Authorized rows only

Customer Insights and the Vibe coding assistant use the compute instance principal separately for OCI Generative AI.
```

## Prerequisites

- Use an isolated, non-production environment.
- Have permission to create the Stack resources, or obtain the required Stack inputs and ADB administrator password from the lab owner.
- Use the provided Oracle Linux 9 compute instance with JupyterLab.
- Ensure the Stack operator can create the compute-instance dynamic group and `generative-ai-chat` policy in the target compartment. Terraform supplies the default on-demand GenAI model for Customer Insights and Vibe. This instance permission does not create or require an IAM identity for Marvin.

## Download and Deploy the Terraform Stack

You do not install Terraform locally. OCI Resource Manager runs the included Terraform configuration for you.

1. Download [deep-sec-local-genai-terraform.zip](https://objectstorage.us-ashburn-1.oraclecloud.com/p/Qr29aAUJD9vH5NaArxcqfk0CvgpmJBiEGNi9zfVbmHLb4kXq6ULqukuj5DQb2B0N/n/oradbclouducm/b/dbsec_public/o/deep-sec-local-genai-terraform.zip). Keep the ZIP intact; do not unzip it.

2. In the OCI Console, open **Developer Services**, select **Resource Manager**, then select **Stacks** and **Create stack**.

3. Select **My configuration** and **Zip file**, upload `deep-sec-local-genai-terraform.zip`, name the Stack, then select **Next**. Enter the required values, especially the compartment, ADB `ADMIN` password, SSH public key, and home public IPv4 address. Run **Plan**, review it, then run **Apply**.

After Apply completes, begin the main lab and use the Stack **Application Information** tab to open JupyterLab and the `deepsec9` Autonomous Database Console.

You may now proceed to the next lab.

## Acknowledgements

- Oracle Database Security and Oracle LiveLabs teams
