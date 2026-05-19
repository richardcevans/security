const userBox = document.querySelector("#userBox");
const queueRows = document.querySelector("#queueRows");
const raw = document.querySelector("#raw");
const modeBanner = document.querySelector("#modeBanner");
const auditRows = document.querySelector("#auditRows");
const promptInput = document.querySelector("#promptInput");
const sqlInput = document.querySelector("#sqlInput");
const graphCanvas = document.querySelector("#graphCanvas");
const graphMeta = document.querySelector("#graphMeta");

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
  clearGraph("Run Follow Graph to visualize the money trail.");
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function loadCases() {
  const payload = await getJson("/api/cases");
  lastEvidence = payload;
  renderQueue(payload.rows || [], "cases");
  clearGraph("Run Follow Graph to visualize a selected case or transaction.");
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function askSql() {
  const payload = await postJson("/api/query", { prompt: promptInput.value, query_type: "sql" });
  lastEvidence = payload;
  if (payload.sql) {
    sqlInput.value = payload.sql;
  }
  clearGraph("SQL evidence loaded. Run Follow Graph for relationship visualization.");
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function runSql() {
  const payload = await postJson("/api/query/sql", { sql: sqlInput.value });
  lastEvidence = payload;
  clearGraph("SQL evidence loaded. Run Follow Graph for relationship visualization.");
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function followGraph() {
  const payload = await postJson("/api/query/graph", { subject: promptInput.value });
  lastEvidence = payload;
  if (payload.sql) {
    sqlInput.value = payload.sql;
  }
  renderGraph(payload);
  showPayload(payload);
  refreshAuditEventsQuietly();
}

async function vectorSearch() {
  const payload = await postJson("/api/query/vector", { text: promptInput.value });
  lastEvidence = payload;
  if (payload.sql) {
    sqlInput.value = payload.sql;
  }
  clearGraph("Vector evidence loaded. Run Follow Graph for relationship visualization.");
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
  clearGraph("AI evidence policy changed. Run Follow Graph to refresh graph evidence.");
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

function clearGraph(message) {
  graphMeta.textContent = "No graph rendered";
  graphCanvas.innerHTML = `<div class="empty-graph">${escapeHtml(message)}</div>`;
}

function renderGraph(payload) {
  const rows = payload.rows || [];
  if (!rows.length) {
    graphMeta.textContent = "0 paths";
    graphCanvas.innerHTML = '<div class="empty-graph">No visible graph paths for the current user.</div>';
    return;
  }

  const { nodes, edges } = graphModel(rows);
  const width = Math.max(920, nodes.length * 210);
  const height = 360;
  const positions = graphPositions(nodes, width, height);
  const edgeMarkup = edges.map((edge, index) => renderGraphEdge(edge, positions, index)).join("");
  const nodeMarkup = nodes.map((node) => renderGraphNode(node, positions[node.id])).join("");

  graphMeta.textContent = `${nodes.length} nodes / ${edges.length} paths`;
  graphCanvas.innerHTML = `
    <svg class="money-graph" viewBox="0 0 ${width} ${height}" role="img" aria-label="Money flow graph">
      <defs>
        <marker id="arrowHead" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z"></path>
        </marker>
      </defs>
      <g class="graph-edges">${edgeMarkup}</g>
      <g class="graph-nodes">${nodeMarkup}</g>
    </svg>
  `;
}

function graphModel(rows) {
  const nodeMap = new Map();
  const edges = [];
  rows.forEach((row, index) => {
    const sourceId = String(valueFor(row, "source_id") || `source-${index}`);
    const targetId = String(valueFor(row, "target_id") || `target-${index}`);
    const sourceName = String(valueFor(row, "source_name") || sourceId);
    const targetName = String(valueFor(row, "target_name") || targetId);
    if (!nodeMap.has(sourceId)) {
      nodeMap.set(sourceId, {
        id: sourceId,
        label: sourceName,
        kind: nodeKind(sourceId, sourceName),
        masked: isMasked(sourceId) || isMasked(sourceName)
      });
    }
    if (!nodeMap.has(targetId)) {
      nodeMap.set(targetId, {
        id: targetId,
        label: targetName,
        kind: nodeKind(targetId, targetName),
        masked: isMasked(targetId) || isMasked(targetName)
      });
    }
    edges.push({
      id: String(valueFor(row, "edge_id") || `edge-${index}`),
      source: sourceId,
      target: targetId,
      amount: valueFor(row, "amount"),
      masked: isMasked(valueFor(row, "amount")) || isMasked(sourceName) || isMasked(targetName)
    });
  });
  return { nodes: Array.from(nodeMap.values()), edges };
}

function graphPositions(nodes, width, height) {
  const positions = {};
  const centerY = height / 2;
  const step = nodes.length > 1 ? (width - 180) / (nodes.length - 1) : 0;
  nodes.forEach((node, index) => {
    const wave = index % 2 === 0 ? -46 : 46;
    positions[node.id] = {
      x: nodes.length === 1 ? width / 2 : 90 + index * step,
      y: centerY + wave
    };
  });
  return positions;
}

function renderGraphEdge(edge, positions, index) {
  const source = positions[edge.source];
  const target = positions[edge.target];
  if (!source || !target) {
    return "";
  }
  const midX = (source.x + target.x) / 2;
  const midY = (source.y + target.y) / 2 - 28 - (index % 2) * 18;
  const amount = edge.amount == null || edge.amount === "" ? "relationship" : formatMoney(edge.amount);
  const edgeClass = edge.masked ? "graph-edge masked" : "graph-edge";
  return `
    <path class="${edgeClass}" d="M ${source.x + 68} ${source.y} C ${midX} ${midY}, ${midX} ${midY}, ${target.x - 68} ${target.y}" marker-end="url(#arrowHead)"></path>
    <g class="edge-label" transform="translate(${midX - 62}, ${midY - 18})">
      <rect width="124" height="28" rx="5"></rect>
      <text x="62" y="18">${escapeSvg(amount)}</text>
    </g>
  `;
}

function renderGraphNode(node, position) {
  const labelLines = wrapLabel(node.label, 20).slice(0, 2);
  const nodeClass = `graph-node ${node.masked ? "masked" : ""}`;
  return `
    <g class="${nodeClass}" transform="translate(${position.x - 72}, ${position.y - 42})">
      <rect width="144" height="84" rx="7"></rect>
      <text class="node-kind" x="72" y="22">${escapeSvg(node.kind)}</text>
      ${labelLines.map((line, index) => `<text class="node-label" x="72" y="${48 + index * 17}">${escapeSvg(line)}</text>`).join("")}
    </g>
  `;
}

function nodeKind(id, label) {
  const value = `${id} ${label}`.toLowerCase();
  if (value.startsWith("a-") || value.includes("account")) return "Account";
  if (value.startsWith("v-") || value.includes("vendor") || value.includes("supply")) return "Vendor";
  if (value.startsWith("c-") || value.includes("customer") || value.includes("party")) return "Customer";
  if (value.startsWith("txn-")) return "Transaction";
  if (value.startsWith("own-") || value.includes("owner")) return "Owner";
  return "Entity";
}

function isMasked(value) {
  return String(value ?? "").toLowerCase().includes("masked");
}

function wrapLabel(value, size) {
  const words = String(value || "").split(/\s+/).filter(Boolean);
  const lines = [];
  let current = "";
  words.forEach((word) => {
    const next = current ? `${current} ${word}` : word;
    if (next.length > size && current) {
      lines.push(current);
      current = word;
    } else {
      current = next;
    }
  });
  if (current) {
    lines.push(current);
  }
  return lines.length ? lines : [String(value || "")];
}

function formatMoney(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return String(value);
  }
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0
  }).format(numeric);
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

function escapeSvg(value) {
  return escapeHtml(value);
}

refreshConfig().then(refreshUser).catch((error) => {
  raw.textContent = String(error.stack || error);
});
