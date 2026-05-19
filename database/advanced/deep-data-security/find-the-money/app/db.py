import json
import os
import re
from decimal import Decimal
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from app.identity import decode_jwt_without_validation, public_claims


MOCK_ALERTS = [
    {
        "alert_id": "ALT-1042",
        "case_id": "CASE-1042",
        "transaction_id": "TXN-90017",
        "severity": "High",
        "reason": "Round-dollar wire through a new vendor with shared beneficial ownership.",
        "amount": 248500,
        "status": "Open",
    },
    {
        "alert_id": "ALT-1088",
        "case_id": "CASE-1088",
        "transaction_id": "TXN-90112",
        "severity": "Medium",
        "reason": "Invoice splitting pattern across three payments in 24 hours.",
        "amount": 73500,
        "status": "Review",
    },
]

MOCK_CASES = [
    {
        "case_id": "CASE-1042",
        "title": "Northstar vendor passthrough",
        "assigned_to": "priya@example.com",
        "risk_score": 92,
        "summary": "Customer funds moved through a vendor and returned to a related party account.",
    },
    {
        "case_id": "CASE-1088",
        "title": "Invoice splitting through shell vendor",
        "assigned_to": "marcus@example.com",
        "risk_score": 77,
        "summary": "Three payments below approval threshold share memo text and vendor ownership.",
    },
]


class FindMoneyDatabase(object):
    def __init__(self):
        self.mode = os.getenv("FIND_MONEY_DB_MODE", "mock").lower()
        self.tns_alias = os.getenv("FIND_MONEY_TNS_ALIAS", "hrdb")
        self._pool = None

    def alerts_for_user(self, user):
        if self.mode == "oracledb":
            sql = """
                SELECT alert_id, case_id, transaction_id, severity, reason, amount, status
                  FROM fin.risk_alerts
                 ORDER BY risk_score DESC, alert_id
                 FETCH FIRST 25 ROWS ONLY
            """
            result = self._run_with_context(user, None, sql, fetch="rows", include_context=True)
            return self._payload(user, "alerts", result["data"], result["request_context"])
        rows = _mock_visible_rows(user, MOCK_ALERTS)
        return self._payload(user, "alerts", rows, _mock_context(user))

    def cases_for_user(self, user):
        if self.mode == "oracledb":
            sql = """
                SELECT case_id, title, assigned_to, risk_score, status, summary
                  FROM fin.cases
                 ORDER BY risk_score DESC, case_id
                 FETCH FIRST 25 ROWS ONLY
            """
            result = self._run_with_context(user, None, sql, fetch="rows", include_context=True)
            return self._payload(user, "cases", result["data"], result["request_context"])
        rows = _mock_visible_rows(user, MOCK_CASES)
        return self._payload(user, "cases", rows, _mock_context(user))

    def ask_agent(self, user, prompt, query_type="sql"):
        query_type = (query_type or "sql").lower()
        if query_type == "graph":
            return self.follow_money_graph(user, _extract_subject(prompt))
        if query_type == "vector":
            return self.vector_search(user, prompt)

        sql, model_payload = self._sql_from_prompt(prompt)
        result = self.run_sql(user, sql)
        result["prompt"] = prompt
        result["llm"] = model_payload
        return result

    def run_sql(self, user, sql):
        sql = (sql or "").strip()
        if not sql:
            raise ValueError("SQL is required.")
        self._validate_sql(sql)

        if self.mode == "oracledb":
            result = self._run_with_context(user, None, sql, fetch="rows", include_context=True)
            return {
                "mode": "oracledb",
                "user": user["username"],
                "sql": sql,
                "rows": result["data"],
                "request_context": result["request_context"],
                "note": "The statement was executed under the end-user security context. Oracle Deep Data Security controls rows, columns, graph traversal results, vector matches, and masks.",
            }

        rows = _mock_sql_result(user, sql)
        return {
            "mode": "mock",
            "user": user["username"],
            "sql": sql,
            "rows": rows,
            "request_context": _mock_context(user),
            "note": "Mock mode simulates policy-filtered results. Use FIND_MONEY_DB_MODE=oracledb for a real Deep Data Security test.",
        }

    def follow_money_graph(self, user, subject):
        subject = subject or "TXN-90017"
        sql = """
            SELECT *
              FROM GRAPH_TABLE(
                     fin.money_graph
                     MATCH (src IS account|customer|vendor|transaction)-[e IS sent_payment|paid_invoice|related_party|beneficial_owner]->{1,3}(dst)
                     WHERE src.id = :subject OR src.name = :subject
                     COLUMNS (
                       vertex_id(src) AS source_id,
                       src.name AS source_name,
                       edge_id(e) AS edge_id,
                       e.amount AS amount,
                       vertex_id(dst) AS target_id,
                       dst.name AS target_name
                     )
                   )
             FETCH FIRST 50 ROWS ONLY
        """
        if self.mode == "oracledb":
            try:
                result = self._run_with_context(
                    user,
                    ["FINAPP_AI_INVESTIGATOR"],
                    sql,
                    fetch="rows",
                    params={"subject": subject},
                    include_context=True,
                )
                used_sql = sql
            except Exception:
                used_sql = """
                    SELECT t.transaction_id AS edge_id,
                           a.account_id AS source_id,
                           a.display_name AS source_name,
                           t.amount,
                           NVL(v.vendor_id, t.to_account_id) AS target_id,
                           NVL(v.vendor_name, t.to_account_id) AS target_name
                      FROM fin.transactions t
                      JOIN fin.accounts a ON a.account_id = t.from_account_id
                      LEFT JOIN fin.vendors v ON v.vendor_id = t.vendor_id
                     WHERE t.transaction_id = :subject
                        OR t.from_account_id = :subject
                        OR t.to_account_id = :subject
                     FETCH FIRST 50 ROWS ONLY
                """
                result = self._run_with_context(
                    user,
                    ["FINAPP_AI_INVESTIGATOR"],
                    used_sql,
                    fetch="rows",
                    params={"subject": subject},
                    include_context=True,
                )
            return {
                "mode": "oracledb",
                "user": user["username"],
                "subject": subject,
                "sql": used_sql,
                "rows": result["data"],
                "request_context": result["request_context"],
                "data_roles": ["FINAPP_AI_INVESTIGATOR"],
                "note": "The AI requested a graph traversal. Oracle evaluated the graph query under the user's DDS context and the app elevation role.",
            }
        return {
            "mode": "mock",
            "user": user["username"],
            "subject": subject,
            "sql": sql,
            "rows": _mock_graph_rows(user),
            "request_context": _mock_context(user, ["FINAPP_AI_INVESTIGATOR"]),
        }

    def vector_search(self, user, text):
        text = text or "invoice splitting through shell vendors"
        sql = """
            SELECT note_id,
                   case_id,
                   title,
                   source_text,
                   risk_tags,
                   VECTOR_DISTANCE(note_embedding, fin.simple_text_embedding(:query_text), COSINE) AS distance
              FROM fin.case_note_embeddings
             ORDER BY distance
             FETCH FIRST 10 ROWS ONLY
        """
        fallback_sql = """
            SELECT note_id,
                   case_id,
                   title,
                   source_text,
                   risk_tags,
                   CASE
                     WHEN LOWER(source_text || ' ' || title || ' ' || risk_tags) LIKE '%' || LOWER(:query_text) || '%' THEN 100
                     ELSE 50
                   END AS similarity
              FROM fin.case_note_embeddings
             WHERE LOWER(source_text || ' ' || title || ' ' || risk_tags) LIKE '%' || LOWER(:query_text) || '%'
                OR LOWER(:query_text) LIKE '%' || LOWER(risk_tags) || '%'
             ORDER BY similarity DESC
             FETCH FIRST 10 ROWS ONLY
        """
        if self.mode == "oracledb":
            try:
                result = self._run_with_context(
                    user,
                    ["FINAPP_AI_INVESTIGATOR"],
                    sql,
                    fetch="rows",
                    params={"query_text": text},
                    include_context=True,
                )
                used_sql = sql
            except Exception:
                result = self._run_with_context(
                    user,
                    ["FINAPP_AI_INVESTIGATOR"],
                    fallback_sql,
                    fetch="rows",
                    params={"query_text": text},
                    include_context=True,
                )
                used_sql = fallback_sql
            return {
                "mode": "oracledb",
                "user": user["username"],
                "query_text": text,
                "sql": used_sql,
                "rows": result["data"],
                "request_context": result["request_context"],
                "data_roles": ["FINAPP_AI_INVESTIGATOR"],
                "note": "Vector evidence search returned only rows and columns visible to the current end user.",
            }
        return {
            "mode": "mock",
            "user": user["username"],
            "query_text": text,
            "sql": sql,
            "rows": _mock_vector_rows(user),
            "request_context": _mock_context(user, ["FINAPP_AI_INVESTIGATOR"]),
        }

    def chat_summary(self, user, prompt, evidence):
        if not prompt:
            prompt = "Summarize the visible evidence and explain what policy protected."
        model_payload = self._call_chat_model(prompt, evidence)
        return {
            "mode": self.mode,
            "user": user["username"],
            "prompt": prompt,
            "summary": model_payload["content"],
            "model": model_payload["model"],
            "endpoint": model_payload["endpoint"],
            "evidence": evidence,
            "note": "Only evidence already returned by Oracle under the end-user context is sent to the chat model.",
        }

    def set_ai_evidence_policy(self, user, enabled):
        if self.mode == "oracledb":
            proc = "sys.find_money_enable_ai_evidence" if enabled else "sys.find_money_disable_ai_evidence"
            self._run_app_query("BEGIN {0}; END;".format(proc), fetch="rowcount")
            payload = self.alerts_for_user(user)
            payload["policy_change"] = "AI evidence role enabled." if enabled else "AI evidence role disabled."
            payload["dba_demo_procedure"] = proc
            return payload
        payload = self.alerts_for_user(user)
        payload["policy_change"] = "Mock mode: AI evidence policy {0}.".format("enabled" if enabled else "disabled")
        return payload

    def audit_events(self, user):
        if self.mode == "oracledb":
            sql = """
                SELECT event_timestamp,
                       dbusername,
                       end_user_name,
                       os_username,
                       userhost,
                       client_program_name,
                       authentication_type,
                       sessionid,
                       action_name,
                       object_schema,
                       object_name,
                       return_code,
                       DBMS_LOB.SUBSTR(sql_text, 220, 1) AS sql_text_preview
                  FROM unified_audit_trail
                 WHERE object_schema = 'FIN'
                   AND action_name IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
                   AND event_timestamp >= SYSTIMESTAMP - INTERVAL '10' MINUTE
                 ORDER BY event_timestamp DESC
                 FETCH FIRST 40 ROWS ONLY
            """
            return {
                "mode": "oracledb",
                "window": "last 10 minutes",
                "events": self._run_app_query(sql, fetch="rows"),
                "note": "END_USER_NAME identifies the DDS end user even though the app uses pooled database connections.",
            }
        return {"mode": "mock", "events": [], "note": "Audit events are available in oracledb mode."}

    def debug_tokens_for_user(self, user):
        if self.mode != "oracledb":
            return {"mode": self.mode, "message": "Database token diagnostics are available in oracledb mode."}
        db_token = self._database_access_token_for_user(user["access_token"])
        return {"mode": "oracledb", "database_access_token": public_claims(decode_jwt_without_validation(db_token))}

    def debug_context_for_user(self, user):
        if self.mode != "oracledb":
            return {"mode": self.mode, "message": "Database context diagnostics are available in oracledb mode."}
        identity_sql = """
            SELECT ORA_END_USER_CONTEXT.username AS username,
                   SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
                   SYS_CONTEXT('USERENV','ENTERPRISE_IDENTITY') AS enterprise_identity,
                   SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method,
                   SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user
              FROM dual
        """
        roles_sql = "SELECT role_name FROM v$end_user_data_role ORDER BY role_name"
        return {
            "mode": "oracledb",
            "identity": self._run_with_context(user, None, identity_sql, fetch="one"),
            "active_data_roles": self._run_with_context(user, None, roles_sql, fetch="rows"),
        }

    def preflight(self, user):
        checks = []

        def add(name, status, detail, evidence=None):
            check = {"name": name, "status": status, "detail": detail}
            if evidence is not None:
                check["evidence"] = evidence
            checks.append(check)

        def run(name, fn):
            try:
                detail, evidence = fn()
                add(name, "pass", detail, evidence)
            except Exception as exc:
                add(name, "fail", str(exc))

        required_env = [
            "FIND_MONEY_TOKEN_URI",
            "FIND_MONEY_APP_CLIENT_ID",
            "FIND_MONEY_APP_CLIENT_SECRET",
            "FIND_MONEY_DB_SCOPE",
        ]
        missing_env = [name for name in required_env if not os.getenv(name)]
        if missing_env:
            add("Required environment", "fail", "Missing {0}.".format(", ".join(missing_env)))
        else:
            add("Required environment", "pass", "Required Entra and database token settings are present.")

        if self.mode != "oracledb":
            add("Database mode", "warn", "FIND_MONEY_DB_MODE is {0}; database checks are skipped.".format(self.mode))
            return {"mode": self.mode, "checks": checks, "summary": _preflight_summary(checks)}

        run("Python driver", self._driver_check)
        run("Application token", self._app_token_check)
        run("End-user database token", lambda: self._user_token_check(user))
        run("Pooled app connection", self._app_connection_check)
        run("End-user security context", lambda: self._context_check(user))
        run("Token role mapping", lambda: self._role_check(user))
        run("FIN schema visibility", lambda: self._fin_schema_check(user))
        run("Graph query", lambda: self._graph_check(user))
        run("Vector query", lambda: self._vector_check(user))
        run("Audit visibility", self._audit_check)
        return {"mode": "oracledb", "checks": checks, "summary": _preflight_summary(checks)}

    def _payload(self, user, kind, rows, request_context):
        return {
            "mode": self.mode,
            "user": user["username"],
            "kind": kind,
            "rows": rows,
            "request_context": request_context,
            "note": "Returned data reflects the current end-user Deep Data Security context.",
        }

    def _sql_from_prompt(self, prompt):
        generated = self._llm_sql(prompt)
        if generated:
            return generated, {"source": "oci_genai", "model": os.getenv("FIND_MONEY_OCI_GENAI_MODEL")}
        lower = (prompt or "").lower()
        if "tax" in lower or "account number" in lower or "pii" in lower:
            sql = "SELECT customer_id, full_name, tax_id, home_branch, risk_rating FROM fin.customers FETCH FIRST 25 ROWS ONLY"
        elif "transaction" in lower or "wire" in lower or "payment" in lower:
            sql = "SELECT transaction_id, from_account_id, to_account_id, amount, currency_code, memo, risk_score FROM fin.transactions ORDER BY amount DESC FETCH FIRST 25 ROWS ONLY"
        elif "owner" in lower or "beneficial" in lower:
            sql = "SELECT owner_id, owner_name, tax_id, related_customer_id, risk_rating FROM fin.beneficial_owners FETCH FIRST 25 ROWS ONLY"
        elif "note" in lower or "case" in lower:
            sql = "SELECT case_id, title, assigned_to, risk_score, summary FROM fin.cases ORDER BY risk_score DESC FETCH FIRST 25 ROWS ONLY"
        else:
            sql = "SELECT * FROM fin.risk_alerts ORDER BY risk_score DESC FETCH FIRST 25 ROWS ONLY"
        return sql, {"source": "local_template", "reason": "OCI GenAI SQL generation was not configured or did not return SQL."}

    def _llm_sql(self, prompt):
        if not os.getenv("FIND_MONEY_OCI_GENAI_API_KEY"):
            return None
        instruction = (
            "Generate one Oracle SQL statement for the FIN schema. Return only SQL. "
            "The database will enforce Deep Data Security; do not add app-side filters. "
            "Available tables include FIN.CUSTOMERS, FIN.ACCOUNTS, FIN.TRANSACTIONS, "
            "FIN.RISK_ALERTS, FIN.CASES, FIN.BENEFICIAL_OWNERS, FIN.CASE_NOTE_EMBEDDINGS."
        )
        payload = self._openai_chat_payload(instruction, prompt)
        content = payload.get("content", "").strip()
        content = re.sub(r"^```(?:sql)?|```$", "", content, flags=re.IGNORECASE).strip()
        return content or None

    def _call_chat_model(self, prompt, evidence):
        if not os.getenv("FIND_MONEY_OCI_GENAI_API_KEY"):
            return {
                "model": "mock",
                "endpoint": "mock",
                "content": _mock_summary(prompt, evidence),
            }
        instruction = (
            "You are a financial investigation assistant. Summarize only the evidence provided. "
            "Call out when data appears masked, missing, or policy-limited."
        )
        user_message = "{0}\n\nVisible evidence JSON:\n{1}".format(prompt, json.dumps(evidence, default=str)[:12000])
        return self._openai_chat_payload(instruction, user_message)

    def _openai_chat_payload(self, system_message, user_message):
        base_url = os.getenv(
            "FIND_MONEY_OCI_GENAI_BASE_URL",
            "https://inference.generativeai.us-chicago-1.oci.oraclecloud.com/openai/v1",
        ).rstrip("/")
        model = os.getenv("FIND_MONEY_OCI_GENAI_MODEL", "cohere.command-r-plus-08-2024")
        compartment_id = os.getenv("FIND_MONEY_OCI_COMPARTMENT_ID", "")
        body = {
            "model": model,
            "messages": [
                {"role": "system", "content": system_message},
                {"role": "user", "content": user_message},
            ],
            "temperature": 0,
        }
        if compartment_id:
            body["extra_body"] = {"compartmentId": compartment_id}
        request = Request(
            "{0}/chat/completions".format(base_url),
            data=json.dumps(body).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer {0}".format(os.getenv("FIND_MONEY_OCI_GENAI_API_KEY")),
            },
        )
        try:
            with urlopen(request, timeout=60) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            message = exc.read().decode("utf-8", "replace")
            raise RuntimeError("OCI GenAI chat request failed: HTTP {0} {1}".format(exc.code, message))
        content = (((payload.get("choices") or [{}])[0].get("message") or {}).get("content") or "").strip()
        return {"model": model, "endpoint": base_url, "content": content, "raw": payload}

    def _validate_sql(self, sql):
        if ";" in sql.rstrip(";"):
            raise ValueError("One SQL statement at a time.")
        verb = sql.lstrip().split(None, 1)[0].lower()
        allowed = {"select", "with"}
        if os.getenv("FIND_MONEY_ALLOW_DML", "0") == "1":
            allowed.update({"insert", "update", "delete", "merge"})
        if verb not in allowed:
            raise ValueError("This demo endpoint allows {0}. Set FIND_MONEY_ALLOW_DML=1 for DML tests.".format(", ".join(sorted(allowed))))

    def _driver_check(self):
        import oracledb
        import oracledb.plugins.end_user_sec_provider  # noqa: F401

        if not hasattr(oracledb, "create_end_user_security_context"):
            raise RuntimeError("python-oracledb does not expose create_end_user_security_context.")
        return "python-oracledb exposes Deep Data Security APIs.", {"oracledb_version": getattr(oracledb, "__version__", "unknown")}

    def _app_token_check(self):
        token = self._application_access_token()
        claims = public_claims(decode_jwt_without_validation(token))
        return "Application database token acquired.", {"aud": claims.get("aud"), "appid": claims.get("appid"), "roles": claims.get("roles", [])}

    def _user_token_check(self, user):
        token = self._database_access_token_for_user(user["access_token"])
        claims = public_claims(decode_jwt_without_validation(token))
        return "On-behalf-of database token acquired for {0}.".format(user["username"]), {"aud": claims.get("aud"), "upn": claims.get("upn"), "roles": claims.get("roles", [])}

    def _app_connection_check(self):
        row = self._run_app_query(
            "SELECT SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity, SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user FROM dual",
            fetch="one",
        )
        return "Application token can acquire a pooled database connection.", row

    def _context_check(self, user):
        row = self._run_with_context(user, None, "SELECT ORA_END_USER_CONTEXT.username AS username FROM dual", fetch="one")
        return "Application can create and attach an end-user security context.", row

    def _role_check(self, user):
        roles = self._run_with_context(user, None, "SELECT role_name FROM v$end_user_data_role ORDER BY role_name", fetch="rows")
        return "Database mapped token roles to active DDS data roles.", {"active_data_roles": [row.get("ROLE_NAME") for row in roles]}

    def _fin_schema_check(self, user):
        row = self._run_with_context(user, None, "SELECT COUNT(*) AS visible_alerts FROM fin.risk_alerts", fetch="one")
        return "FIN schema data is visible through DDS policy.", row

    def _graph_check(self, user):
        row = self._run_with_context(user, ["FINAPP_AI_INVESTIGATOR"], "SELECT COUNT(*) AS visible_transactions FROM fin.transactions", fetch="one")
        return "Graph source data can be queried under app elevation.", row

    def _vector_check(self, user):
        row = self._run_with_context(user, ["FINAPP_AI_INVESTIGATOR"], "SELECT COUNT(*) AS visible_notes FROM fin.case_note_embeddings", fetch="one")
        return "Vector evidence table is protected by DDS policy.", row

    def _audit_check(self):
        row = self._run_app_query("SELECT COUNT(*) AS sample_rows FROM unified_audit_trail WHERE ROWNUM <= 1", fetch="one")
        return "Application can read Unified Audit Trail through AUDIT_VIEWER.", row

    def _pool_oracle(self):
        if self._pool is not None:
            return self._pool
        try:
            import oracledb
            import oracledb.plugins.end_user_sec_provider  # noqa: F401
        except ImportError as exc:
            raise RuntimeError("FIND_MONEY_DB_MODE=oracledb requires python-oracledb with Deep Data Security support.") from exc
        missing_env = [
            name for name in (
                "FIND_MONEY_DB_SCOPE",
                "FIND_MONEY_TOKEN_URI",
                "FIND_MONEY_APP_CLIENT_ID",
                "FIND_MONEY_APP_CLIENT_SECRET",
            )
            if not os.getenv(name)
        ]
        if missing_env:
            raise RuntimeError("Missing Find the Money database token settings: {0}".format(", ".join(missing_env)))
        pool_kwargs = {
            "dsn": self.tns_alias,
            "min": 1,
            "max": 4,
            "increment": 1,
            "access_token": self._application_access_token,
        }
        config_dir = os.getenv("FIND_MONEY_CONFIG_DIR") or os.getenv("TNS_ADMIN")
        wallet_location = os.getenv("FIND_MONEY_WALLET_LOCATION")
        if not wallet_location:
            default_wallet = Path(__file__).resolve().parent.parent / "python-wallet"
            if (default_wallet / "ewallet.pem").is_file():
                wallet_location = str(default_wallet)
        if config_dir:
            pool_kwargs["config_dir"] = config_dir
        if wallet_location:
            pool_kwargs["wallet_location"] = wallet_location
        if os.getenv("FIND_MONEY_WALLET_PASSWORD"):
            pool_kwargs["wallet_password"] = os.getenv("FIND_MONEY_WALLET_PASSWORD")
        self._pool = oracledb.create_pool(**pool_kwargs)
        return self._pool

    def _application_access_token(self, *args):
        body = urlencode(
            {
                "grant_type": "client_credentials",
                "client_id": os.getenv("FIND_MONEY_APP_CLIENT_ID"),
                "client_secret": os.getenv("FIND_MONEY_APP_CLIENT_SECRET"),
                "scope": os.getenv("FIND_MONEY_APP_DB_SCOPE", os.getenv("FIND_MONEY_DB_SCOPE")),
            }
        ).encode("utf-8")
        return self._request_access_token(body, "application database access token")

    def _database_access_token_for_user(self, end_user_token):
        body = urlencode(
            {
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "client_id": os.getenv("FIND_MONEY_APP_CLIENT_ID"),
                "client_secret": os.getenv("FIND_MONEY_APP_CLIENT_SECRET"),
                "scope": os.getenv("FIND_MONEY_DB_SCOPE"),
                "assertion": end_user_token,
                "requested_token_use": "on_behalf_of",
            }
        ).encode("utf-8")
        return self._request_access_token(body, "on-behalf-of database access token")

    def _request_access_token(self, body, token_name):
        request = Request(os.getenv("FIND_MONEY_TOKEN_URI"), data=body, headers={"Content-Type": "application/x-www-form-urlencoded"})
        try:
            with urlopen(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            message = exc.read().decode("utf-8", "replace")
            raise RuntimeError("Could not get {0}: HTTP {1} {2}".format(token_name, exc.code, message))
        token = payload.get("access_token")
        if not token:
            raise RuntimeError("Entra ID did not return an {0}.".format(token_name))
        return token

    def _run_with_context(self, user, data_roles, sql, fetch, params=None, include_context=False):
        import oracledb

        connection = self._pool_oracle().acquire()
        try:
            context_kwargs = {
                "end_user_identity": self._database_access_token_for_user(user["access_token"]),
                "database_access_token": self._application_access_token(),
            }
            if data_roles:
                context_kwargs["data_roles"] = data_roles
            context = oracledb.create_end_user_security_context(**context_kwargs)
            connection.set_end_user_security_context(context)
            cursor = connection.cursor()
            try:
                cursor.execute(sql, params or {})
                if fetch == "rowcount":
                    row_count = cursor.rowcount
                    connection.commit()
                    return row_count
                columns = [d[0] for d in cursor.description]
                if fetch == "one":
                    row = cursor.fetchone()
                    data = _row_to_dict(columns, row) if row else None
                    return {"data": data, "request_context": self._current_request_context(cursor)} if include_context else data
                data = [_row_to_dict(columns, row) for row in cursor.fetchall()]
                return {"data": data, "request_context": self._current_request_context(cursor)} if include_context else data
            finally:
                cursor.close()
                connection.clear_end_user_security_context()
        finally:
            self._pool_oracle().release(connection)

    def _run_app_query(self, sql, fetch, params=None):
        connection = self._pool_oracle().acquire()
        try:
            cursor = connection.cursor()
            try:
                cursor.execute(sql, params or {})
                if fetch == "rowcount":
                    row_count = cursor.rowcount
                    connection.commit()
                    return row_count
                columns = [d[0] for d in cursor.description]
                if fetch == "one":
                    row = cursor.fetchone()
                    return _row_to_dict(columns, row) if row else None
                return [_row_to_dict(columns, row) for row in cursor.fetchall()]
            finally:
                cursor.close()
        finally:
            self._pool_oracle().release(connection)

    def _current_request_context(self, cursor):
        cursor.execute(
            """
            SELECT SYS_CONTEXT('USERENV','SESSIONID') AS session_id,
                   SYS_CONTEXT('USERENV','SERVICE_NAME') AS service_name,
                   ORA_END_USER_CONTEXT.username AS end_user_name,
                   SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
                   SYS_CONTEXT('USERENV','ENTERPRISE_IDENTITY') AS enterprise_identity,
                   SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method,
                   SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user
              FROM dual
            """
        )
        columns = [d[0] for d in cursor.description]
        identity = _row_to_dict(columns, cursor.fetchone())
        cursor.execute("SELECT role_name FROM v$end_user_data_role ORDER BY role_name")
        columns = [d[0] for d in cursor.description]
        roles = [_row_to_dict(columns, row) for row in cursor.fetchall()]
        return {"pooled_connection": {"session_id": identity.get("SESSION_ID"), "service_name": identity.get("SERVICE_NAME")}, "identity": identity, "active_data_roles": roles}


def _mock_visible_rows(user, rows):
    roles = set(user.get("roles") or [])
    username = user.get("username", "").lower()
    if "FINAPP_AUDITORS" in roles or "FINAPP_SENIOR_INVESTIGATORS" in roles or "marcus" in username:
        return rows
    if "FINAPP_INVESTIGATORS" in roles or "priya" in username:
        return rows[:1]
    return [{key: ("MASKED" if key in ("amount", "summary", "assigned_to") else value) for key, value in rows[0].items()}]


def _mock_sql_result(user, sql):
    lower = sql.lower()
    if "beneficial" in lower:
        rows = [{"OWNER_ID": "OWN-77", "OWNER_NAME": "MASKED", "TAX_ID": "MASKED", "RISK_RATING": "High"}]
    elif "customer" in lower:
        rows = [{"CUSTOMER_ID": "C-1007", "FULL_NAME": "Sophia Chen", "TAX_ID": "MASKED", "HOME_BRANCH": "Chicago", "RISK_RATING": "High"}]
    elif "transaction" in lower:
        rows = [{"TRANSACTION_ID": "TXN-90017", "FROM_ACCOUNT_ID": "A-8821", "TO_ACCOUNT_ID": "MASKED", "AMOUNT": "MASKED", "MEMO": "Vendor services"}]
    elif "case" in lower:
        rows = _mock_visible_rows(user, MOCK_CASES)
    else:
        rows = _mock_visible_rows(user, MOCK_ALERTS)
    return rows


def _mock_graph_rows(user):
    rows = [
        {"SOURCE_ID": "A-8821", "SOURCE_NAME": "Sophia operating account", "EDGE_ID": "TXN-90017", "AMOUNT": "MASKED", "TARGET_ID": "V-440", "TARGET_NAME": "Northstar Supply"},
        {"SOURCE_ID": "V-440", "SOURCE_NAME": "Northstar Supply", "EDGE_ID": "OWN-77", "AMOUNT": None, "TARGET_ID": "C-2041", "TARGET_NAME": "MASKED related party"},
    ]
    if "FINAPP_SENIOR_INVESTIGATORS" in set(user.get("roles") or []) or "marcus" in user.get("username", "").lower():
        rows[0]["AMOUNT"] = 248500
        rows[1]["TARGET_NAME"] = "Keystone Holdings"
    return rows


def _mock_vector_rows(user):
    rows = [
        {"NOTE_ID": "NOTE-22", "CASE_ID": "CASE-1042", "TITLE": "Shared owner", "SOURCE_TEXT": "MASKED", "RISK_TAGS": "related-party, passthrough", "DISTANCE": 0.08},
        {"NOTE_ID": "NOTE-31", "CASE_ID": "CASE-1088", "TITLE": "Invoice split pattern", "SOURCE_TEXT": "Three payments under approval threshold.", "RISK_TAGS": "invoice-splitting", "DISTANCE": 0.16},
    ]
    if "priya" in user.get("username", "").lower() or "marcus" in user.get("username", "").lower():
        rows[0]["SOURCE_TEXT"] = "Vendor shares beneficial owner with the final receiving account."
    return rows


def _mock_context(user, data_roles=None):
    return {
        "pooled_connection": "mock",
        "identity": {"END_USER_NAME": user.get("username"), "CURRENT_USER": "FIND_MONEY_APP_USER"},
        "active_data_roles": [{"ROLE_NAME": role} for role in (data_roles or user.get("roles") or [])],
    }


def _extract_subject(prompt):
    match = re.search(r"(TXN-\d+|CASE-\d+|A-\d+|V-\d+)", prompt or "", re.IGNORECASE)
    return match.group(1).upper() if match else "TXN-90017"


def _mock_summary(prompt, evidence):
    rows = evidence.get("rows") if isinstance(evidence, dict) else None
    count = len(rows or [])
    return "Visible evidence contains {0} row(s). Masked or missing fields indicate database policy limited what the current user could see. Prompt: {1}".format(count, prompt)


def _row_to_dict(columns, row):
    result = {}
    for index, column in enumerate(columns):
        value = row[index]
        if hasattr(value, "read"):
            value = value.read()
        if isinstance(value, bytes):
            value = value.decode("utf-8", "replace")
        elif hasattr(value, "isoformat"):
            value = value.isoformat()
        elif isinstance(value, Decimal):
            value = int(value) if value == value.to_integral_value() else float(value)
        result[column] = value
    return result


def _preflight_summary(checks):
    counts = {"pass": 0, "warn": 0, "fail": 0}
    for check in checks:
        status = check.get("status")
        if status in counts:
            counts[status] += 1
    return counts
