# Get Started: JupyterLab on the App Server

## Introduction

This workshop uses the JupyterLab service already installed on the DeepSec7 application server. Use its browser file area only to upload the wallet ZIP. Use terminal sessions for the remaining lab commands.

Estimated Time: 5 minutes

### Objectives

- Open JupyterLab from the Resource Manager Stack output.
- Upload the wallet ZIP without exposing it in source control or Object Storage.
- Use separate terminals for the running web server and later cleanup commands.

### Prerequisites

- A completed Resource Manager Apply job with a `jupyter_url` output.
- The wallet ZIP downloaded from the `deepsec7` Autonomous Database Console page.

## Task 1: Orient Yourself in JupyterLab

1. Open the `jupyter_url` output from the completed Resource Manager Apply job.

2. Select **+**, then select **Other** and **Terminal**. This opens the first terminal session.

3. Use the JupyterLab file-browser **Upload Files** button only to upload `Wallet_DEEPSEC7.zip` from your computer. Keep the file private.

4. Later, when `run.sh` is running, leave that first terminal open. Select **+**, then **Other** and **Terminal** again to open a second terminal for validation or cleanup.

You may now proceed to the next lab.

## Acknowledgements

- **Author** - Richard Evans
- **Last Updated By/Date** - Richard Evans, July 2026
