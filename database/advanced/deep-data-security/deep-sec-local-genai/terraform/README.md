# OCI Resource Manager Stack

Use this folder only to create and later destroy the lab infrastructure:

- Autonomous AI Database 26ai, BYOL
- Flask compute instance from the supplied Ashburn image
- Disposable VCN, subnet, gateway, routing, and security list
- Private wallet bucket
- Compute dynamic group and OCI Generative AI chat policy

It does not create OCI IAM users or database users. The database SQL scripts
create Marvin as a local database user.

## Run in OCI Resource Manager

1. Download `deep-sec-local-genai-terraform.zip`. Do not unzip it.
2. In the OCI Console, open **Developer Services**, **Resource Manager**, and
   **Stacks**, then select **Create stack**.
3. Select **My configuration**, upload that ZIP, set the configuration working
   directory to `terraform`, and choose Terraform 1.5.x.
4. Enter these required variables:

   - `tenancy_ocid`
   - `compartment_ocid`
   - `adb_admin_password` (mark it sensitive)
   - `ssh_public_key`
   - `allowed_ingress_home_ip_address` (your public home IPv4 address, without `/32`)

5. Keep the supplied Ashburn image, BYOL, `My Home IP`,
   `create_genai_iam = true`, and the default on-demand GenAI model
   (`google.gemini-2.5-flash`) unless your lab needs different values.
6. Create the stack, run **Plan**, review the expected 10 resources, then run
   **Apply**.

The outputs provide the ADB OCID, `adb_console_url`, and compute public IP. Open
`adb_console_url`, select **Database connection**, and download an **Instance
Wallet** for the browser-based JupyterLab setup. Open the Flask URL at the
compute public IP on port 7777. Jupyter is on port 8888. The VCN permits
all protocols only from the `allowed_ingress_home_ip_address` you entered.

After an Apply job completes, open the Stack **Application Information** tab.
It provides clickable Flask, JupyterLab, and ADB Console links, along with the
application-server IP, service alias, SSH command, GenAI identity, and an
unlockable ADB `ADMIN` password. Use the **Jobs** output page for the complete
`deepsec9_lab_summary`, which groups the ADB, compute, network, wallet bucket,
GenAI identity, application ports, and trusted ingress CIDR in one value.
Terraform also writes the selected GenAI model and policy compartment to the
compute instance as `/home/opc/.deepsec9-genai-defaults`. Customer Insights and
the Vibe CLI read those defaults automatically. Customer Insights sends OCI
Generative AI only the customer rows and columns Oracle returned for Marvin.

## Required IAM Privileges

The identity that runs the Stack job needs permission in the lab compartment to
create the database, VM, networking, and wallet bucket. A tenancy administrator
can grant a Stack-operator group policies such as:

```
Allow group <stack-operators> to manage autonomous-databases in compartment <lab-compartment>
Allow group <stack-operators> to manage instance-family in compartment <lab-compartment>
Allow group <stack-operators> to manage virtual-network-family in compartment <lab-compartment>
Allow group <stack-operators> to manage object-family in compartment <lab-compartment>
Allow group <stack-operators> to read objectstorage-namespaces in tenancy
```

With `create_genai_iam = true`, it also needs these tenancy-level permissions:

```
Allow group <stack-operators> to manage dynamic-groups in tenancy
Allow group <stack-operators> to manage policies in tenancy
```

Those last two policies permit creation of the dynamic group tied to this one
VM and its `generative-ai-chat` policy. They do not create IAM users. If they
are unavailable, set `create_genai_iam = false` and have a tenancy administrator
create the dynamic group and policy separately.

## Clean Up

When the lab ends, run a **Destroy** job for this Stack. It removes the ADB,
VM, bucket, IAM resources, and disposable networking created by the Stack.
