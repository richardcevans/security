# Traceability

## Source Inputs

- `deepsec-demos-tanisha-langchain-poc-demo.zip`
- `python-langchain-oci/README.md`
- `python-langchain-oci/setup.sql`
- `python-langchain-oci/get_user_token.py`
- `python-langchain-oci/db_conn.py`
- `python-langchain-oci/langchain_app.py`
- `python-langchain-oci/langchain_tools.py`
- `python-langchain-msei/README.md`
- `python-langchain-msei/setup.sql`
- `python-langchain-msei/get_user_token.py`
- `python-langchain-msei/db_connection.py`
- `python-langchain-msei/langchain_app.py`
- `python-langchain-msei/langchain_tools.py`

## Mapping

| LiveLabs content | Source basis |
| --- | --- |
| Prerequisites | Both README files and environment examples |
| OCI IAM path | `python-langchain-oci/README.md`, `.env.example`, `oci_app_default_config.ini`, `get_user_token.py`, `db_conn.py` |
| Microsoft Entra ID path | `python-langchain-msei/README.md`, `.env.example`, `get_user_token.py`, `db_connection.py` |
| Database setup | Both `setup.sql` files |
| Application runtime | Both `langchain_app.py` files |
| Validation prompts | `langchain_tools.py` system prompts and table restrictions |

## Preserved Source Gaps

- Several source files contain masked values or placeholders that must be replaced before execution.
- The OCI IAM `db_conn.py` token paths are hard-coded placeholders and must be updated after token generation.
- The Microsoft Entra ID `app_config.py` source contains placeholder syntax that should be corrected before runtime testing.
- The Microsoft Entra ID `setup.sql` source contains sample email placeholders and markdown-style mail links that should be normalized before execution.
- The source package does not include screenshots.
