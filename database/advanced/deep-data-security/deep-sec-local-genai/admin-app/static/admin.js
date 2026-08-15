const csrfToken = document.querySelector("meta[name='csrf-token']")?.content;
const jsonHeaders = {"Content-Type": "application/json", "X-CSRFToken": csrfToken};
function loadSetupProgress() {
  try {
    return new Set(JSON.parse(document.body?.dataset.completedActions || "[]"));
  } catch (_) {
    return new Set();
  }
}

let completedSetupActions = loadSetupProgress();
let selectedActionKey = null;

function updateActionAvailability() {
  document.querySelectorAll(".run-action").forEach((button) => {
    const status = button.closest(".action-card").querySelector(".action-status");
    button.disabled = false;
    if (status.dataset.lockMessage && status.textContent === status.dataset.lockMessage) {
      status.textContent = "";
    }
  });

  document.querySelectorAll(".step-item").forEach((step) => {
    const key = step.dataset.actionStep;
    const button = step.querySelector(".step-badge");
    const completed = completedSetupActions.has(key);
    step.classList.remove("is-locked");
    step.classList.toggle("is-completed", completed);
    step.classList.toggle("is-current", !completed && key === selectedActionKey);
    button.disabled = false;
    button.setAttribute("aria-disabled", "false");
  });

  if (!selectedActionKey) {
    const firstStep = document.querySelector("[data-select-action]");
    if (firstStep) selectAction(firstStep.dataset.selectAction);
  }
}

function selectAction(actionKey) {
  const targetStep = document.querySelector(`.step-item[data-action-step="${actionKey}"]`);
  if (!targetStep) return;
  selectedActionKey = actionKey;
  document.querySelectorAll("[data-action-panel]").forEach((panel) => {
    panel.hidden = panel.dataset.actionPanel !== actionKey;
  });
  document.querySelectorAll(".step-item").forEach((step) => {
    const selected = step.dataset.actionStep === actionKey;
    step.classList.toggle("is-selected", selected);
    step.classList.toggle("is-current", selected && !completedSetupActions.has(step.dataset.actionStep));
    step.querySelector(".step-badge")?.setAttribute("aria-current", selected ? "step" : "false");
  });
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  let payload = {};
  try {
    payload = await response.json();
  } catch (_) {
    payload = {error: "The server returned an unexpected response."};
  }
  if (response.status === 401) window.location.assign("/");
  return {response, payload};
}

const loginForm = document.querySelector("#login-form");
if (loginForm) {
  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const password = document.querySelector("#password");
    const button = document.querySelector("#login");
    const error = document.querySelector("#error");
    error.textContent = "";
    button.disabled = true;
    button.textContent = "Signing in…";
    try {
      const {response, payload} = await requestJson("/api/login", {
        method: "POST", headers: jsonHeaders, body: JSON.stringify({password: password.value})
      });
      if (response.ok) {
        window.location.assign("/console");
        return;
      }
      error.textContent = payload.error || "Database sign-in failed.";
    } catch (_) {
      error.textContent = "Unable to sign in. Please try again.";
    } finally {
      button.disabled = false;
      button.textContent = "Sign in to Admin Console";
    }
  });
}

const logout = document.querySelector("#logout");
if (logout) {
  logout.addEventListener("click", async () => {
    await requestJson("/api/logout", {method: "POST", headers: jsonHeaders});
    window.location.assign("/");
  });
}

const stateLabels = ["End user", "Active data roles", "Rows returned by Oracle", "Columns returned by Oracle"];

function renderState(state) {
  const target = document.querySelector("#state");
  if (!target) return;
  const values = [
    state.end_user || "—",
    state.data_roles?.join(", ") || "No active data role",
    String(state.row_count ?? "—"),
    state.visible_columns?.join(", ") || "—"
  ];
  target.replaceChildren();
  stateLabels.forEach((label, index) => {
    const term = document.createElement("dt");
    term.textContent = label;
    const value = document.createElement("dd");
    value.textContent = values[index];
    target.append(term, value);
  });
}

async function refreshState() {
  const status = document.querySelector("#state-status");
  const error = document.querySelector("#state-error");
  if (!status || !error) return;
  status.textContent = "Reading Oracle authorization…";
  error.textContent = "";
  try {
    const {response, payload} = await requestJson("/api/state");
    if (!response.ok) {
      error.textContent = payload.error || "Could not read Marvin's current state.";
      status.textContent = "Unavailable";
      return;
    }
    if (!payload.available) {
      renderState({});
      error.textContent = payload.message || "Marvin's current state is not available yet.";
      status.textContent = "Waiting for Create MARVIN";
      return;
    }
    renderState(payload);
    status.textContent = "Read directly from Oracle";
  } catch (_) {
    error.textContent = "Could not read Marvin's current state.";
    status.textContent = "Unavailable";
  }
}

document.querySelector("#refresh-state")?.addEventListener("click", refreshState);
if (document.querySelector("#state")) refreshState();
updateActionAvailability();

document.querySelectorAll("[data-select-action]").forEach((button) => {
  button.addEventListener("click", () => selectAction(button.dataset.selectAction));
});

document.querySelectorAll(".run-action").forEach((button) => {
  button.addEventListener("click", async () => {
    const card = button.closest(".action-card");
    const status = card.querySelector(".action-status");
    const output = card.querySelector(".action-output");
    const outputText = output.querySelector("pre");
    if (card.classList.contains("destructive") && !window.confirm("Run this administrative action?")) return;
    button.disabled = true;
    status.textContent = "Running SQL*Plus…";
    output.hidden = true;
    try {
      const {response, payload} = await requestJson(`/api/actions/${button.dataset.action}`, {
        method: "POST", headers: jsonHeaders
      });
      outputText.textContent = payload.output || payload.error || "No output was returned.";
      output.hidden = false;
      status.textContent = response.ok ? "Completed" : "Action did not complete";
      if (response.ok) {
        if (Array.isArray(payload.completed_actions)) {
          completedSetupActions = new Set(payload.completed_actions);
        } else if (button.dataset.resetsSetup === "true") {
          completedSetupActions = new Set();
        } else {
          completedSetupActions.add(button.dataset.action);
        }
        updateActionAvailability();
      }
      await refreshState();
    } catch (_) {
      status.textContent = "Action failed";
      outputText.textContent = "Could not contact the administrator console.";
      output.hidden = false;
    } finally {
      updateActionAvailability();
    }
  });
});

document.querySelectorAll(".run-vibe").forEach((button) => {
  button.addEventListener("click", async () => {
    const requestKey = button.dataset.vibeRequest;
    const customPrompt = document.querySelector("#custom-vibe-prompt");
    const prompt = requestKey === "custom" ? customPrompt?.value.trim() : button.dataset.prompt;
    const output = document.querySelector("#vibe-output");
    const outputText = output?.querySelector("pre");
    const reload = document.querySelector("#vibe-reload");
    if (!prompt) {
      if (reload) reload.textContent = "Enter a custom Vibe request first.";
      output.hidden = false;
      return;
    }
    if (!window.confirm("Run Vibe and apply its proposed changes to the live Customer Sales application?")) return;
    const originalLabel = button.textContent;
    button.disabled = true;
    button.textContent = "Vibe is working…";
    output.hidden = false;
    outputText.textContent = "Running Vibe. This can take several minutes…";
    if (reload) reload.textContent = "";
    try {
      const {response, payload} = await requestJson(`/api/vibe/${requestKey}`, {
        method: "POST", headers: jsonHeaders, body: JSON.stringify({prompt})
      });
      outputText.textContent = payload.output || payload.error || "No output was returned.";
      if (reload) {
        reload.textContent = response.ok && payload.applied
          ? "Vibe applied changes and the Customer Sales application was reloaded. Sign in again if needed."
          : (response.ok ? "Vibe did not apply file changes, so the Customer Sales application was not reloaded." : "Vibe did not complete. Review the output above.");
      }
    } catch (_) {
      outputText.textContent = "Could not contact the administrator console.";
      if (reload) reload.textContent = "";
    } finally {
      button.disabled = false;
      button.textContent = originalLabel;
    }
  });
});

document.querySelector(".run-vibe-reset")?.addEventListener("click", async (event) => {
  const button = event.currentTarget;
  const output = document.querySelector("#vibe-output");
  const outputText = output?.querySelector("pre");
  const reload = document.querySelector("#vibe-reload");
  if (!window.confirm("Replace the live Customer Sales application with the known-good copy? This cannot be undone except by restoring a backup.")) return;
  const originalLabel = button.textContent;
  button.disabled = true;
  button.textContent = "Restoring…";
  output.hidden = false;
  outputText.textContent = "Restoring known-good copy. This can take a moment…";
  if (reload) reload.textContent = "";
  try {
    const {response, payload} = await requestJson("/api/vibe/reset", {method: "POST", headers: jsonHeaders});
    outputText.textContent = payload.output || payload.error || "No output was returned.";
    if (reload) {
      reload.textContent = response.ok
        ? "Known-good copy restored and the Customer Sales application was reloaded."
        : "Restore did not complete. Review the output above.";
    }
  } catch (_) {
    outputText.textContent = "Could not contact the administrator console.";
    if (reload) reload.textContent = "";
  } finally {
    button.disabled = false;
    button.textContent = originalLabel;
  }
});
