# Get Started: JupyterLab on the App Server

## Introduction

JupyterLab is already installed on the Deep Sec application server. The Customer Sales App and Admin Console also run automatically after deployment. Use JupyterLab Terminal tabs for diagnostic commands; no terminal setup is needed to begin the walkthrough.

Estimated Time: 5 minutes

### Objectives

- Open JupyterLab from the stack's **Application Information** tab.
- Locate the two Terminal tabs already open by default.
- Understand where to run diagnostic commands.

### Prerequisites

- A completed Resource Manager Apply job.
- The JupyterLab URL and generated password from **Application Information**.

## Task 1: Open a JupyterLab terminal

1. Open **JupyterLab** from the stack's **Application Information** tab and sign in with the generated password.

2. Select either of the two **Terminal** tabs already open by default. These terminals run commands on the Compute VM that hosts the applications.

3. If both Terminal tabs are closed, select **File → New → Terminal**.

4. Run diagnostic commands, such as `journalctl`, in a Terminal tab. Do not run them in a Python notebook cell or a terminal on your own computer.

5. The current deployment uses TLS connections without a database wallet. The `deepsec_low` SQL*Plus alias is already configured; you do not need to download or upload a wallet.

You may now proceed to the next lab.

## Acknowledgements

- **Author** - Richard Evans
- **Last Updated** - October 2026
