# Can Application Code Bypass Oracle AI Database Security?

## Introduction

In this lab, you will set up and configure the Customer Sales App where Oracle AI Database, rather than application code, determines the rows and columns each user can access.

Marvin begins with broad access to illustrate the risk. You then build a least-privilege employee data grant, extend that same authorization to data sitting outside the database entirely, add manager access through an end user context, and try to get around all of it using AI-generated code. The application always issues ordinary SQL; the database decides what its current user may receive.

Estimated time: 60 minutes after the Stack is ready.

### Prerequisites

- Complete the [Introduction](introduction.md) and deploy the GreenButton Stack.
- Sign in to **Deep Sec DEMO Setup** as `ADMIN` using the generated lab password.
- Keep the **Customer Sales App** open in a separate browser tab.

## Task 1: Prepare the ordinary database objects

### Browser — Deep Sec DEMO Setup, DB Setup

1. Select **DB Setup**.
2. Run **Prepare App**.
3. Run **Create DB Role**.
4. Run **Review & Quiz** to confirm that the APPLAB schema, customer data, and database role exist.

These steps create ordinary Oracle objects. Deep Data Security has not yet been configured.

## Task 2: Create data roles and initial grants

### Browser — Deep Sec DEMO Setup, Deep Sec Setup

1. Select **Deep Sec Setup**.
2. Run the steps in order:

    1. **Create data roles**
    2. **Create data grants**
    3. **Create end users**
    4. **Grant Data Role**

3. Run **Review & Quiz**.

The initial employee grant is wide open, every row, every column, on purpose. The next task narrows it.

## Task 3: Build a least-privilege employee grant

### Browser — Deep Sec DEMO Setup, Customize Grant; Customer Sales App

1. In **Customize Grant**, exclude the sensitive columns from the employee grant and restrict rows to each sales representative's own accounts. The grant is built as everything except what you explicitly remove, not the other way around.
2. Apply the grant.
3. Return to the Customer Sales App, already open, and select **Customer Report** again.

Marvin now sees only his three customer accounts. Oracle returns `Not authorized` for the columns you excluded.

4. Open **AI Insights** and ask a question about customer data. The AI response is limited to the same database-authorized result.

## Task 4: Extend the same authorization to data outside the database

### Browser — Deep Sec DEMO Setup, Order History; Customer Sales App

1. Select **Order History**. Before touching Oracle at all, this page shows you the raw Apache Iceberg files already sitting in Object Storage, and walks through the layered index Oracle uses to resolve them, metadata, manifest list, manifest files, down to the actual Parquet data.
2. Create the external table. No data moves, Oracle points at the files where they already live.
3. Query it with ordinary SQL, same syntax as any other table, and confirm the row count.
4. Extend the employee grant's authorization to this table too, same exclusion pattern as Task 3, applied to a table that was never inside the database at all.
5. In the Customer Sales App, check order history for Marvin.

The lesson here is the same one from Task 3, just proving it reaches further than you might expect, Deep Data Security doesn't care where the underlying bytes are stored.

## Task 5: Add manager access

### Browser — Deep Sec DEMO Setup, End User Context

1. Complete the manager workflow in order:

    1. **Manager Lookup**
    2. **Manager Context**
    3. **Set Context**
    4. **Manager Data Grant**
    5. **Grant Manager Role**

2. In the Customer Sales App, sign out and sign back in as Marvin.
3. Select **Customer Report** and check order history again.

Marvin remains an employee and now also holds the manager data role. His employee role returns his own accounts; his manager role contributes his team's. The database combines both roles' authorized results automatically.

## Task 6: Create a new Customer Sales App page with Vibe Coding

### Browser — Deep Sec DEMO Setup, Vibe Coding; Customer Sales App

1. Select **Vibe Coding**.
2. Describe the report you want in plain English, for example: `Show me every customer's sensitive identifier.`
3. Select **Create Customer Sales App page**. Vibe Coding generates one read-only SQL statement and publishes a new report URL.
4. Open the new Customer Sales App report page and run the report as Marvin or Emma.
5. Review the generated SQL, the database security context, and the rows Oracle returned.

Vibe Coding does not edit or restart the Customer Sales App. The page uses a permanent report route that reads the generated report definition at runtime, then connects as the signed-in local database user. However the request is phrased, Oracle still returns only the rows and columns that user's active data roles authorize.

## Task 7: Validate and reset

### Browser — Deep Sec DEMO Setup, Admin

1. Select **Admin** and run the validation comparison. Emma and Marvin's active roles, applicable grants, authorized columns, and row rules are read directly from Oracle and shown side by side.
2. Use the reset options available on this page if you need to repeat a section of the lab.

## Clean up

When finished, destroy the Resource Manager Stack. The GreenButton destroy workflow removes its stack-specific Object Storage objects and pre-authenticated requests before deleting the bucket.

## Acknowledgements

- **Author** - Richard Evans
- **Last Updated** - September 2026
