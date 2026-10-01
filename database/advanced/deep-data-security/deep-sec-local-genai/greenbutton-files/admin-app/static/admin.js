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

function stepIsCompleted(step) {
  const groups = JSON.parse(step.dataset.completionGroups || "[]");
  return groups.length > 0 && groups.every((group) => group.some((key) => completedSetupActions.has(key)));
}

function updateNavigationProgress() {
  const links = Array.from(document.querySelectorAll("[data-progress-steps]"));
  let total = 0;
  let completed = 0;
  links.forEach((link) => {
    let groups = [];
    try {
      groups = JSON.parse(link.dataset.progressSteps || "[]");
    } catch (_) {
      groups = [];
    }
    const excluded = link.dataset.progressExcluded === "true";
    const isCompleted = !excluded && groups.length > 0 && groups.every((group) =>
      group.some((actionKey) => completedSetupActions.has(actionKey))
    );
    link.classList.toggle("is-completed", isCompleted);
    link.querySelector(".page-check")?.toggleAttribute("hidden", !isCompleted);
    if (!excluded) {
      total += 1;
      if (isCompleted) completed += 1;
    }
  });
}

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
    const completed = stepIsCompleted(step);
    step.classList.remove("is-locked");
    step.classList.toggle("is-completed", completed);
    step.classList.toggle("is-current", !completed && key === selectedActionKey);
    button.disabled = false;
    button.setAttribute("aria-disabled", "false");
  });
  updateNavigationProgress();

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
    step.classList.toggle("is-current", selected && !stepIsCompleted(step));
    step.querySelector(".step-badge")?.setAttribute("aria-current", selected ? "step" : "false");
  });
  const validationButton = document.querySelector(`[data-action="${actionKey}"][data-validation-comparison="true"]`);
  if (validationButton) refreshValidationComparison();
}

async function requestJson(url, options, {redirectOn401 = true} = {}) {
  const response = await fetch(url, options);
  let payload = {};
  try {
    payload = await response.json();
  } catch (_) {
    payload = {error: "The server returned an unexpected response."};
  }
  if (response.status === 401 && redirectOn401) window.location.assign("/");
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
      }, {redirectOn401: false});
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
  logout.addEventListener("click", async (event) => {
    event.preventDefault();
    logout.disabled = true;
    document.cookie = "hol_tour_seen=; path=/; max-age=0; samesite=Lax";
    document.cookie = "hol_deebee_greeted=; path=/; max-age=0; samesite=Lax";
    try {
      await fetch("/api/logout", {
        method: "POST", headers: jsonHeaders, cache: "no-store", credentials: "same-origin"
      });
    } finally {
      // Replace the protected page so Back cannot restore it from history.
      window.location.replace("/");
    }
  });
}

function validationItem(label, value) {
  const item = document.createElement("li");
  const name = document.createElement("strong");
  name.textContent = `${label}: `;
  item.append(name, document.createTextNode(value || "—"));
  return item;
}

function describeRowPredicate(predicate) {
  if (!predicate || predicate.trim().toUpperCase() === "1=1" || predicate.trim().toUpperCase() === "1 = 1") {
    return "Every row";
  }
  const normalized = predicate.toLowerCase();
  const hasOwnRows = normalized.includes("sales_rep");
  const hasManagerOr = normalized.includes(" or ") && normalized.includes("manager_id");
  if (hasManagerOr) return "Their own rows, plus their team's";
  if (hasOwnRows) return "Only their own rows";
  if (normalized.includes("customer_id in")) return "Rows for customers they can already see";
  return predicate;
}

function columnPills(columns) {
  const list = Array.isArray(columns) ? columns : String(columns || "").split(",").map((column) => column.trim()).filter(Boolean);
  const wrap = document.createElement("div");
  wrap.className = "column-pills";
  list.forEach((column) => {
    const pill = document.createElement("span");
    pill.className = "column-pill";
    pill.textContent = column;
    wrap.append(pill);
  });
  return wrap;
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
    if (persona.columns?.length) card.append(columnPills(persona.columns));
    const grantsTitle = document.createElement("h5");
    grantsTitle.textContent = "Applicable data grants";
    card.append(grantsTitle);
    const grants = document.createElement("ul");
    grants.className = "validation-grants";
    if ((persona.grants || []).length) {
      for (const grant of persona.grants) {
        const item = document.createElement("li");
        item.className = "grant-card";
        const name = document.createElement("div");
        name.className = "grant-name";
        name.textContent = grant.name;
        const via = document.createElement("div");
        via.className = "grant-via muted";
        via.textContent = `via ${grant.role}`;
        const rows = document.createElement("div");
        rows.className = "grant-rows";
        rows.textContent = describeRowPredicate(grant.predicate);
        item.append(name, via, columnPills(grant.columns), rows);
        grants.append(item);
      }
    } else {
      const empty = document.createElement("li");
      empty.className = "muted";
      empty.textContent = "No applicable data grants";
      grants.append(empty);
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

function renderGrantComparison(snapshot) {
  const target = document.querySelector("#customize-grant-states");
  const query = document.querySelector("#customize-grant-query");
  if (!target) return;
  target.replaceChildren();
  if (!snapshot.available) {
    const message = document.createElement("p");
    message.className = "muted";
    message.textContent = snapshot.message || "Marvin's authorization is not available yet.";
    target.append(message);
    return;
  }
  if (query) query.textContent = snapshot.query || query.textContent;
  [["Before", snapshot.before], ["After", snapshot.after]].forEach(([label, state]) => {
    const card = document.createElement("article");
    card.className = "grant-state-card";
    const heading = document.createElement("h4");
    heading.textContent = label;
    card.append(heading);
    const summary = document.createElement("p");
    summary.className = "grant-state-summary";
    summary.textContent = state
      ? `${state.row_count} rows, ${state.columns.length} columns.`
      : "Pending Apply.";
    card.append(summary);
    if (state) {
      const columns = document.createElement("p");
      columns.className = "grant-state-columns";
      columns.textContent = `Visible columns: ${state.columns.join(", ")}`;
      card.append(columns);
    }
    target.append(card);
  });
}

async function refreshGrantComparison(method = "GET") {
  if (!document.querySelector("#customize-grant-states")) return;
  try {
    const {response, payload} = await requestJson("/api/customize-grant-comparison", {
      method,
      headers: jsonHeaders,
    });
    renderGrantComparison(response.ok ? payload : {available: false, message: payload.error});
  } catch (_) {
    renderGrantComparison({available: false, message: "Could not read Marvin's authorization comparison."});
  }
}

updateActionAvailability();
refreshGrantComparison();

document.querySelectorAll("[data-select-action]").forEach((button) => {
  button.addEventListener("click", () => selectAction(button.dataset.selectAction));
});

document.querySelectorAll(".next-button").forEach((button) => {
  button.addEventListener("click", () => {
    const nextKey = button.dataset.nextStep;
    if (!nextKey) return;
    selectAction(nextKey);
    document.querySelector(`[data-action-panel="${nextKey}"]`)?.scrollIntoView({behavior: "smooth", block: "start"});
  });
});

document.querySelectorAll(".run-action").forEach((button) => {
  button.addEventListener("click", async () => {
    const card = button.closest(".action-card");
    const actionArea = button.closest(".toggle-half") || card;
    const status = actionArea.querySelector(".action-status");
    const output = actionArea.querySelector(".action-output");
    const outputText = output.querySelector("pre");
    if (button.dataset.resetsSetup === "true" && !window.confirm("Run this administrative action?")) return;
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
      if (response.ok && button.dataset.validationComparison === "true") await refreshValidationComparison();
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

document.querySelectorAll(".customer-sales-link[data-complete-action]").forEach((link) => {
  link.addEventListener("click", () => {
    const actionKey = link.dataset.completeAction;
    const actionArea = link.closest(".action-card");
    const status = actionArea.querySelector(".action-status");
    const output = actionArea.querySelector(".action-output");
    const outputText = output.querySelector("pre");
    status.textContent = "Opening Customer Sales App…";

    // Do not prevent the link's default target=_blank navigation. The demo
    // opens immediately, while this page records the same link-step action
    // that the former Continue button used.
    void requestJson(`/api/actions/${actionKey}`, {method: "POST", headers: jsonHeaders})
      .then(({response, payload}) => {
        outputText.textContent = payload.output || payload.error || "No output was returned.";
        output.hidden = false;
        output.open = true;
        status.textContent = response.ok ? "Completed" : "Could not mark this step complete";
        if (response.ok) {
          completedSetupActions = Array.isArray(payload.completed_actions)
            ? new Set(payload.completed_actions)
            : new Set([...completedSetupActions, actionKey]);
          updateActionAvailability();
        }
      })
      .catch(() => {
        status.textContent = "Could not mark this step complete";
      });
  });
});

document.querySelectorAll(".review-quiz").forEach((quiz) => {
  const button = quiz.querySelector(".check-review-quiz");
  button.addEventListener("click", async () => {
    const selected = quiz.querySelector("input[type='radio']:checked");
    const feedback = quiz.querySelector(".review-quiz-feedback");
    feedback.hidden = false;
    feedback.className = "review-quiz-feedback error";
    if (!selected) {
      feedback.textContent = "Choose an answer first.";
      return;
    }
    button.disabled = true;
    try {
      const {response, payload} = await requestJson(`/api/steps/${quiz.dataset.stepKey}/quiz`, {
        method: "POST", headers: jsonHeaders, body: JSON.stringify({answer: selected.value}),
      });
      feedback.textContent = payload.feedback || payload.error || "Could not check the answer.";
      if (response.ok && payload.correct) feedback.className = "review-quiz-feedback correct";
      if (Array.isArray(payload.completed_actions)) {
        completedSetupActions = new Set(payload.completed_actions);
        updateActionAvailability();
      }
    } catch (_) {
      feedback.textContent = "Could not contact the administrator console. Try checking your answer again.";
    } finally {
      button.disabled = false;
    }
  });
});

document.querySelectorAll(".download-button[data-download-name]").forEach((link) => {
  link.addEventListener("click", async (event) => {
    event.preventDefault();
    if (link.dataset.downloading === "true") return;
    const status = link.closest(".action-card").querySelector(".action-status");
    link.dataset.downloading = "true";
    status.textContent = "Preparing download…";
    try {
      const response = await fetch(link.href);
      if (!response.ok) throw new Error("Download failed");
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const download = document.createElement("a");
      download.href = url;
      download.download = link.dataset.downloadName;
      document.body.append(download);
      download.click();
      download.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 60000);
      const completed = JSON.parse(response.headers.get("X-Completed-Actions") || "null");
      if (Array.isArray(completed)) completedSetupActions = new Set(completed);
      status.textContent = "Download ready.";
      updateActionAvailability();
    } catch (_) {
      status.textContent = "Could not download the archive. Try again.";
    } finally {
      delete link.dataset.downloading;
    }
  });
});

document.querySelector("#run-vibe-coding")?.addEventListener("click", async () => {
  const button = document.querySelector("#run-vibe-coding");
  const status = document.querySelector("#vibe-coding-status");
  const scriptOutput = document.querySelector("#vibe-coding-script-output");
  const reportLink = document.querySelector("#vibe-coding-report-link");
  const requestText = document.querySelector("#vibe-coding-request").value;
  button.disabled = true;
  status.textContent = "Creating Customer Sales App page…";
  reportLink.hidden = true;
  reportLink.replaceChildren();
  try {
    const {response, payload} = await requestJson("/api/vibe-coding/publish", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({request: requestText}),
    });
    status.textContent = response.ok ? "Customer Sales App page created." : (payload.error || "Failed.");
    if (payload.sql) {
      scriptOutput.hidden = false;
      scriptOutput.querySelector("pre").textContent = payload.sql;
    }
    if (response.ok && payload.report_path) {
      const link = document.createElement("a");
      const customerUrl = new URL(payload.report_path, window.location.origin);
      customerUrl.port = "7777";
      link.href = customerUrl.toString();
      link.textContent = "Open the new Customer Sales App report page";
      link.target = "_blank";
      link.rel = "noopener";
      reportLink.append(link);
      reportLink.hidden = false;
    }
  } catch (_) {
    status.textContent = "Could not contact the administrator console.";
  } finally {
    button.disabled = false;
    button.textContent = "Create Customer Sales App page";
  }
});

document.querySelectorAll(".grant-wizard").forEach((wizard) => {
  const actionKey = wizard.dataset.actionKey;
  const preview = wizard.querySelector(".grant-preview");
  const applyButton = wizard.querySelector(".run-grant-apply");
  const status = wizard.querySelector(".grant-status");
  const output = wizard.querySelector(".grant-output");
  const outputText = output?.querySelector("pre");
  const isAllExcept = wizard.dataset.wizardStyle === "all_except";

  function selectedColumns() {
    return Array.from(wizard.querySelectorAll(".grant-column-include:checked")).map((element) => element.value);
  }

  function selectedUpdateColumns() {
    return Array.from(wizard.querySelectorAll(".grant-update-include:checked")).map((element) => element.value);
  }

  function excludedColumns() {
    return Array.from(wizard.querySelectorAll(".grant-exclude-column:checked")).map((element) => element.value);
  }

  function restrictRows() {
    return wizard.querySelector(".grant-restrict-rows")?.checked || false;
  }

  function allowDelete() {
    return wizard.querySelector(".grant-allow-delete")?.checked || false;
  }

  function requestPayload() {
    if (isAllExcept) {
      return {
        excluded_columns: excludedColumns(),
      };
    }
    return {
      columns: selectedColumns(),
      update_columns: selectedUpdateColumns(),
      allow_delete: allowDelete(),
      restrict_rows: restrictRows(),
    };
  }

  async function refreshPreview() {
    if (!preview) return;
    try {
      const {payload} = await requestJson(`/api/actions/${actionKey}/preview`, {
        method: "POST",
        headers: jsonHeaders,
        body: JSON.stringify(requestPayload()),
      });
      preview.textContent = payload.sql || payload.error || "Could not generate a preview.";
    } catch (_) {
      preview.textContent = "Could not contact the administrator console.";
    }
  }

  if (isAllExcept) {
    wizard.querySelectorAll(".grant-exclude-column").forEach((box) => box.addEventListener("change", refreshPreview));
  } else {
    wizard.querySelectorAll(".grant-column-exclude").forEach((radio) => {
      radio.addEventListener("change", () => {
        if (radio.checked) {
          const pairedUpdateExclude = wizard.querySelector(`.grant-update-exclude[value="${radio.value}"]`);
          if (pairedUpdateExclude) pairedUpdateExclude.checked = true;
        }
      });
    });
    wizard.querySelectorAll(".grant-column-include, .grant-column-exclude, .grant-update-include, .grant-update-exclude, .grant-restrict-rows, .grant-allow-delete").forEach((box) => {
      box.addEventListener("change", refreshPreview);
    });
  }
  refreshPreview();

  applyButton?.addEventListener("click", async () => {
    if (wizard.dataset.confirmApply === "true" && !window.confirm("Apply this data grant?")) return;
    applyButton.disabled = true;
    status.textContent = "Applying…";
    try {
      const {response, payload} = await requestJson(`/api/actions/${actionKey}/apply`, {
        method: "POST",
        headers: jsonHeaders,
        body: JSON.stringify(requestPayload()),
      });
      status.textContent = response.ok ? "Applied." : (payload.error || "Failed.");
      if (output) {
        output.hidden = false;
        output.open = true;
        outputText.textContent = payload.output || payload.error || "No output was returned.";
      }
      if (response.ok) {
        if (Array.isArray(payload.completed_actions)) {
          completedSetupActions = new Set(payload.completed_actions);
        } else if (actionKey) {
          completedSetupActions.add(actionKey);
        }
        updateActionAvailability();
        await refreshGrantComparison("POST");
      }
    } catch (_) {
      status.textContent = "Could not contact the administrator console.";
    } finally {
      applyButton.disabled = false;
    }
  });
});

function loadTourSteps() {
  try {
    const steps = JSON.parse(document.body?.dataset.tourSteps || "[]");
    return Array.isArray(steps) ? steps : [];
  } catch (_) {
    return [];
  }
}

const TOUR_STEPS = loadTourSteps();
let endActiveTour = null;
let closeActiveGreeting = null;
let guideTimer = null;

function scheduleGuide(callback, delay) {
  window.clearTimeout(guideTimer);
  guideTimer = window.setTimeout(callback, delay);
}

function startTour() {
  window.clearTimeout(guideTimer);
  closeActiveGreeting?.(false);
  endActiveTour?.(false);
  if (!TOUR_STEPS.length) return;
  let index = 0;
  let target = null;
  let frame = null;
  const previousFocus = document.activeElement;
  const backdrop = document.createElement("div");
  backdrop.className = "tour-backdrop";
  const tooltip = document.createElement("div");
  tooltip.className = "tour-tooltip";
  tooltip.setAttribute("role", "dialog");
  tooltip.setAttribute("aria-modal", "true");
  tooltip.setAttribute("aria-labelledby", "tour-title");
  tooltip.setAttribute("aria-describedby", "tour-description");
  document.body.append(backdrop, tooltip);

  function end(restoreFocus = true) {
    window.cancelAnimationFrame(frame);
    window.removeEventListener("scroll", queuePosition, true);
    window.removeEventListener("resize", queuePosition);
    window.removeEventListener("pagehide", onPageHide);
    document.removeEventListener("pointerdown", onOutside, true);
    document.removeEventListener("keydown", onKeyDown, true);
    backdrop.remove();
    tooltip.remove();
    endActiveTour = null;
    document.cookie = "hol_tour_seen=1; path=/; max-age=31536000; samesite=Lax";
    if (restoreFocus && previousFocus?.isConnected) previousFocus.focus({preventScroll: true});
  }

  function position() {
    frame = null;
    if (!target?.isConnected) return end();
    const rect = target.getBoundingClientRect();
    const width = window.innerWidth;
    const height = window.innerHeight;
    const visible = rect.bottom > 0 && rect.top < height && rect.right > 0 && rect.left < width;
    backdrop.style.clipPath = visible ? "" : "none";
    backdrop.style.setProperty("--spot-top", `${Math.max(0, rect.top - 4)}px`);
    backdrop.style.setProperty("--spot-left", `${Math.max(0, rect.left - 4)}px`);
    backdrop.style.setProperty("--spot-width", `${Math.min(width, rect.right + 4) - Math.max(0, rect.left - 4)}px`);
    backdrop.style.setProperty("--spot-height", `${Math.min(height, rect.bottom + 4) - Math.max(0, rect.top - 4)}px`);
    const box = tooltip.getBoundingClientRect();
    let top = visible ? rect.bottom + 12 : 12;
    if (top + box.height > height - 12 && rect.top - box.height - 12 >= 12) top = rect.top - box.height - 12;
    tooltip.style.top = `${Math.max(12, Math.min(top, height - box.height - 12))}px`;
    tooltip.style.left = `${Math.max(12, Math.min(rect.left, width - box.width - 12))}px`;
  }

  function queuePosition() {
    if (frame === null) frame = window.requestAnimationFrame(position);
  }

  function onOutside(event) {
    if (!tooltip.contains(event.target)) end(false);
  }

  function onPageHide() { end(false); }

  function onKeyDown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      end();
    } else if (event.key === "Tab") {
      const buttons = Array.from(tooltip.querySelectorAll("button"));
      const first = buttons[0];
      const last = buttons[buttons.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!tooltip.contains(document.activeElement) || (!event.shiftKey && document.activeElement === last)) {
        event.preventDefault();
        first.focus();
      }
    }
  }

  function render() {
    while (index < TOUR_STEPS.length) {
      target = document.querySelector(TOUR_STEPS[index].selector);
      if (target) break;
      index += 1;
    }
    if (!target || index >= TOUR_STEPS.length) return end();
    const step = TOUR_STEPS[index];
    target.scrollIntoView({block: "nearest", inline: "nearest"});
    tooltip.replaceChildren();
    const heading = document.createElement("h3");
    heading.id = "tour-title";
    heading.textContent = step.title;
    const text = document.createElement("p");
    text.id = "tour-description";
    text.textContent = step.text;
    const actions = document.createElement("div");
    actions.className = "tour-actions";
    actions.innerHTML = '<button class="secondary small tour-skip" type="button">Skip tour</button><button class="primary small tour-next" type="button"></button>';
    actions.querySelector(".tour-next").textContent = index === TOUR_STEPS.length - 1 ? "Done" : "Next";
    tooltip.append(heading, text, actions);
    actions.querySelector(".tour-skip").addEventListener("click", () => end());
    actions.querySelector(".tour-next").addEventListener("click", () => {
      index += 1;
      if (index < TOUR_STEPS.length) render(); else end();
    });
    position();
    actions.querySelector(".tour-next").focus({preventScroll: true});
  }

  endActiveTour = end;
  window.addEventListener("scroll", queuePosition, {capture: true, passive: true});
  window.addEventListener("resize", queuePosition);
  window.addEventListener("pagehide", onPageHide);
  document.addEventListener("pointerdown", onOutside, true);
  document.addEventListener("keydown", onKeyDown, true);
  render();
}

document.querySelector("#tour-replay")?.addEventListener("click", startTour);

function showDeebeePopup() {
  window.clearTimeout(guideTimer);
  endActiveTour?.(false);
  closeActiveGreeting?.(false);
  const previousFocus = document.activeElement;
  const backdrop = document.createElement("div");
  backdrop.className = "deebee-popup-backdrop";
  const popup = document.createElement("div");
  popup.className = "deebee-popup";
  popup.setAttribute("role", "dialog");
  popup.setAttribute("aria-modal", "true");
  popup.setAttribute("aria-label", "Welcome from DeeBee");
  popup.innerHTML = `
    <img src="/static/images/deebee.png" alt="DeeBee" class="deebee-icon deebee-icon-large">
    <div>
      <p class="deebee-greeting">Hi, I'm DeeBee, your Oracle LiveLabs assistant. I will guide you through Oracle Deep Data Security, help you test each policy from the user's side, and point out patterns you can apply in your own environment.</p>
      <button class="primary small deebee-popup-dismiss" type="button">Got it</button>
    </div>
  `;
  document.body.append(backdrop, popup);

  function close(continueTour = false) {
    window.clearTimeout(guideTimer);
    backdrop.remove();
    popup.remove();
    document.removeEventListener("keydown", onKeyDown, true);
    closeActiveGreeting = null;
    document.cookie = "hol_deebee_greeted=1; path=/; max-age=31536000; samesite=Lax";
    if (previousFocus?.isConnected) previousFocus.focus({preventScroll: true});
    if (continueTour && !document.cookie.includes("hol_tour_seen=1")) scheduleGuide(startTour, 150);
    else document.cookie = "hol_tour_seen=1; path=/; max-age=31536000; samesite=Lax";
  }

  function onKeyDown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      close(false);
    } else if (event.key === "Tab") {
      event.preventDefault();
      popup.querySelector("button").focus();
    }
  }

  closeActiveGreeting = close;
  backdrop.addEventListener("click", () => close(false));
  popup.querySelector(".deebee-popup-dismiss").addEventListener("click", () => close(true));
  document.addEventListener("keydown", onKeyDown, true);
  popup.querySelector("button").focus({preventScroll: true});
}

window.addEventListener("load", () => {
  if (document.querySelector(".overview-card") && !document.cookie.includes("hol_deebee_greeted=1")) {
    scheduleGuide(showDeebeePopup, 300);
  } else if (!document.cookie.includes("hol_tour_seen=1")) {
    scheduleGuide(startTour, 400);
  }
});
