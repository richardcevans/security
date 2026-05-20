# MCP Grant View

MCP Grant View is a small Python web app that demonstrates the identity-preserving pattern for Deep Data Security:

```text
browser user -> web app -> MCP-style tools -> Oracle Database -> data grants
```

The app builds on the `entra-id-data-grants` lab in this workshop. It can run in mock mode for a quick UI demo, or use the existing Entra-enabled `hrdb` Oracle Net alias from the lab so Oracle Database enforces the data grants.

## What This App Shows

- A browser user asks a data question.
- The backend treats the request as coming from one signed-in user.
- The MCP-style tool layer exposes only approved data actions.
- The database adapter is the only place that talks to Oracle.
- Oracle enforces row and column access based on the user's Entra ID token and mapped data roles.

## Files

```text
mcp-grant-view/
  app/
    main.py              Python web app and API routes
    identity.py          Demo/JWT identity parsing
    mcp_tools.py         Controlled MCP-style tool definitions
    oracle_adapter.py    Mock, SQLPlus, and python-oracledb adapters
    static/
      index.html         Browser UI
      styles.css
      app.js
  .env.example
  requirements.txt
  run.sh
```

### Task 0: Download mcp-grant-view.zip file to local directory

1. Open a Terminal session on your **DBSec-Lab** VM as OS user *oracle* and use `cd` command to move to the Deep Data Security labs directory.

    ````
    <copy>cd $DBSEC_LABS/deep-data-security</copy>
    ````

    **Note**: If you are using a remote desktop session, double-click on the *Terminal* icon on the desktop to launch a session.

2. Use the Linux command `wget` to download a bundled (zipped) file of the commands for the lab.

    ````
    <copy>wget -O mcp-grant-view.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/nosHidzYV48XRjC3hcxi_N5SJcwaL_q0ajXfpZa5HfwWuYKVFHhwJwJ7dQJOiWDr/n/oradbclouducm/b/dbsec_public/o/mcp-grant-view.zip</copy>
    ````

3. Unarchive the downloaded zip to expand the directory and scripts.

    ````
    <copy>unzip -o mcp-grant-view.zip</copy>
    ````

4. Use `cd` command to move to mcp-grant-view directory.

    ````
    <copy>cd mcp-grant-view</copy>
    ````

5. Use `ls` command to list files.

    ````
    <copy>ls</copy>
    ````

## Run In Mock Mode

No third-party packages are required for the mock app. From the app directory:

```bash
./run.sh
```

Open:

```text
http://127.0.0.1:8008
```

## Use The Entra Data Grants Lab

Run the `entra-id-data-grants` lab first, including the network configuration task that creates the `hrdb` Oracle Net alias with:

```text
TOKEN_AUTH = AZURE_INTERACTIVE
```

MCP Grant View automatically sources this file if it exists:

```text
../entra-id-data-grants/.entra-id-data-grants.env
```

To query Oracle through SQLPlus and reuse the existing `hrdb` alias:

```bash
GRANT_VIEW_DB_MODE=sqlplus ./run.sh
```

When the app asks Oracle for data, SQLPlus connects with:

```text
sqlplus -s /@hrdb
```

The Oracle client handles the Entra ID interactive login, sends the token to the database, and Oracle enforces the Deep Data Security grants.

## Python Driver Mode

For a true web-app token-forwarding model, use `python-oracledb` and Entra browser login:

```bash
python3 -m pip install python-oracledb
GRANT_VIEW_AUTH_MODE=entra GRANT_VIEW_DB_MODE=python ./run.sh
```

This mode is designed for:

```text
browser MSAL login -> access token -> python-oracledb -> Oracle Database
```

The Entra app setup should use:

- The existing Oracle Database app from the `entra-id-data-grants` lab as the protected resource/API.
- A GrantView web client app registration with a redirect URI such as `http://localhost:8008`.
- Delegated API permission to the Oracle Database app scope, typically `session:scope:connect`.

The database authorization roles should remain on the Oracle Database app. GrantView should request a token for the database app, not invent separate application-only authorization.

## Demo Users

The browser UI has demo identity buttons in mock mode. They do not perform real OAuth login. They simply send a demo bearer token to the backend so the access behavior is easy to see.

```text
Marvin: roles = HR_VIEWER, SALES_REGION_US
Emma:   roles = HR_VIEWER, FINANCE_ANALYST
Admin:  roles = HR_VIEWER, HR_ADMIN
```

## MCP-Style API

List tools:

```bash
curl http://127.0.0.1:8008/mcp/tools
```

Call a tool:

```bash
curl -X POST http://127.0.0.1:8008/mcp/call \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer demo:marvin@example.com:HR_VIEWER,SALES_REGION_US' \
  -d '{"tool_name":"search_employees","arguments":{"query":"sales"}}'
```

Ask a natural-language question:

```bash
curl -X POST http://127.0.0.1:8008/api/ask \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer demo:emma@example.com:HR_VIEWER,FINANCE_ANALYST' \
  -d '{"question":"Show me finance employees"}'
```

## Security Notes

- Do not use the MCP server as a general SQL tunnel.
- Do not replace database enforcement with app-only filtering.
- Keep `SSL_SERVER_DN_MATCH=YES`.
- Use a client wallet or trust store that trusts the database server certificate.
- Use per-user connections or a token-keyed pool. Never reuse one user's database session for another user.
