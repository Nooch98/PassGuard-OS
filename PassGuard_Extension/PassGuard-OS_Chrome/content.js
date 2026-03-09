function findVisibleInputs() {
  const inputs = Array.from(document.querySelectorAll("input"));

  return inputs.filter((input) => {
    const style = window.getComputedStyle(input);
    const hiddenByType = input.type === "hidden";
    const hiddenByStyle =
      style.display === "none" ||
      style.visibility === "hidden" ||
      input.offsetParent === null;

    return !hiddenByType && !hiddenByStyle && !input.disabled && !input.readOnly;
  });
}

function scoreUsernameField(input) {
  const haystack = [
    input.name || "",
    input.id || "",
    input.placeholder || "",
    input.autocomplete || "",
    input.ariaLabel || "",
    input.getAttribute("aria-label") || ""
  ]
    .join(" ")
    .toLowerCase();

  let score = 0;

  if (input.type === "email") score += 50;
  if (input.type === "text") score += 20;
  if (haystack.includes("user")) score += 40;
  if (haystack.includes("usuari")) score += 40;
  if (haystack.includes("email")) score += 40;
  if (haystack.includes("login")) score += 20;
  if (haystack.includes("identifier")) score += 20;
  if (input.autocomplete === "username") score += 60;

  return score;
}

function scorePasswordField(input) {
  const haystack = [
    input.name || "",
    input.id || "",
    input.placeholder || "",
    input.autocomplete || "",
    input.ariaLabel || "",
    input.getAttribute("aria-label") || ""
  ]
    .join(" ")
    .toLowerCase();

  let score = 0;

  if (input.type === "password") score += 100;
  if (haystack.includes("pass")) score += 30;
  if (input.autocomplete === "current-password") score += 50;

  return score;
}

function findBestFields() {
  const visibleInputs = findVisibleInputs();

  const usernameCandidates = visibleInputs
    .map((input) => ({ input, score: scoreUsernameField(input) }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score);

  const passwordCandidates = visibleInputs
    .map((input) => ({ input, score: scorePasswordField(input) }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score);

  return {
    username: usernameCandidates[0]?.input || null,
    password: passwordCandidates[0]?.input || null
  };
}

function setNativeValue(input, value) {
  const descriptor = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype,
    "value"
  );
  descriptor?.set?.call(input, value);

  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "PG_FILL_FORM") return;

  const credential = message.credential;
  if (!credential) {
    sendResponse?.({ ok: false, error: "MISSING_CREDENTIAL" });
    return;
  }

  const fields = findBestFields();

  let filled = false;

  if (fields.username && credential.username) {
    setNativeValue(fields.username, credential.username);
    filled = true;
  }

  if (fields.password && credential.password) {
    setNativeValue(fields.password, credential.password);
    filled = true;
  }

  sendResponse?.({ ok: true, filled });
});