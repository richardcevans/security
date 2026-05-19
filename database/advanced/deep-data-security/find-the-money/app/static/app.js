const userBox = document.querySelector("#userBox");
const queueRows = document.querySelector("#queueRows");
const raw = document.querySelector("#raw");
const modeBanner = document.querySelector("#modeBanner");
const auditRows = document.querySelector("#auditRows");
const promptInput = document.querySelector("#promptInput");
const sqlInput = document.querySelector("#sqlInput");

document.querySelector("#alertsButton").addEventListener("click", loadAlerts);
document.querySelector("#casesButton").addEventListener("click", loadCases);
document.querySelector("#askSqlButton").addEventListener("click", askSql);
document.querySelector("#graphButton").addEventListener("click", followGraph);
document.querySelector("#vectorButton").addEventListener("click", vectorSearch);
document.querySelector("#chatButton").addEventListener("click", summarizeEvidence);
document.querySelector("#runSqlButton").addEventListener("click", runSql);
document.querySelector("#auditButton").addEventListener("click", () => loadAuditEvents());
document.querySelector("#enableAiButton").addEventListener("click", () => toggleAiEvidence(true));
document.querySelector("#disableAiButton").addEventListener("click", () => toggleAiEvidence(false));

let lastEvidence = null;

async function refreshConfig() {
  const response = await fetch("/config");
  const config = await response.json();
  const mode = config.db_mode || "mock";
  modeBanner.className = `mode-banner ${mode === "oracledb" ? "real" : "mock"}`;
  modeBanner.innerHTML = mode === "oracledb"
    ? "<strong>Oracle mode:</strong> AI-generated database work runs through the pooled app identity with the signed-in end-user security context."
    : "<strong>Mock mode:</strong> policy outcomes are simulated. Run with <code>FIND_MONEY_DB_MODE=oracledb ./run.sh</code> to prove Deep Data Security.";
}

async function refreshUser() {
  const response = await fetch("/api/me");
  const payload = await response.json();
  const user = payload.user;
  if (!user) {
    userBox.innerHTML = "<strong>Not signed in</strong><br />Use Entra ID or a demo user";
    raw.textContent = "Sign in before running investigations.";
    return null;
  }
  userBox.innerHTML = `<strong>${escapeHtml(user.name)}</strong><br />${escapeHtml(user.username)}<br />${escapeHtml((user.roles || []).join(", "))}`;
  raw.textContent = JSON.stringify({
    demo: "AI agent under database policy",
    user,
    enforcement: [
      "The app can ask the LLM to generate broad SQL.",
      "Generated SQL, graph traversal, and vector search execute under Oracle end-user security context.",
      "Deep Data Security, not prompt text, controls returned rows and columns."
    ]
  }, null, 2);
  return user;
}

async function loadAlerts() {
  const payload = await getJson("/api/alerts");
  lastEvidence = payload;
  renderQueue(payload.rows || [], "alerts");
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function loadCases() {
  const payload = await getJson("/api/cases");
  lastEvidence = payload;
  renderQueue(payload.rows || [], "cases");
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function askSql() {
  const payload = await postJson("/api/query", { prompt: promptInput.value, query_type: "sql" });
  lastEvidence = payload;
  if (payload.sql) {
    sqlInput.value = payload.sql;
  }
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function runSql() {
  const payload = await postJson("/api/query/sql", { sql: sqlInput.value });
  lastEvidence = payload;
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function followGraph() {
  const payload = await postJson("/api/query/graph", { subject: promptInput.value });
  lastEvidence = payload;
  if (payload.sql) {
    sqlInput.value = payload.sql;
  }
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function vectorSearch() {
  const payload = await postJson("/api/query/vector", { text: promptInput.value });
  lastEvidence = payload;
  if (payload.sql) {
    sqlInput.value = payload.sql;
  }
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function summarizeEvidence() {
  const payload = await postJson("/api/llm/chat", {
    prompt: promptInput.value,
    evidence: lastEvidence || {}
  });
  showPayload(payload);
}

async function toggleAiEvidence(enabled) {
  const payload = await postJson(enabled ? "/api/policy/enable-ai-evidence" : "/api/policy/disable-ai-evidence", {});
  lastEvidence = payload;
  renderQueue(payload.rows || [], "alerts");
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function loadAuditEvents(updateRaw = true) {
  const payload = await getJson("/api/audit/events");
  renderAuditEvents(payload.events || []);
  if (updateRaw) {
    showPayload(payload);
  }
}

function refreshAuditEventsQuietly() {
  loadAuditEvents(false).catch((error) => {
    auditRows.innerHTML = `<tr><td colspan="7">${escapeHtml(error.message || error)}</td></tr>`;
  });
}

async function getJson(url) {
  const response = await fetch(url);
  const payload = await response.json();
  if (!response.ok) {
    showPayload(payload);
    throw new Error(payload.error || "Request failed");
  }
  return payload;
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  const payload = await response.json();
  if (!response.ok) {
    showPayload(payload);
    throw new Error(payload.error || "Request failed");
  }
  return payload;
}

function renderQueue(rows, kind) {
  if (!rows.length) {
    queueRows.innerHTML = '<tr><td colspan="5">No visible rows.</td></tr>';
    return;
  }
  queueRows.innerHTML = rows.map((row) => {
    const id = valueFor(row, kind === "cases" ? "case_id" : "alert_id");
    const caseId = valueFor(row, "case_id");
    const severity = valueFor(row, "severity") || valueFor(row, "status");
    const reason = valueFor(row, "reason") || valueFor(row, "summary") || valueFor(row, "title");
    const amount = valueFor(row, "amount") || valueFor(row, "risk_score");
    return `
      <tr>
        <td>${escapeHtml(id)}</td>
        <td>${escapeHtml(caseId)}</td>
        <td>${escapeHtml(severity)}</td>
        <td>${escapeHtml(reason)}</td>
        <td>${escapeHtml(amount)}</td>
      </tr>
    `;
  }).join("");
}

function renderAuditEvents(events) {
  if (!events.length) {
    auditRows.innerHTML = '<tr><td colspan="7">No audit events in the current window.</td></tr>';
    return;
  }
  auditRows.innerHTML = events.map((event) => `
    <tr>
      <td>${escapeHtml(valueFor(event, "event_timestamp"))}</td>
      <td>${escapeHtml(valueFor(event, "action_name"))}</td>
      <td>${escapeHtml(valueFor(event, "end_user_name"))}</td>
      <td>${escapeHtml(valueFor(event, "dbusername"))}</td>
      <td>${escapeHtml(`${valueFor(event, "object_schema")}.${valueFor(event, "object_name")}`)}</td>
      <td><code>${escapeHtml(valueFor(event, "sql_text_preview"))}</code></td>
      <td>${escapeHtml(valueFor(event, "return_code"))}</td>
    </tr>
  `).join("");
}

function showPayload(payload) {
  raw.textContent = JSON.stringify(payload, null, 2);
}

function valueFor(row, key) {
  const upperKey = key.toUpperCase();
  return row[key] ?? row[upperKey] ?? "";
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

refreshConfig().then(refreshUser).catch((error) => {
  raw.textContent = String(error.stack || error);
});
