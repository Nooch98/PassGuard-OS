const statusText = document.getElementById("statusText");
const originText = document.getElementById("originText");
const sessionText = document.getElementById("sessionText");
const credentialsList = document.getElementById("credentialsList");
const messageBox = document.getElementById("messageBox");

const refreshBtn = document.getElementById("refreshBtn");
const loadBtn = document.getElementById("loadBtn");
const lockBtn = document.getElementById("lockBtn");

function showMessage(text, type = "info") {
  messageBox.textContent = text;
  messageBox.className = `message ${type}`;
}

function clearMessage() {
  messageBox.textContent = "";
  messageBox.className = "message hidden";
}

function setStatusUi(data) {
  statusText.textContent = data?.session_active ? "Connected" : "Locked";
  sessionText.textContent = data?.session_active
    ? `${data?.remaining_seconds ?? 0}s remaining`
    : "No active session";
}

async function copyToClipboard(text, successMessage) {
  if (!text || !text.trim()) {
    showMessage("Nothing to copy.", "error");
    return;
  }

  try {
    await navigator.clipboard.writeText(text);
    showMessage(successMessage, "success");
  } catch (err) {
    showMessage("Clipboard access failed.", "error");
  }
}

function renderCredentials(credentials = []) {
  credentialsList.innerHTML = "";

  if (!credentials.length) {
    credentialsList.innerHTML = `<div class="empty">No matching credentials found.</div>`;
    return;
  }

  for (const credential of credentials) {
    const item = document.createElement("div");
    item.className = "credential-item";

    const title = document.createElement("div");
    title.className = "credential-title";
    title.textContent = credential.title || credential.username || "Credential";

    const meta = document.createElement("div");
    meta.className = "credential-meta";
    meta.textContent = credential.username || "(no username)";

    const origin = document.createElement("div");
    origin.className = "credential-origin";
    origin.textContent = credential.origin
      ? `Matched for: ${credential.origin}`
      : "Matched for current site";

    const actions = document.createElement("div");
    actions.className = "credential-actions";

    const fillBtn = document.createElement("button");
    fillBtn.className = "btn primary small";
    fillBtn.textContent = "Fill";
    fillBtn.title =
      "Use autofill on the current page. Manual copy may be safer on unusual or sensitive login pages.";
    fillBtn.addEventListener("click", async () => {
      clearMessage();

      const result = await chrome.runtime.sendMessage({
        type: "PG_AUTOFILL_CREDENTIAL",
        credential
      });

      if (!result?.ok) {
        showMessage(result?.error || "Autofill failed", "error");
        return;
      }

      showMessage(
        "Form filled. On unusual or sensitive pages, manual copy may be safer.",
        "success"
      );
    });

    const copyPasswordBtn = document.createElement("button");
    copyPasswordBtn.className = "btn copy small";
    copyPasswordBtn.textContent = "Copy Password";
    copyPasswordBtn.title =
      "Copy only the password. Recommended for unusual or sensitive login pages.";
    copyPasswordBtn.addEventListener("click", async () => {
      clearMessage();
      await copyToClipboard(
        credential.password || "",
        "Password copied. It may be safer to paste manually on sensitive pages."
      );
    });

    const copyUsernameBtn = document.createElement("button");
    copyUsernameBtn.className = "btn secondary small";
    copyUsernameBtn.textContent = "Copy Username";
    copyUsernameBtn.title = "Copy only the username.";
    copyUsernameBtn.addEventListener("click", async () => {
      clearMessage();
      await copyToClipboard(
        credential.username || "",
        "Username copied."
      );
    });

    actions.appendChild(fillBtn);
    actions.appendChild(copyPasswordBtn);

    if (credential.username && credential.username.trim()) {
      actions.appendChild(copyUsernameBtn);
    }

    item.appendChild(title);
    item.appendChild(meta);
    item.appendChild(origin);
    item.appendChild(actions);

    credentialsList.appendChild(item);
  }
}

async function loadStatus() {
  clearMessage();

  const result = await chrome.runtime.sendMessage({ type: "PG_GET_STATUS" });

  if (!result?.ok) {
    statusText.textContent = "Unavailable";
    sessionText.textContent = "-";
    showMessage(result?.error || "Failed to connect to PassGuard host", "error");
    return;
  }

  setStatusUi(result.data);
}

async function loadCredentials() {
  clearMessage();
  credentialsList.innerHTML = `<div class="empty">Loading...</div>`;

  const result = await chrome.runtime.sendMessage({
    type: "PG_GET_CREDENTIALS_FOR_ACTIVE_TAB"
  });

  if (!result?.ok) {
    originText.textContent = "-";
    renderCredentials([]);
    showMessage(result?.error || "Failed to load credentials", "error");
    return;
  }

  originText.textContent = result.origin || "-";

  const data = result.data;
  if (data?.status === "locked") {
    renderCredentials([]);
    showMessage("Vault is locked in PassGuard OS.", "error");
    return;
  }

  if (data?.status !== "ok") {
    renderCredentials([]);
    showMessage(data?.message || "Unknown host response", "error");
    return;
  }

  renderCredentials(data.credentials || []);

  if ((data.credentials || []).length > 0) {
    showMessage(
      "Credentials loaded. Autofill is available, but manual copy may be safer on unusual or sensitive login pages.",
      "info"
    );
  }
}

async function lockVault() {
  clearMessage();

  const result = await chrome.runtime.sendMessage({ type: "PG_LOCK_NOW" });

  if (!result?.ok) {
    showMessage(result?.error || "Failed to lock vault", "error");
    return;
  }

  renderCredentials([]);
  await loadStatus();
  showMessage("Vault locked.", "success");
}

refreshBtn.addEventListener("click", async () => {
  await loadStatus();
});

loadBtn.addEventListener("click", async () => {
  await loadStatus();
  await loadCredentials();
});

lockBtn.addEventListener("click", async () => {
  await lockVault();
});

(async function init() {
  await loadStatus();
})();