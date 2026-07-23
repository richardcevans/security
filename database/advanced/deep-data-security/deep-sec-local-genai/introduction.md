# Introduction to Local Deep Data Security and Generative AI

## Introduction

AI applications should never decide which customer data a user may see. In this workshop, Oracle Deep Data Security enforces that decision in Oracle Autonomous AI Database 26ai. The browser UI is a small Flask application, but its sign-in control does not filter rows or hide columns. A student supplies the password for Emma, Marvin, or Carol; the app opens a direct database session as that selected local end user and executes one fixed query.

Emma, Marvin, and Carol are local database-managed end users. They do not require OCI IAM identities, application registration, or database-access tokens. The only OCI identity used is the compute instance principal, which calls OCI Generative AI after the database has returned authorized data.

Estimated Workshop Time: 60 minutes after infrastructure provisioning. Allow additional time for Autonomous Database creation and Python package installation.

### Objectives

- Provision an Autonomous AI Database 26ai instance and retrieve its wallet.
- Create local Deep Data Security end users, data roles, and row- and column-level data grants.
- Deploy a Flask web application that connects directly as Emma, Marvin, or Carol.
- Demonstrate that the same SQL produces database-enforced differences in rows and column values.
- Summarize only authorized query results with OCI Generative AI.

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
Authorized rows only ----> OCI Generative AI summary
                         (compute instance principal)
```

## Prerequisites

- Use an isolated, non-production environment.
- Have permission to create the Stack resources, or obtain the required Stack inputs and ADB administrator password from the lab owner.
- Use the provided Oracle Linux 9 compute instance with JupyterLab.
- Ensure the Stack operator can create the compute-instance dynamic group and `generative-ai-chat` policy in the target compartment. Terraform supplies the default on-demand GenAI model. This instance permission does not create or require IAM identities for Emma, Marvin, or Carol.

## Download and Deploy the Terraform Stack

You do not install Terraform locally. OCI Resource Manager runs the included Terraform configuration for you.

1. Download [deep-sec-local-genai-terraform.zip](https://objectstorage.us-ashburn-1.oraclecloud.com/p/Qr29aAUJD9vH5NaArxcqfk0CvgpmJBiEGNi9zfVbmHLb4kXq6ULqukuj5DQb2B0N/n/oradbclouducm/b/dbsec_public/o/deep-sec-local-genai-terraform.zip). Keep the ZIP intact; do not unzip it.

2. In the OCI Console, open **Developer Services**, select **Resource Manager**, then select **Stacks** and **Create stack**.

3. Select **My configuration** and **Zip file**, upload `deep-sec-local-genai-terraform.zip`, name the Stack, then select **Next**. Enter the required values, especially the compartment, ADB `ADMIN` password, SSH public key, and home public IPv4 address. Run **Plan**, review it, then run **Apply**.

After Apply completes, begin the main lab and use the Stack **Application Information** tab to open JupyterLab and the `deepsec7` Autonomous Database Console.

You may now proceed to the next lab.

## Acknowledgements

- Oracle Database Security and Oracle LiveLabs teams
