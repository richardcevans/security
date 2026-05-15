const identities = {
  marvin: {
    label: "Marvin",
    token: "demo:marvin@example.com:HR_VIEWER,SALES_REGION_US",
  },
  emma: {
    label: "Emma",
    token: "demo:emma@example.com:HR_VIEWER,FINANCE_ANALYST",
  },
  admin: {
    label: "DeepSec Admin",
    token: "demo:admin@example.com:HR_VIEWER,HR_ADMIN",
  },
};

let currentUser = "marvin";
let clientConfig = { auth_mode: "demo" };
let msalClient = null;
let entraAccount = null;
let entraAccessToken = "";

const questionInput = document.querySelector("#question");
const askButton = document.querySelector("#askButton");
const identitySummary = document.querySelector("#identitySummary");
const decisionList = document.querySelector("#decisionList");
const rowsBody = document.querySelector("#rowsBody");
const rawOutput = document.querySelector("#rawOutput");
const entraSignInButton = document.querySelector("#entraSignInButton");
const entraSignOutButton = document.querySelector("#entraSignOutButton");

document.querySelectorAll(".identity-button").forEach((button) => {
  button.addEventListener("click", () => {
    currentUser = button.dataset.user;
    document
      .querySelectorAll(".identity-button")
      .forEach((item) => item.classList.toggle("active", item === button));
    updateIdentitySummary();
    askQuestion();
  });
});

askButton.addEventListener("click", askQuestion);
entraSignInButton.addEventListener("click", signInWithEntra);
entraSignOutButton.addEventListener("click", signOutOfEntra);
questionInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    askQuestion();
  }
});

function updateIdentitySummary() {
  if (clientConfig.auth_mode === "entra") {
    if (!entraAccount) {
      identitySummary.innerHTML = "<strong>Not signed in</strong><span>Microsoft Entra ID</span>";
      return;
    }
    identitySummary.innerHTML = `<strong>${escapeHtml(entraAccount.name || entraAccount.username)}</strong><span>${escapeHtml(entraAccount.username)}</span>`;
    return;
  }

  const identity = identities[currentUser];
  const roles = identity.token.split(":")[2].replaceAll(",", ", ");
  identitySummary.innerHTML = `<strong>${identity.label}</strong><span>${roles}</span>`;
}

async function askQuestion() {
  askButton.disabled = true;
  askButton.textContent = "Working";

  try {
    const token = await getAuthorizationToken();
    const response = await fetch("/api/ask", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ question: questionInput.value }),
    });

    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || payload.detail || "Request failed");
    }

    renderDecision(payload);
    renderRows(payload.result.rows || []);
    rawOutput.textContent = JSON.stringify(payload, null, 2);
  } catch (error) {
    rowsBody.innerHTML = `<tr><td colspan="6" class="empty">${error.message}</td></tr>`;
    rawOutput.textContent = String(error.stack || error);
  } finally {
    askButton.disabled = false;
    askButton.textContent = "Ask";
  }
}

async function getAuthorizationToken() {
  if (clientConfig.auth_mode !== "entra") {
    return identities[currentUser].token;
  }
  if (!entraAccount) {
    await signInWithEntra();
  }
  if (!entraAccessToken) {
    await acquireEntraToken();
  }
  return entraAccessToken;
}

async function signInWithEntra() {
  if (!msalClient) {
    throw new Error("MSAL is not loaded. Check browser network access to the MSAL CDN.");
  }
  const login = await msalClient.loginPopup({
    scopes: [clientConfig.scope],
    prompt: "select_account",
  });
  entraAccount = login.account;
  entraAccessToken = login.accessToken || "";
  updateIdentitySummary();
  await acquireEntraToken();
  await askQuestion();
}

async function acquireEntraToken() {
  const response = await msalClient.acquireTokenSilent({
    account: entraAccount,
    scopes: [clientConfig.scope],
  }).catch(() =>
    msalClient.acquireTokenPopup({
      account: entraAccount,
      scopes: [clientConfig.scope],
    }),
  );
  entraAccessToken = response.accessToken;
}

async function signOutOfEntra() {
  const account = entraAccount;
  entraAccount = null;
  entraAccessToken = "";
  updateIdentitySummary();
  if (account) {
    await msalClient.logoutPopup({ account });
  }
}

function renderDecision(payload) {
  const roles = payload.identity.roles.join(", ");
  decisionList.innerHTML = `
    <div>
      <dt>User</dt>
      <dd>${escapeHtml(payload.identity.display_name)}</dd>
    </div>
    <div>
      <dt>Roles</dt>
      <dd>${escapeHtml(roles)}</dd>
    </div>
    <div>
      <dt>Selected Tool</dt>
      <dd>${escapeHtml(payload.selected_tool)}</dd>
    </div>
    <div>
      <dt>Answer</dt>
      <dd>${escapeHtml(payload.answer)}</dd>
    </div>
  `;
}

function renderRows(rows) {
  if (!rows.length) {
    rowsBody.innerHTML = '<tr><td colspan="6" class="empty">No visible rows.</td></tr>';
    return;
  }

  rowsBody.innerHTML = rows
    .map(
      (row) => `
      <tr>
        <td>${escapeHtml(row.employee_id)}</td>
        <td>${escapeHtml(row.name)}</td>
        <td>${escapeHtml(row.ssn ?? "NULL")}</td>
        <td>${escapeHtml(row.salary)}</td>
        <td>${escapeHtml(row.department_id ?? "")}</td>
        <td>${escapeHtml(row.manager_id ?? "")}</td>
      </tr>
    `,
    )
    .join("");
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

async function initialize() {
  const response = await fetch("/api/config");
  clientConfig = await response.json();

  if (clientConfig.auth_mode === "entra") {
    document.querySelectorAll(".identity-button").forEach((button) => {
      button.hidden = true;
    });
    entraSignInButton.hidden = false;
    entraSignInButton.classList.add("primary");
    entraSignOutButton.hidden = false;
    askButton.textContent = "Sign In And Ask";

    if (!clientConfig.client_id || !clientConfig.tenant_id || !clientConfig.scope) {
      rawOutput.textContent =
        "Set CLIENT_ID, TENANT_ID, and APP_ID_URI from the entra-id-data-grants lab before using Entra mode.";
      updateIdentitySummary();
      return;
    }

    msalClient = new msal.PublicClientApplication({
      auth: {
        clientId: clientConfig.client_id,
        authority: `https://login.microsoftonline.com/${clientConfig.tenant_id}`,
        redirectUri: window.location.origin,
      },
      cache: {
        cacheLocation: "sessionStorage",
      },
    });
  }

  updateIdentitySummary();
  if (clientConfig.auth_mode !== "entra") {
    askQuestion();
  }
}

initialize().catch((error) => {
  rawOutput.textContent = String(error.stack || error);
});
