# Can Application Code or GenAI Bypass Oracle Deep Data Security?

## Introduction

In this lab, you build a customer-sales application where Oracle AI Database, not the application code or an AI prompt, decides which rows and columns each user can see. You then test the same boundary with OCI Generative AI and with data that does not live inside the database.

You do the entire lab inside a guided web console. Every page has numbered steps, a **Run Action** button, notes from DeeBee (your guide), and a short check-your-understanding quiz. You will not need to come back to this document once you are in the console; everything you need is on the page in front of you.

Estimated time: 60 minutes once the Stack is ready. In a hurry? A twenty-minute fast path is described on the console's Overview page.

### Objectives

- Create database end users, data roles, data grants, cross-table data grants, and end user context.
- Walk through Oracle Deep Data Security's core authorization capabilities and observe how each one changes the authorized result.
- Use OCI Generative AI to test natural-language queries against the data already authorized for the signed-in user.
- Verify that GenAI queries cannot override or bypass database authorizations.

### Who this lab is for

- **Security engineers:** see row- and column-level enforcement that no application, script, or AI prompt can override.
- **Database administrators:** every step is real SQL you can open, read, and run yourself.
- **Developers:** watch the application stay completely unchanged while what it returns changes underneath it.
- **Managers and team leads:** least privilege you can demonstrate to an auditor in under an hour.

### Prerequisites

- Complete the [Introduction](introduction.md) and deploy the GreenButton Stack.
- The Stack's **Application Information** tab gives you three URLs and one generated password. The same password is used everywhere in this lab: `ADMIN` in the console, `MARVIN` and `EMMA` in the Customer Sales App, and JupyterLab.

## Task 1: Open the console and start

### Browser — Deep Sec Demo Setup

1. From the OCI Stack page, open the **Deep Sec Demo Setup** application using the link in the **Application Information** tab. Sign in as `ADMIN` with the password shown in the same tab.
2. Read the **Overview** page. It shows the scenario, the architecture, and what each stage does.
3. Press the **?** in the header for a thirty-second tour of the navigation.
4. Select **Start DB Setup** and follow the numbered steps. The console guides you through every stage from here:

    DB Setup → Deep Sec Setup → Customer Sales App → Customize Grant → End User Context → Order History → Exercises → Best Practices

5. Keep the **Customer Sales App** open in a second browser tab using its link from the Stack's **Application Information** tab. The console tells you exactly when to switch to it and what to look for.

    That's the whole lab. The rest of this document is optional.

## Under the hood (optional)

The console runs real SQL against a real Autonomous Database. If you'd rather see or run it yourself, you can.

### JupyterLab and the shell

Open the JupyterLab link from the Stack's **Application Information** tab and sign in with the generated password. From the launcher, open a **Terminal**. You are on the compute VM that hosts both applications.

- Check the applications: `sudo /usr/local/sbin/deep-sec-status`
- Every script the console runs is under `database/` in the deployed application source. Open any of them to read exactly what a step does.

### Connect directly with SQL*Plus

The Stack configures the built-in `deepsec_low` TNS alias for the ADB LOW service; no wallet is required.

```text
sqlplus ADMIN/"<generated password>"@deepsec_low
```

Try the same query the Customer Sales App runs, as Marvin instead of ADMIN, and watch Oracle return a different answer to the identical statement:

```text
sqlplus MARVIN/"<generated password>"@deepsec_low
SQL> SELECT * FROM APPLAB.customers ORDER BY revenue DESC;
```

### SSH

The Stack output `ssh_command` is a ready-to-paste command using the SSH key you supplied at deploy time. Use it if you prefer your own terminal to JupyterLab's.

### Take the scripts with you

The console's **Admin → Downloads** page builds a fresh ZIP of the SQL scripts and the two application source trees, generated from what's actually running on your VM at that moment. Nothing in them is lab-specific magic; they are the statements you would run in your own environment.

## If something doesn't load

If a console or application page returns an error on first open, the VM may still be finishing its bootstrap. Wait a minute and reload. If it persists, open JupyterLab's terminal and run `sudo /usr/local/sbin/deep-sec-status`; both services should report `active (running)`.

## Clean up

When finished, destroy the Resource Manager Stack. This permanently removes the workshop resources. The GreenButton destroy workflow removes its stack-specific Object Storage objects and pre-authenticated requests before deleting the bucket.

## Acknowledgements

- **Author** - Richard Evans
- **Last Updated** - September 2026
