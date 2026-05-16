const userBox = document.querySelector("#userBox");
const tokensButton = document.querySelector("#tokensButton");
const contextButton = document.querySelector("#contextButton");
const requestContextButton = document.querySelector("#requestContextButton");
const tokenDebug = document.querySelector("#tokenDebug");
const contextDebug = document.querySelector("#contextDebug");
const requestContext = document.querySelector("#requestContext");

tokensButton.addEventListener("click", loadTokenDebug);
contextButton.addEventListener("click", loadContextDebug);
requestContextButton.addEventListener("click", loadRequestContext);

async function refreshUser() {
  const response = await fetch("/api/me");
  const payload = await response.json();
  const user = payload.user;
  if (!user) {
    userBox.innerHTML = "<strong>Not signed in</strong><br />Return to the app and sign in.";
    tokenDebug.textContent = "Sign in to view token claims.";
    contextDebug.textContent = "Sign in to view database context.";
    return null;
  }
  userBox.innerHTML = `<strong>${escapeHtml(user.name)}</strong><br />${escapeHtml(user.username)}<br />${escapeHtml((user.roles || []).join(", "))}`;
  return user;
}

async function loadTokenDebug() {
  tokenDebug.textContent = "Loading token claims...";
  try {
    const payload = await getJson("/api/debug/tokens", tokenDebug);
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
    contextDebug.textContent = JSON.stringify(payload, null, 2);
  } catch (error) {
    if (!contextDebug.textContent) {
      contextDebug.textContent = String(error.stack || error);
    }
  }
}

async function loadRequestContext() {
  const payload = await getJson("/api/employees", contextDebug);
  renderRequestContext(payload.request_context);
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
    requestContext.innerHTML = "<div><dt>Status</dt><dd>No HR request yet.</dd></div>";
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

refreshUser().then((user) => {
  if (user) {
    loadRequestContext();
    loadTokenDebug();
    loadContextDebug();
  }
});
