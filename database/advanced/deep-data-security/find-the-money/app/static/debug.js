const userBox = document.querySelector("#userBox");
const tokensButton = document.querySelector("#tokensButton");
const contextButton = document.querySelector("#contextButton");
const requestContextButton = document.querySelector("#requestContextButton");
const preflightButton = document.querySelector("#preflightButton");
const tokenDebug = document.querySelector("#tokenDebug");
const contextDebug = document.querySelector("#contextDebug");
const requestContext = document.querySelector("#requestContext");
const preflightSummary = document.querySelector("#preflightSummary");
const preflightResults = document.querySelector("#preflightResults");
const tokenFlow = document.querySelector("#tokenFlow");

tokensButton.addEventListener("click", loadTokenDebug);
contextButton.addEventListener("click", loadContextDebug);
requestContextButton.addEventListener("click", loadRequestContext);
preflightButton.addEventListener("click", loadPreflight);

async function refreshUser() {
  const response = await fetch("/api/me");
  const payload = await response.json();
  const user = payload.user;
  if (!user) {
    userBox.innerHTML = "<strong>Not signed in</strong><br />Return to the app and sign in.";
    tokenDebug.textContent = "Sign in to view token claims.";
    contextDebug.textContent = "Sign in to view database context.";
    preflightResults.textContent = "Sign in to run preflight checks.";
    tokenFlow.textContent = "Sign in to view the token flow.";
    return null;
  }
  userBox.innerHTML = `<strong>${escapeHtml(user.name)}</strong><br />${escapeHtml(user.username)}<br />${escapeHtml((user.roles || []).join(", "))}`;
  preflightSummary.textContent = "";
  preflightResults.textContent = "Click Run Preflight to check the demo setup.";
  return user;
}

async function loadTokenDebug() {
  tokenDebug.textContent = "Loading token claims...";
  try {
    const payload = await getJson("/api/debug/tokens", tokenDebug);
    renderTokenFlow(payload);
    tokenDebug.textContent = JSON.stringify(payload, null, 2);
  } catch (error) {
    if (!tokenDebug.textContent) {
      tokenDebug.textContent = String(error.stack || error);
    }
  }
}

async function loadContextDebug() {
  contextDebug.textContent = "Loading database context...";
  try {
    const payload = await getJson("/api/debug/database-context", contextDebug);
    updateTokenFlowRoles(payload.active_data_roles || []);
    contextDebug.textContent = JSON.stringify(payload, null, 2);
  } catch (error) {
    if (!contextDebug.textContent) {
      contextDebug.textContent = String(error.stack || error);
    }
  }
}

async function loadRequestContext() {
  const payload = await getJson("/api/alerts", contextDebug);
  renderRequestContext(payload.request_context);
}

async function loadPreflight() {
  preflightSummary.textContent = "Running checks...";
  preflightResults.innerHTML = "";
  try {
    const payload = await getJson("/api/preflight", contextDebug);
    renderPreflight(payload);
  } catch (error) {
    preflightSummary.textContent = "Preflight failed.";
    preflightResults.innerHTML = `<div class="preflight-item fail"><strong>Error</strong><span>${escapeHtml(error.message || error)}</span></div>`;
  }
}

async function getJson(url, outputElement) {
  const response = await fetch(url);
  const payload = await response.json();
  if (!response.ok) {
    outputElement.textContent = JSON.stringify(payload, null, 2);
    throw new Error(payload.error || "Request failed");
  }
  return payload;
}

function escapeHtml(value) {
  return String(value == null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function valueFor(row, key) {
  const upperKey = key.toUpperCase();
  return row[key] ?? row[upperKey] ?? "";
}

function renderRequestContext(context) {
  if (!context) {
    requestContext.innerHTML = "<div><dt>Status</dt><dd>No FIN request yet.</dd></div>";
    return;
  }
  const identity = context.identity || {};
  const pooled = context.pooled_connection || {};
  const roles = (context.active_data_roles || []).map((role) => valueFor(role, "role_name")).filter(Boolean);
  requestContext.innerHTML = `
    <div><dt>Pooled Session</dt><dd>${escapeHtml(pooled.session_id)}</dd></div>
    <div><dt>Service</dt><dd>${escapeHtml(pooled.service_name)}</dd></div>
    <div><dt>End User</dt><dd>${escapeHtml(identity.END_USER_NAME || identity.end_user_name)}</dd></div>
    <div><dt>Current User</dt><dd>${escapeHtml(identity.CURRENT_USER || identity.current_user)}</dd></div>
    <div><dt>Active Data Roles</dt><dd>${escapeHtml(roles.join(", "))}</dd></div>
  `;
}

function renderTokenFlow(payload) {
  const idToken = payload.id_token || {};
  const appToken = payload.user_access_token || {};
  const dbToken = ((payload.obo_database_token || {}).database_access_token) || {};
  tokenFlow.innerHTML = `
    ${flowStep("Browser sign-in", idToken.preferred_username || idToken.name || "Signed-in user", idToken.aud)}
    ${flowArrow()}
    ${flowStep("Web app API token", appToken.scp || "user_access", appToken.aud)}
    ${flowArrow()}
    ${flowStep("OBO database token", (dbToken.roles || []).join(", ") || dbToken.scp || "database token", dbToken.aud)}
    ${flowArrow()}
    ${flowStep("Oracle Deep Data Security", "Waiting for database context", "Active data roles")}
  `;
}

function updateTokenFlowRoles(roles) {
  const roleNames = roles.map((role) => valueFor(role, "role_name")).filter(Boolean);
  const roleStep = tokenFlow.querySelector("[data-flow-step='Oracle Deep Data Security']");
  if (!roleStep) {
    return;
  }
  const value = roleStep.querySelector(".flow-value");
  if (value) {
    value.textContent = roleNames.length ? roleNames.join(", ") : "No active data roles";
  }
}

function flowStep(label, value, detail) {
  return `
    <div class="flow-step" data-flow-step="${escapeHtml(label)}">
      <strong>${escapeHtml(label)}</strong>
      <span class="flow-value">${escapeHtml(value || "")}</span>
      <small>${escapeHtml(detail || "")}</small>
    </div>
  `;
}

function flowArrow() {
  return '<div class="flow-arrow" aria-hidden="true">-&gt;</div>';
}

function renderPreflight(payload) {
  const summary = payload.summary || {};
  preflightSummary.innerHTML = `
    <span class="status-pill pass">${escapeHtml(summary.pass || 0)} pass</span>
    <span class="status-pill warn">${escapeHtml(summary.warn || 0)} warn</span>
    <span class="status-pill fail">${escapeHtml(summary.fail || 0)} fail</span>
  `;
  preflightResults.innerHTML = (payload.checks || []).map((check) => `
    <div class="preflight-item ${escapeHtml(check.status)}">
      <strong>${escapeHtml(check.name)}</strong>
      <span>${escapeHtml(check.detail)}</span>
      ${check.evidence ? `<pre>${escapeHtml(JSON.stringify(check.evidence, null, 2))}</pre>` : ""}
    </div>
  `).join("");
}

refreshUser().then((user) => {
  if (user) {
    loadRequestContext();
    loadTokenDebug();
    loadContextDebug();
  }
});
