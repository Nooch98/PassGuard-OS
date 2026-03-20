function findVisibleInputs(doc = document) {
  let inputs = Array.from(doc.querySelectorAll("input"));
  
  const allElements = doc.querySelectorAll('*');
  allElements.forEach(el => {
    if (el.shadowRoot) {
      inputs = inputs.concat(findVisibleInputs(el.shadowRoot));
    }
  });

  return inputs.filter((input) => {
    const style = window.getComputedStyle(input);
    const rect = input.getBoundingClientRect();

    const isHidden = input.type === "hidden" || 
                     style.display === "none" || 
                     style.visibility === "hidden" || 
                     style.opacity === "0" ||
                     rect.width === 0 || 
                     rect.height === 0;

    return !isHidden && !input.disabled && !input.readOnly;
  });
}

function getContextText(input) {
  const parent = input.parentElement;
  const label = document.querySelector(`label[for="${input.id}"]`);
  const ariaLabel = input.getAttribute("aria-label") || input.getAttribute("aria-labelledby") || "";
  
  return [
    input.name,
    input.id,
    input.placeholder,
    input.autocomplete,
    ariaLabel,
    label?.innerText || "",
    parent?.innerText?.substring(0, 50) || ""
  ].join(" ").toLowerCase();
}

function scoreUsernameField(input) {
  const haystack = getContextText(input);
  let score = 0;

  if (input.type === "email") score += 60;
  if (input.type === "text") score += 20;

  const highPriority = ["user", "usuari", "email", "correo", "login", "nickname"];
  const mediumPriority = ["identif", "cuenta", "account", "alias"];
  
  highPriority.forEach(k => { if (haystack.includes(k)) score += 50; });
  mediumPriority.forEach(k => { if (haystack.includes(k)) score += 25; });

  if (input.autocomplete === "username" || input.autocomplete === "email") score += 100;

  if (haystack.includes("search") || haystack.includes("buscar")) score -= 40;
  if (input.type === "password") score = 0; 

  return score;
}

function scorePasswordField(input) {
  const haystack = getContextText(input);
  let score = 0;

  if (input.type === "password") score += 150;
  if (input.autocomplete === "current-password" || input.autocomplete === "new-password") score += 100;
  
  const keywords = ["pass", "contra", "clave", "pw", "mfa", "pin"];
  keywords.forEach(k => { if (haystack.includes(k)) score += 40; });

  return score;
}

function findBestFields() {
  const visibleInputs = findVisibleInputs();

  const usernameCandidates = visibleInputs
    .map((input) => ({ input, score: scoreUsernameField(input) }))
    .filter((x) => x.score > 20)
    .sort((a, b) => b.score - a.score);

  const passwordCandidates = visibleInputs
    .map((input) => ({ input, score: scorePasswordField(input) }))
    .filter((x) => x.score > 20)
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

function handleCapture() {
  const fields = findBestFields();
  const passInput = fields.password || document.querySelector('input[type="password"]');

  if (passInput && passInput.value.length > 3) {
    const payload = {
      origin: window.location.origin,
      username: fields.username ? fields.username.value : "",
      password: passInput.value,
      platform: (document.title || window.location.hostname).split(/[-|–]/)[0].trim()
    };

    chrome.runtime.sendMessage({
      type: "PG_SAVE_SUGGESTION",
      payload: payload
    });
  }
}

document.addEventListener("mousedown", (e) => {
  const btn = e.target.closest('button, input[type="submit"]');
  if (btn) {
    handleCapture(); 
  }
});

document.addEventListener("click", (e) => {
  const btn = e.target.closest('button, input[type="submit"], input[type="button"]');
  if (btn) {
    const text = (btn.innerText || btn.value || "").toLowerCase();
    const actions = ["log", "entrar", "sign", "access", "continuar", "next", "siguiente"];
    if (actions.some(word => text.includes(word))) {
      setTimeout(handleCapture, 200);
    }
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "PG_SHOW_LINK_BANNER") {
    const { platform, new_origin, account_id } = message.data;

    if (document.getElementById('pg-upsert-banner')) return;

    const banner = document.createElement('div');
    banner.id = 'pg-upsert-banner';
    banner.innerHTML = `
      <div style="position: fixed; top: 10px; right: 10px; z-index: 2147483647; 
                  background: #0A0A0E; border: 1px solid #00FBFF; color: white; 
                  padding: 15px; font-family: monospace; border-radius: 4px;
                  box-shadow: 0 0 15px rgba(0,251,255,0.3); min-width: 250px;">
        <span style="color: #00FBFF">> LINK_DETECTED:</span> Link ${platform} to ${new_origin}?
        <div style="margin-top: 10px; display: flex; gap: 10px;">
          <button id="pg-accept" style="background: #00FBFF; border: none; cursor: pointer; padding: 5px 12px; font-weight: bold; color: black;">YES</button>
          <button id="pg-deny" style="background: transparent; border: 1px solid white; color: white; cursor: pointer; padding: 5px 12px;">NO</button>
        </div>
      </div>
    `;
    document.body.appendChild(banner);

    banner.querySelector('#pg-accept').onclick = () => {
      chrome.runtime.sendMessage({ 
        type: "PG_CONFIRM_LINK", 
        account_id, 
        origin: new_origin 
      });
      banner.remove();
    };
    banner.querySelector('#pg-deny').onclick = () => banner.remove();
  }

  if (message?.type === "PG_FILL_FORM") {
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
  }

  return true;
});
