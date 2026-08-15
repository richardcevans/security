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
   directory to `terraform`, and choose Terraform 1.5.7 or a later 1.x release.
4. Enter these required variables:

   - `tenancy_ocid`
   - `compartment_ocid`
   - `ssh_public_key`
   - `allowed_ingress_home_ip_address` (your public home IPv4 address, without `/32`)

5. Keep the supplied Ashburn image, BYOL, `My Home IP`,
   `create_genai_iam = true`, and the default on-demand GenAI model
   (`google.gemini-2.5-flash`) unless your lab needs different values.
6. Create the stack, run **Plan**, review the expected resources, then run
   **Apply**.

> **Timing:** Stack provisioning is pre-lab work. It is not part of the 60-minute Deep Data Security hands-on estimate; students begin the timed lab after Apply succeeds.

The outputs provide the ADB OCID, `adb_console_url`, and compute public IP. Terraform generates an Instance Wallet, writes it to the private wallet bucket, and creates a 24-hour, one-object read link that cloud-init uses only on the newly created compute instance. Select **Unlock** and copy the shared ADB `ADMIN`, JupyterLab, and Marvin password before opening either service. The Customer Sales application starts automatically on port 7777. The Admin Console starts automatically on port 7778 and signs in directly as ADB `ADMIN` with that same password. It exposes only fixed, visible SQL*Plus lab actions and shows their output. Jupyter is on port 8888. The VCN permits
all protocols only from the `allowed_ingress_home_ip_address` you entered.

After an Apply job completes, open the Stack **Application Information** tab.
It provides clickable Flask, JupyterLab, and ADB Console links, along with the
application-server IP, service alias, SSH command, GenAI identity, and one
unlockable password shared by ADB `ADMIN`, JupyterLab, and Marvin. Select
**Unlock** and copy it before opening the JupyterLab link; enter the same value
when the database setup script prompts for Marvin in Task 2. Terraform generates
it for the Stack deployment and it replaces the image's former shared password. Use the **Jobs** output page for the complete
`deep_sec_lab_summary`, which groups the ADB, compute, network, wallet bucket,
GenAI identity, application ports, and trusted ingress CIDR in one value.
Terraform also writes the selected GenAI model and policy compartment to the
compute instance as `/home/opc/.deep-sec-genai-defaults`. Customer Insights and
the Vibe CLI read those defaults automatically. Customer Insights sends OCI
Generative AI only the customer rows and columns Oracle returned for Marvin.
Terraform also downloads the public `deep-data-security-flask-app.zip` and
`vibe-cli.zip` files to `/home/opc`, so learners can unpack them without a
second download. It installs the generated ADB wallet at
`/home/opc/deep-sec-wallet/tns_admin`; learners do not download or upload it.

## Reliability Diagnostics

Cloud-init records every bootstrap phase in `/var/log/deep-sec-bootstrap.log`
and sends the same output to the system journal. Both Gunicorn services use
debug-level logs, unbuffered application output, health checks, and automatic
restart. The `operational_debug` Stack output contains copy-ready commands.
On the compute host, the fastest complete diagnostic is:

```shell
sudo /usr/local/sbin/deep-sec-status
```

To follow an individual service while reproducing a problem, run one of:

```shell
sudo journalctl -fu deep-sec-admin-console.service -o short-iso
sudo journalctl -fu deep-sec-customer-sales.service -o short-iso
```

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
