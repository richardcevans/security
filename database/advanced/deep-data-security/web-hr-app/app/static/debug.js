const userBox = document.querySelector("#userBox");
const tokensButton = document.querySelector("#tokensButton");
const contextButton = document.querySelector("#contextButton");
const tokenDebug = document.querySelector("#tokenDebug");
const contextDebug = document.querySelector("#contextDebug");

tokensButton.addEventListener("click", loadTokenDebug);
contextButton.addEventListener("click", loadContextDebug);

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

refreshUser().then((user) => {
  if (user) {
    loadTokenDebug();
    loadContextDebug();
  }
});
