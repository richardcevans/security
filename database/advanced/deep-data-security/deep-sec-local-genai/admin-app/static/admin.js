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
    const actionArea = button.closest(".toggle-half") || button.closest(".action-card");
    const status = actionArea.querySelector(".action-status");
    button.disabled = false;
    if (status.dataset.lockMessage && status.textContent === status.dataset.lockMessage) {
      status.textContent = "";
    }
  });

  document.querySelectorAll(".step-item").forEach((step) => {
    const key = step.dataset.actionStep;
    const button = step.querySelector(".step-badge");
    const completed = (step.dataset.actionKeys || "").split(",").some((actionKey) => completedSetupActions.has(actionKey));
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
  if (actionKey === "validate_as_marvin") refreshValidationComparison();
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
  if (state.direct_reports?.length) {
    const term = document.createElement("dt");
    term.textContent = "Direct reports";
    const value = document.createElement("dd");
    value.textContent = state.direct_reports.join(", ");
    target.append(term, value);
  }
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

function validationItem(label, value) {
  const item = document.createElement("li");
  const name = document.createElement("strong");
  name.textContent = `${label}: `;
  item.append(name, document.createTextNode(value || "—"));
  return item;
}

function renderValidationComparison(snapshot) {
  const target = document.querySelector("#validation-personas");
  const query = document.querySelector("#validation-query");
  if (!target) return;
  target.replaceChildren();
  if (!snapshot.available) {
    const message = document.createElement("p");
    message.className = "muted";
    message.textContent = snapshot.message || "Create Emma, Marvin, and the data roles before running this comparison.";
    target.append(message);
    return;
  }
  if (query) query.textContent = snapshot.query || query.textContent;
  for (const persona of snapshot.personas || []) {
    const card = document.createElement("article");
    card.className = "validation-persona";
    const title = document.createElement("h4");
    title.textContent = persona.username;
    card.append(title);
    if (!persona.available) {
      const message = document.createElement("p");
      message.className = "error";
      message.textContent = `${persona.username} is not available yet.`;
      card.append(message);
      target.append(card);
      continue;
    }
    const details = document.createElement("dl");
    [["Active data roles", (persona.roles || []).join(", ") || "No active data role"], ["Rows returned", String(persona.row_count ?? "—")]].forEach(([label, value]) => {
      const term = document.createElement("dt");
      term.textContent = label;
      const description = document.createElement("dd");
      description.textContent = value;
      details.append(term, description);
    });
    card.append(details);
    const grantsTitle = document.createElement("h5");
    grantsTitle.textContent = "Applicable data grants";
    card.append(grantsTitle);
    const grants = document.createElement("ul");
    grants.className = "validation-grants";
    if ((persona.grants || []).length) {
      for (const grant of persona.grants) {
        const item = document.createElement("li");
        const name = document.createElement("strong");
        name.textContent = grant.name;
        item.append(name);
        const details = document.createElement("ul");
        details.append(validationItem("Granted through", grant.role));
        details.append(validationItem("Columns", grant.columns));
        details.append(validationItem("Rows", grant.predicate));
        item.append(details);
        grants.append(item);
      }
    } else {
      grants.append(validationItem("No applicable data grants", ""));
    }
    card.append(grants);
    target.append(card);
  }
}

async function refreshValidationComparison() {
  if (!document.querySelector("#validation-personas")) return;
  try {
    const {response, payload} = await requestJson("/api/validation-comparison");
    renderValidationComparison(response.ok ? payload : {available: false, message: payload.error});
  } catch (_) {
    renderValidationComparison({available: false, message: "Could not read the Oracle authorization comparison."});
  }
}

document.querySelector("#refresh-state")?.addEventListener("click", refreshState);
if (document.querySelector("#state")) refreshState();
updateActionAvailability();

document.querySelectorAll("[data-select-action]").forEach((button) => {
  button.addEventListener("click", () => selectAction(button.dataset.selectAction));
});

document.querySelectorAll(".next-button").forEach((button) => {
  button.addEventListener("click", () => {
    const nextKey = button.dataset.nextStep;
    if (!nextKey) return;
    selectAction(nextKey);
    document.querySelector(`.step-item[data-action-step="${nextKey}"]`)?.scrollIntoView({behavior: "smooth", block: "nearest", inline: "center"});
  });
});

document.querySelectorAll(".run-action").forEach((button) => {
  button.addEventListener("click", async () => {
    const card = button.closest(".action-card");
    const actionArea = button.closest(".toggle-half") || card;
    const status = actionArea.querySelector(".action-status");
    const output = actionArea.querySelector(".action-output");
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
      output.open = true;
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
      if (button.dataset.action === "validate_as_marvin") await refreshValidationComparison();
    } catch (_) {
      status.textContent = "Action failed";
      outputText.textContent = "Could not contact the administrator console.";
      output.hidden = false;
      output.open = true;
    } finally {
      updateActionAvailability();
    }
  });
});

function updateLastRunBanner(status, summaryText, model) {
  const banner = document.querySelector("#vibe-last-run");
  const dot = document.querySelector("#vibe-last-run-status");
  const summary = document.querySelector("#vibe-last-run-summary");
  const modelEl = document.querySelector("#vibe-last-run-model");
  if (!banner) return;
  banner.hidden = false;
  dot.className = "vibe-last-run-status " + status;
  summary.textContent = summaryText;
  modelEl.textContent = model || "—";
}

function setVibeMeta(selector, value, hidden = false) {
  const element = document.querySelector(selector);
  if (!element) return;
  element.textContent = value;
  element.parentElement.hidden = hidden;
}

function renderVibeFiles(files) {
  const filesSection = document.querySelector("#vibe-files-section");
  const filesList = document.querySelector("#vibe-files");
  if (!filesSection || !filesList) return;
  filesList.replaceChildren();
  for (const file of files || []) {
    const item = document.createElement("li");
    const code = document.createElement("code");
    code.textContent = file;
    item.append(code);
    filesList.append(item);
  }
  filesSection.hidden = !filesList.childElementCount;
}

function setAllVibeButtonsDisabled(disabled) {
  document.querySelectorAll(".run-vibe, .run-vibe-reset").forEach((btn) => {
    if (!btn.dataset.vibeBusy) btn.disabled = disabled;
  });
}

function setCardStatus(key, state, text) {
  const element = document.querySelector(`.vibe-card-status[data-status-for="${key}"]`);
  if (!element) return;
  element.className = "vibe-card-status " + state;
  element.textContent = text;
}

document.querySelectorAll(".run-vibe").forEach((button) => {
  button.addEventListener("click", async () => {
    const requestKey = button.dataset.vibeRequest;
    const customPrompt = document.querySelector("#custom-vibe-prompt");
    const prompt = requestKey === "custom" ? customPrompt?.value.trim() : button.dataset.prompt;
    const output = document.querySelector("#vibe-output");
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
    button.dataset.vibeBusy = "true";
    setAllVibeButtonsDisabled(true);
    setCardStatus(requestKey, "running", "Running…");
    output.hidden = false;
    setVibeMeta("#vibe-target", "…");
    setVibeMeta("#vibe-model", "…");
    setVibeMeta("#vibe-region", "…");
    const promptElement = document.querySelector("#vibe-prompt");
    promptElement.textContent = prompt;
    promptElement.closest(".vibe-section").hidden = false;
    document.querySelector("#vibe-summary").textContent = "Running Vibe. This can take several minutes…";
    renderVibeFiles([]);
    document.querySelector("#vibe-raw").textContent = "";
    if (reload) reload.textContent = "";
    output.scrollIntoView({ behavior: "smooth", block: "start" });
    updateLastRunBanner("running", "Vibe is working…", "");
    try {
      const {response, payload} = await requestJson(`/api/vibe/${requestKey}`, {
        method: "POST", headers: jsonHeaders, body: JSON.stringify({prompt})
      });
      setVibeMeta("#vibe-target", payload.target_project || "Unknown");
      setVibeMeta("#vibe-model", payload.model || "Unknown");
      setVibeMeta("#vibe-region", payload.region || "Unknown");
      document.querySelector("#vibe-summary").textContent = payload.genai_summary || payload.error || "No summary was returned.";
      document.querySelector("#vibe-raw").textContent = payload.output || payload.error || "No output was returned.";
      renderVibeFiles(payload.files_changed);
      updateLastRunBanner(
        response.ok && payload.applied ? "ok" : "fail",
        response.ok && payload.applied ? "Applied changes" : (response.ok ? "No file changes applied" : "Failed"),
        payload.model || ""
      );
      setCardStatus(
        requestKey,
        response.ok && payload.applied ? "ok" : "fail",
        response.ok && payload.applied ? "Applied" : (response.ok ? "No changes applied" : "Failed")
      );
      if (reload) {
        reload.textContent = response.ok && payload.applied
          ? "Vibe applied changes and the Customer Sales application was reloaded. Sign in again if needed."
          : (response.ok ? "Vibe did not apply file changes, so the Customer Sales application was not reloaded." : "Vibe did not complete. Review the output above.");
      }
    } catch (_) {
      const message = "Could not contact the administrator console.";
      document.querySelector("#vibe-summary").textContent = message;
      document.querySelector("#vibe-raw").textContent = message;
      updateLastRunBanner("fail", "Failed", "");
      setCardStatus(requestKey, "fail", "Failed");
      if (reload) reload.textContent = "";
    } finally {
      button.disabled = false;
      button.textContent = originalLabel;
      delete button.dataset.vibeBusy;
      setAllVibeButtonsDisabled(false);
    }
  });
});

document.querySelector(".run-vibe-reset")?.addEventListener("click", async (event) => {
  const button = event.currentTarget;
  const output = document.querySelector("#vibe-output");
  const reload = document.querySelector("#vibe-reload");
  if (!window.confirm("Replace the live Customer Sales application with the original application copy? This cannot be undone except by restoring a backup.")) return;
  const originalLabel = button.textContent;
  button.disabled = true;
  button.textContent = "Restoring…";
  button.dataset.vibeBusy = "true";
  setAllVibeButtonsDisabled(true);
  setCardStatus("reset", "running", "Running…");
  output.hidden = false;
  setVibeMeta("#vibe-target", "…");
  setVibeMeta("#vibe-model", "", true);
  setVibeMeta("#vibe-region", "", true);
  document.querySelector("#vibe-prompt").closest(".vibe-section").hidden = true;
  document.querySelector("#vibe-summary").textContent = "Restoring original application. This can take a moment…";
  renderVibeFiles([]);
  document.querySelector("#vibe-raw").textContent = "";
  if (reload) reload.textContent = "";
  output.scrollIntoView({ behavior: "smooth", block: "start" });
  updateLastRunBanner("running", "Restoring original application…", "");
  try {
    const {response, payload} = await requestJson("/api/vibe/reset", {method: "POST", headers: jsonHeaders});
    setVibeMeta("#vibe-target", payload.target_project || "Customer Sales application");
    document.querySelector("#vibe-summary").textContent = response.ok
      ? "Original application restored."
      : (payload.error || "Restore did not complete.");
    document.querySelector("#vibe-raw").textContent = payload.output || payload.error || "No output was returned.";
    updateLastRunBanner(response.ok ? "ok" : "fail", response.ok ? "Restored original application" : "Failed", "");
    setCardStatus("reset", response.ok ? "ok" : "fail", response.ok ? "Applied" : "Failed");
    if (reload) {
      reload.textContent = response.ok
        ? "Original application restored and the Customer Sales application was reloaded."
        : "Restore did not complete. Review the output above.";
    }
  } catch (_) {
    const message = "Could not contact the administrator console.";
    document.querySelector("#vibe-summary").textContent = message;
    document.querySelector("#vibe-raw").textContent = message;
    updateLastRunBanner("fail", "Failed", "");
    setCardStatus("reset", "fail", "Failed");
    if (reload) reload.textContent = "";
  } finally {
    button.disabled = false;
    button.textContent = originalLabel;
    delete button.dataset.vibeBusy;
    setAllVibeButtonsDisabled(false);
  }
});

function selectedGrantColumns() {
  return Array.from(document.querySelectorAll(".grant-column:checked")).map((element) => element.value);
}

async function refreshGrantPreview() {
  const preview = document.querySelector("#grant-preview");
  if (!preview) return;
  try {
    const {payload} = await requestJson("/api/manager-grant/preview", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({columns: selectedGrantColumns()}),
    });
    preview.textContent = payload.sql || payload.error || "Could not generate a preview.";
  } catch (_) {
    preview.textContent = "Could not contact the administrator console.";
  }
}

document.querySelectorAll(".grant-column").forEach((box) => {
  box.addEventListener("change", refreshGrantPreview);
});
if (document.querySelector("#grant-preview")) refreshGrantPreview();

document.querySelector(".run-grant-apply")?.addEventListener("click", async (event) => {
  const button = event.currentTarget;
  const status = document.querySelector("#grant-status");
  const output = document.querySelector("#grant-output");
  const outputText = output?.querySelector("pre");
  if (!window.confirm("Apply this column set to Marvin's manager grant now?")) return;
  button.disabled = true;
  status.textContent = "Applying…";
  try {
    const {response, payload} = await requestJson("/api/manager-grant/apply", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({columns: selectedGrantColumns()}),
    });
    status.textContent = response.ok ? "Applied." : (payload.error || "Failed.");
    if (output) {
      output.hidden = false;
      output.open = true;
      outputText.textContent = payload.output || payload.error || "No output was returned.";
    }
    if (response.ok) await refreshState();
  } catch (_) {
    status.textContent = "Could not contact the administrator console.";
  } finally {
    button.disabled = false;
  }
});
