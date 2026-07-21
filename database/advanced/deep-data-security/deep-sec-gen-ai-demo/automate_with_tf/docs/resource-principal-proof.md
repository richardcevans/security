# ADB resource-principal proof point

The external-table scripts use the system credential `OCI$RESOURCE_PRINCIPAL`.
This is created by `DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL()` and avoids
storing a long-lived OCI user credential in the database.

Before `sql/05_create_external_table.sql` is run, test this in a disposable
lab tenancy:

1. Create or adopt the ADB-S and private demo bucket with Terraform.
2. Create a dynamic group whose rule selects only that ADB-S resource.
3. Grant that dynamic group only read/list access to objects in the demo bucket
   or its compartment, using the narrowest policy form supported by the tenancy.
4. Run `sql/04_enable_resource_principal.sql` as ADMIN.
5. Use `DBMS_CLOUD.LIST_OBJECTS('OCI$RESOURCE_PRINCIPAL', '<bucket URI>')` to
   prove the principal can read the bucket and cannot write or read another
   bucket.
6. Run the external-table script twice and query the compensation view.

Do not replace this proof with an OCI user credential. The exact dynamic-group
rule and policy statement are tenancy-specific and are intentionally not
claimed as tested until this integration test passes.
