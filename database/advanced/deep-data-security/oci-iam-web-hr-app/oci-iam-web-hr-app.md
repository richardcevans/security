# OCI IAM Web HR App with Oracle Deep Data Security

## Introduction

This lab deploys the OCI IAM version of the Web HR App against the Autonomous Database environment created by the ADB OCI IAM lab. A browser user signs in through OCI IAM by using Authorization Code with PKCE. The application verifies the ID token, then uses the user's OAuth access token to open a direct connection to Autonomous Database.

The application does not use an ADMIN password or a shared database account. Oracle Database receives the signed-in user's token and applies the OCI IAM data roles and HR data grants that already protect `HR.EMPLOYEES`. The same SQL can return different data or reject an update for different users because authorization remains in the database.

### Prerequisites

- Complete the ADB OCI IAM lab through the HR schema, OCI IAM group, data role, and data grant setup. Retain its `.adb-oci-iam.env` file and wallet.
- Have the `deep-sec-mcp` directory available. Its `.deep-sec-mcp.env` file must contain `OCI_DOMAIN_URL`, `OCI_CLIENT_ID`, `OCI_SCOPE`, `ADB_SERVICE`, `TNS_ADMIN`, and `WALLET_PWD`.
- Use a Compute VM or another app host that can receive browser traffic on TCP port 8012. Configure the VCN security list or network security group and the host firewall if they restrict this port.
- Use an HTTPS URL that users can reach. The OCI IAM public client must register the exact callback URL, including its scheme, host, port, and `/callback` path.

### Objectives

- Configure the Web HR App with an HTTPS callback URL.
- Add that callback URL to the existing OCI IAM public client.
- Start the app and authenticate an OCI IAM user.
- Verify the database identity and database-enforced HR access.

Estimated Time: 45 minutes

## Task 1: Download the Web HR App Code

1. In a terminal on the application host, change to the Deep Data Security lab directory.

    ```bash
    <copy>
    cd $DBSEC_LABS/deep-data-security
    </copy>
    ```

2. Download the published Web HR App bundle from OCI Object Storage by using its read-only Pre-Authenticated Request (PAR) URL.

    ```bash
    <copy>
    wget -O oci-iam-web-hr-app.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/qlgNacu97lpENtc8KA59BMyLL3z4zJZas8opcbPkxSgnTPirn2SqF9_beS9cDy41/n/oradbclouducm/b/dbsec_public/o/oci-iam-web-hr-app.zip
    </copy>
    ```

3. Extract the bundle and enter the application directory.

    ```bash
    <copy>
    unzip -o oci-iam-web-hr-app.zip
    cd oci-iam-web-hr-app
    </copy>
    ```

## Task 2: Prepare the Application Host

1. On the application host, change to the OCI IAM Web HR App directory. The directory is part of the Deep Data Security lab bundle.

    ```bash
    <copy>
    cd $DBSEC_LABS/deep-data-security/oci-iam-web-hr-app
    ls -1
    </copy>
    ```

2. Ensure that the DeepSec environment file and its wallet are available at the sibling path expected by `run.sh`. If you copied them from another host, keep the environment file and wallet readable only by the application account.

    ```bash
    <copy>
    test -r ../deep-sec-mcp/.deep-sec-mcp.env
    source ../deep-sec-mcp/.deep-sec-mcp.env
    test -f "$TNS_ADMIN/tnsnames.ora"
    env | grep -E '^(ADB_SERVICE|OCI_DOMAIN_URL|OCI_CLIENT_ID|OCI_SCOPE|TNS_ADMIN)=' | sort
    </copy>
    ```

3. Create a Python virtual environment and install the app dependencies.

    ```bash
    <copy>
    python3 -m venv ~/deepsec-venv
    ~/deepsec-venv/bin/pip install --upgrade pip
    ~/deepsec-venv/bin/pip install -r requirements.txt
    </copy>
    ```

## Task 3: Configure HTTPS and the OAuth Callback

1. Set `WEB_HR_PUBLIC_HOST` to the DNS name or public IP address that the browser will use. Keep the same host value throughout this lab.

    ```bash
    <copy>
    export WEB_HR_PUBLIC_HOST="YOUR_PUBLIC_HOST"
    export WEB_HR_PUBLIC_URL="https://${WEB_HR_PUBLIC_HOST}:8012"
    </copy>
    ```

2. Create a self-signed certificate for this lab. Replace it with a certificate issued by a trusted certificate authority for a production deployment.

    ```bash
    <copy>
    mkdir -p certs
    openssl req -x509 -newkey rsa:2048 -nodes -days 7 \
      -keyout certs/web-hr.key \
      -out certs/web-hr.crt \
      -subj "/CN=${WEB_HR_PUBLIC_HOST}"
    chmod 600 certs/web-hr.key
    </copy>
    ```

3. Create the local app configuration. Do not add this file to source control because it identifies the deployed endpoint and can include environment-specific values.

    ```bash
    <copy>
    cat > .env <<EOF
    WEB_HR_HOST=0.0.0.0
    WEB_HR_PORT=8012
    WEB_HR_REDIRECT_URI=${WEB_HR_PUBLIC_URL}/callback
    WEB_HR_TNS_ALIAS=${ADB_SERVICE}
    WEB_HR_TLS_CERT=$(pwd)/certs/web-hr.crt
    WEB_HR_TLS_KEY=$(pwd)/certs/web-hr.key
    EOF
    chmod 600 .env
    </copy>
    ```

4. Inspect the callback URI. OCI IAM compares this value exactly with the URI stored on the public client.

    ```bash
    <copy>
    grep '^WEB_HR_REDIRECT_URI=' .env
    </copy>
    ```

## Task 4: Register the Callback on OCI IAM

1. On the host where you completed the ADB OCI IAM lab, source its environment and append the Web HR callback to the existing public-client redirect URIs. Do not remove the callbacks already used by the prerequisite lab.

    ```bash
    <copy>
    cd $DBSEC_LABS/deep-data-security/adb-oci-iam
    source ./.adb-oci-iam.env
    export WEB_HR_REDIRECT_URI="https://YOUR_PUBLIC_HOST:8012/callback"
    export OCI_REDIRECT_URIS="${OCI_REDIRECT_URIS},${WEB_HR_REDIRECT_URI}"
    ./00_setup_adb.sh
    </copy>
    ```

2. Confirm that the prerequisite setup reports the registered redirect URIs and the public-client ID. If the callback shown by the command differs from the value in the app's `.env`, correct the mismatch before starting the app.

    ```bash
    <copy>
    source ./.adb-oci-iam.env
    printf '%s\n' "$OCI_CLIENT_ID" "$OCI_REDIRECT_URIS"
    </copy>
    ```

## Task 5: Run and Verify the Application

1. Return to the application directory and start the server in the background.

    ```bash
    <copy>
    cd $DBSEC_LABS/deep-data-security/oci-iam-web-hr-app
    PYTHON_BIN=~/deepsec-venv/bin/python ./start.sh
    ./status.sh
    </copy>
    ```

2. Open `https://YOUR_PUBLIC_HOST:8012` in a browser. Accept the temporary certificate warning if you used the self-signed lab certificate. Then select **Sign In With OCI IAM** and authenticate as a prerequisite-lab user.

3. Select **Load Employees**. The response comes from `HR.EMPLOYEES`, but the available rows and permitted updates are enforced by the database for the signed-in identity.

4. Open **Diagnostics**, then run the preflight check. Confirm that it reports a successful OCI IAM token connection, database identity, and data-grant query. The database context should show the authenticated OCI IAM user and an OAuth authentication method.

5. Select **Switch OCI IAM User**, authenticate as a user with a different data role, and repeat the employee query. Compare the database response rather than relying on a client-side role check.

## Task 6: Troubleshoot and Stop the App

1. If login fails, compare the URI reported by the app with the URI registered on the OCI IAM public client. The scheme, host, port, and `/callback` path must match exactly.

    ```bash
    <copy>
    grep '^WEB_HR_REDIRECT_URI=' .env
    tail -n 80 logs/web-hr-app.log
    </copy>
    ```

2. If the preflight fails before the HR query, confirm that the app can read the wallet and that the TNS alias exists.

    ```bash
    <copy>
    source ../deep-sec-mcp/.deep-sec-mcp.env
    test -r "$TNS_ADMIN/tnsnames.ora" && echo "Wallet configuration is present"
    grep -i "^${ADB_SERVICE}[[:space:]]*=" "$TNS_ADMIN/tnsnames.ora"
    </copy>
    ```

3. Stop the background server when the lab is complete.

    ```bash
    <copy>
    ./stop.sh
    </copy>
    ```

You may now proceed to the next lab.

## Learn More

- [Oracle Autonomous Database documentation](https://docs.oracle.com/en/cloud/paas/autonomous-database/)
- [OCI Identity and Access Management documentation](https://docs.oracle.com/en-us/iaas/Content/Identity/home.htm)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
