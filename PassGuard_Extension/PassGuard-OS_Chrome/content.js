function neutralizeBrowserManager() {
  const inputs = document.querySelectorAll('input');
  inputs.forEach(input => {
      input.setAttribute('autocomplete', 'off-passguard-' + Math.random().toString(36).substring(7));
      input.setAttribute('data-pg-managed', 'true');

      input.style.setProperty('background-image', 'none', 'important');
  });
}

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
      input.name, input.id, input.placeholder, input.autocomplete,
      ariaLabel, label?.innerText || "", parent?.innerText?.substring(0, 50) || ""
  ].join(" ").toLowerCase();
}

function scoreUsernameField(input) {
  const haystack = getContextText(input);
  let score = 0;
  if (input.type === "email") score += 60;
  if (input.type === "text") score += 20;
  const highPriority = ["user", "usuari", "email", "correo", "login", "nickname"];
  highPriority.forEach(k => { if (haystack.includes(k)) score += 50; });
  if (input.autocomplete === "username" || input.autocomplete === "email") score += 100;
  if (input.type === "password") score = 0; 
  return score;
}

function scorePasswordField(input) {
  const haystack = getContextText(input);
  let score = 0;
  if (input.type === "password") score += 150;
  const keywords = ["pass", "contra", "clave", "pw"];
  keywords.forEach(k => { if (haystack.includes(k)) score += 40; });
  return score;
}

function findBestFields() {
  const visibleInputs = findVisibleInputs();
  const usernameCandidates = visibleInputs.map(i => ({ input: i, score: scoreUsernameField(i) })).filter(x => x.score > 20).sort((a,b) => b.score - a.score);
  const passwordCandidates = visibleInputs.map(i => ({ input: i, score: scorePasswordField(i) })).filter(x => x.score > 20).sort((a,b) => b.score - a.score);
  return { username: usernameCandidates[0]?.input || null, password: passwordCandidates[0]?.input || null };
}

function setNativeValue(input, value) {
  const descriptor = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value");
  descriptor?.set?.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));
}

function getNormalizedPlatform() {
  let rawTitle = document.title || "";
  const genericTitles = ["login", "sign in", "inicio de sesión", "acceder", "auth"];
  const firstWord = rawTitle.split(/[-|–|:| ]/)[0].trim().toLowerCase();
  let platformName = (genericTitles.includes(firstWord) || rawTitle.length < 3) ? 
      (window.location.hostname.split('.').reverse()[1] || window.location.hostname) : firstWord;
  return platformName.charAt(0).toUpperCase() + platformName.slice(1);
}

function handleCapture() {
  const fields = findBestFields();
  let currentUsername = fields.username ? fields.username.value : "";
  let currentPassword = fields.password ? fields.password.value : "";

  if (currentUsername && !currentPassword) {
      sessionStorage.setItem('pg_pending_username', currentUsername);
  }

  const savedUsername = sessionStorage.getItem('pg_pending_username');
  const finalUsername = currentUsername || savedUsername || "";

  if (currentPassword && currentPassword.length > 3) {
      neutralizeBrowserManager();
      
      chrome.runtime.sendMessage({
          type: "PG_SAVE_SUGGESTION",
          payload: {
              origin: window.location.origin,
              username: finalUsername,
              password: currentPassword,
              platform: getNormalizedPlatform()
          }
      }, () => {
          if (chrome.runtime.lastError) {
              setTimeout(handleCapture, 300);
          } else {
              sessionStorage.removeItem('pg_pending_username');
          }
      });
  }
}

function showPassGuardBanner(data) {
  if (document.getElementById('pg-upsert-banner')) return;

  const banner = document.createElement('div');
  banner.id = 'pg-upsert-banner';

  const styleTag = document.createElement('style');
  styleTag.textContent = `
      @keyframes pgSlide { from { transform: translateX(120%); } to { transform: translateX(0); } }
      .pg-btn { transition: all 0.2s; border: 1px solid #00FBFF; cursor: pointer; padding: 10px; font-weight: bold; font-family: 'Courier New', monospace; border-radius: 4px; flex: 1; }
      .pg-btn-primary { background: #00FBFF; color: #000; }
      .pg-btn-primary:hover { background: #000; color: #00FBFF; box-shadow: 0 0 10px #00FBFF; }
      .pg-btn-secondary { background: transparent; color: #fff; border-color: #555; }
      .pg-btn-secondary:hover { border-color: #fff; }
  `;
  document.head.appendChild(styleTag);

  banner.style.cssText = `
      position: fixed !important; top: 20px !important; right: 20px !important;
      z-index: 2147483647 !important; background: #0A0A0E !important;
      border: 2px solid #00FBFF !important; color: white !important;
      padding: 24px !important; font-family: 'Courier New', monospace !important;
      border-radius: 12px !important; box-shadow: 0 10px 40px rgba(0,0,0,0.8), 0 0 15px rgba(0,251,255,0.4) !important;
      width: 320px !important; animation: pgSlide 0.4s ease-out !important;
  `;

  banner.innerHTML = `
      <div style="display: flex; align-items: center; margin-bottom: 16px;">
          <div style="width: 10px; height: 10px; background: #00FBFF; border-radius: 50%; margin-right: 10px; box-shadow: 0 0 8px #00FBFF;"></div>
          <span style="letter-spacing: 2px; font-size: 12px; color: #00FBFF; font-weight: bold;">PASSGUARD_OS // LINK_ACCOUNT</span>
      </div>
      <div style="font-size: 15px; margin-bottom: 20px; line-height: 1.5; color: #E0E0E0;">
          Link <span style="color: #00FBFF; font-weight: bold;">${data.platform}</span> with this origin?
          <div style="font-size: 11px; margin-top: 8px; color: #888; overflow: hidden; text-overflow: ellipsis; text-transform: uppercase;">ORIGIN: ${data.new_origin}</div>
      </div>
      <div style="display: flex; gap: 12px;">
          <button id="pg-accept" class="pg-btn pg-btn-primary">LINK ACCOUNT</button>
          <button id="pg-deny" class="pg-btn pg-btn-secondary">IGNORE</button>
      </div>
  `;

  (document.body || document.documentElement).appendChild(banner);

  banner.querySelector('#pg-accept').onclick = () => {
      chrome.runtime.sendMessage({ type: "PG_CONFIRM_LINK", account_id: data.account_id, origin: data.new_origin });
      banner.remove();
  };
  banner.querySelector('#pg-deny').onclick = () => banner.remove();
}

document.addEventListener("mousedown", (e) => {
  if (e.target.closest('button, input[type="submit"], [role="button"]')) handleCapture();
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Enter") setTimeout(handleCapture, 200);
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "PG_SHOW_LINK_BANNER") {
      showPassGuardBanner(message.data);
  }

  if (message?.type === "PG_FILL_FORM") {
      const { username, password } = message.credential || {};
      const fields = findBestFields();
      if (fields.username && username) setNativeValue(fields.username, username);
      if (fields.password && password) setNativeValue(fields.password, password);
      neutralizeBrowserManager();
      sendResponse?.({ ok: true });
  }
  return true;
});
