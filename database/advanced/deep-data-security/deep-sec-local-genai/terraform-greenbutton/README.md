# Deep Sec GreenButton OCI Resource Manager Stack

This is the supported Deep Sec infrastructure path. It creates walletless TLS
Autonomous AI Database 26ai, the GreenButton application VM, private Object
Storage, network resources, and a dedicated Stack-owned Iceberg bucket
containing the pre-created Order History data.

## Deploy

Build and deploy from the parent `deep-sec-local-genai` directory:

```bash
bash build_greenbutton_app_zip.sh
bash build_greenbutton_terraform_zip.sh
```

The second command creates `deep-sec-local-genai-terraform-GreenButton.zip`.
It embeds the application ZIP and the checked-in Iceberg sample, so Resource
Manager needs only this Terraform ZIP.

In OCI Resource Manager:

1. Select **Create stack**, choose **My configuration**, and upload
   `deep-sec-local-genai-terraform-GreenButton.zip`.
2. Set **Working directory** to `terraform`.
3. Select the target tenancy compartment and region. `us-ashburn-1` and
   `DBSec_Rich` are the known-good values for the RICH lab, but use the
   compartment and region where the supplied compute image is available.
4. Provide an SSH public key and an OCI Auth Token for the ADB Iceberg reader:
   `order_history_oci_username` must be in
   `<identity-domain>/<username>` form, and
   `order_history_oci_auth_token` must be entered as a sensitive value.
5. Leave the legacy Customer Secret Key, user-bucket, shared-dataset, and
   Data Flow fields empty/disabled. Leave `create_genai_iam` off unless a
   tenancy administrator specifically wants a new dynamic group and policy.
6. Run **Plan**. After reviewing a successful plan, run **Apply**.

Apply provisions the database, VM, private Object Storage, and the
Stack-owned Iceberg bucket. It waits for the VM bootstrap health gate before
returning success. In **Application Information**, select **Unlock** and copy
the generated password for ADB ADMIN, JupyterLab, and Marvin, then use the
output URLs:

- Admin Console: port `7778`
- Customer Sales: port `7777`
- JupyterLab: port `8888`

The official Resource Manager procedure is [Creating a Stack from a Zip
File](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/create-stack-local.htm).

The Stack's default browser CIDR is temporarily `0.0.0.0/0` (`Wide Open`).
Restrict it before using the lab outside its controlled environment.

On Destroy, GreenButton removes all object versions and pre-authenticated
requests from its unique Stack bucket before deleting the bucket. If a stack
created by an older ZIP reports `PreauthenticatedRequestStillExists`, remove
the listed bucket's remaining PARs once, then rerun Destroy.

## Stack variables

For a GreenButton deployment, enter these values in Resource Manager:

| Variable | Value |
| --- | --- |
| `tenancy_ocid` | Your OCI tenancy OCID. |
| `compartment_ocid` | The target compartment OCID; use `DBSec_Rich` when that is the intended lab compartment. |
| `ssh_public_key` | The public SSH key for the person who will operate this stack. |
| `order_history_oci_username` | The Iceberg reader identity in `<identity-domain>/<username>` form. |
| `order_history_oci_auth_token` | An Auth Token for that same identity-domain user; enter it as a sensitive value. |
| `order_history_bucket_prefix` | Optional object prefix for the pre-created Iceberg table in the dedicated Stack-created bucket. The default is `order_history_iceberg`. |

`region` defaults to `us-ashburn-1`. The browser CIDR currently defaults to
`0.0.0.0/0` for the hands-on-lab environment; restrict it before broader use.
The Compute image OCID is tenancy- and region-specific: a team using a
different tenancy or region must provide an image shared into that tenancy.

The browser access CIDR is also an important deployment input. The default
`0.0.0.0/0` (`Wide Open`) is suitable only for a short controlled test. Set it
to the operator's public IPv4 address or CIDR before using the lab more
broadly.

## Order History delivery

The normal path is intentionally one operation: Apply the Stack. Terraform
creates a dedicated private bucket, uploads the checked-in
`order_history_iceberg_bundle.zip`, and gives the VM short-lived exact-object
PARs. The VM materializer rewrites the complete JSON and Avro metadata graph
for that bucket and prefix, then publishes the table. It does not run Spark,
Data Flow, or generate a new dataset.

The bucket belongs to the tenancy and compartment, not to an individual IAM
user. This Stack creates and cleans up its own dedicated bucket on Destroy, so
the learner does not need to pre-create a bucket or provide a Customer Secret
Key. The only Iceberg credential is the OCI Auth Token used by APPLAB's
`DBMS_CLOUD` reader. The generated ADB reader setup verifies the metadata object
and reads a real Iceberg row before Apply completes.

Legacy delivery-mode, user-bucket, shared-dataset, and Data Flow values may
remain in an upgraded Resource Manager Stack's saved variable map, but the
GreenButton configuration no longer reads them or provisions those paths.

After Apply, verify the VM before opening the applications:

```bash
ssh opc@<compute-public-ip>
sudo cat /var/lib/deep-sec/bootstrap-status
sudo tail -n 200 /var/log/deep-sec-bootstrap.log
```

The status file should contain `COMPLETE`. The bootstrap log should show the
schema creation, Object Storage publication, Iceberg reader setup, and
application health phases. If a phase fails, inspect the run directory named
in the log before retrying the Stack.

### ADB access to the Iceberg warehouse

Create an Oracle-SSO Auth Token for the user who will own the ADB
`DBMS_CLOUD` credential, then enter `order_history_oci_username` and
`order_history_oci_auth_token` as Stack input. Do not put the token in source
control, `terraform.tfvars`, or output files. Resource Manager cannot create
an Oracle-SSO Auth Token or Customer Secret Key through the Identity Domains
API; the retired `create_iceberg_resources` switch must remain false.

OCI Resource Principal authentication is not supported for Autonomous AI
Database Iceberg queries, so GreenButton intentionally does not offer it for
this reader.

The bundle materializer writes through Stack-created Object Storage PARs, while
the separate Auth Token lets ADB read the published dataset. Customer Secret
Key inputs remain accepted for compatibility with older Stack variable maps;
the bundle materializer does not use them. Resource Manager cannot create an
Oracle-SSO Auth Token; provide the existing token as a sensitive input.

The database-side reader follows Oracle's
[DBMS_CLOUD documentation](https://docs.oracle.com/en/cloud/paas/autonomous-database/dedicated/adbaa/dbmscloud-for-objects-and-files.html),
using a direct metadata pointer to the published Iceberg table. The schema
setup also restores the required outbound Object Storage ACL when APPLAB is
created. A reset therefore recreates APPLAB and its ACL before the Order
History table setup is run again.

To verify the external table after setup, connect as APPLAB and run:

```sql
SELECT COUNT(*) FROM order_history;
SELECT order_id, customer_id, order_date
FROM order_history
ORDER BY order_date, order_id;
```

The checked-in sample contains 1,500 rows. The external table reads those
files in Object Storage; it does not copy them into ADB.

For a reset, use **Restore to DB Setup** or **Prepare App** in the Admin
Console. Confirm the bootstrap/database log shows `create_schema.sql` and its
Object Storage ACL grant, then rerun the normal Order History table action if
the reset workflow has not already done so.

## Generative AI prerequisite

The Vibe page uses the Compute instance principal. To avoid exhausting the
tenancy dynamic-group quota when many lab stacks deploy concurrently,
GreenButton does **not** create one dynamic group per Stack by default. Before
the lab, a tenancy administrator must provide a shared dynamic group and policy
that allow the GreenButton Compute instances to use `generative-ai-chat` in the
target compartment. Set `create_genai_iam = true` only for a one-off tenancy
that has dynamic-group capacity; it creates a uniquely named per-Stack group
and policy.

## Legacy paths

The former regular, NO-IAM, FREE, and wallet-based deployment paths are under
`../archive/non-greenbutton-20260827/` and are not supported for new stacks.
