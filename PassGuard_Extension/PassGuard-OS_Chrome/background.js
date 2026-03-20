const NATIVE_HOST_NAME = "com.passguard.os";

function sendNativeMessage(payload) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, payload, (response) => {
      if (chrome.runtime.lastError) {
        console.error("Native Error:", chrome.runtime.lastError.message);
        reject(new Error(chrome.runtime.lastError.message));
        return;
      }
      if (!response) {
        reject(new Error("EMPTY_NATIVE_RESPONSE"));
        return;
      }
      resolve(response);
    });
  });
}

function getSmartSearchTerm(url) {
  try {
    const parsed = new URL(url);
    const hostname = parsed.hostname.toLowerCase();
    let cleanHost = hostname.replace(/^www\./, '');
    const parts = cleanHost.split('.');
    if (parts.length >= 2) return parts[parts.length - 2];
    return cleanHost;
  } catch (e) { return ""; }
}

async function getActiveTab() {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  return tabs[0] || null;
}

function normalizeOrigin(url) {
  try { return new URL(url).origin; } catch (e) { return ""; }
}

chrome.commands.onCommand.addListener(async (command) => {
  if (command === "fill-credentials") {
    try {
      const tab = await getActiveTab();
      if (!tab?.id || !tab.url) return;

      const origin = normalizeOrigin(tab.url);
      const rawResponse = await sendNativeMessage({
        action: "get_credentials",
        origin: origin
      });

      const credentialObject = rawResponse?.credentials?.[0];
      if (credentialObject?.username && credentialObject?.password) {
        chrome.tabs.sendMessage(tab.id, {
          type: "PG_FILL_FORM",
          credential: {
            username: credentialObject.username,
            password: credentialObject.password
          }
        }).catch(() => {});
      }
    } catch (err) {
      console.error("Command Error:", err);
    }
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "PG_SAVE_SUGGESTION") {
    chrome.runtime.sendNativeMessage('com.passguard.os', {
      action: "check_link_status",
      origin: message.payload.origin,
      platform: message.payload.platform
    }, (response) => {
      if (chrome.runtime.lastError) {
        return;
      }

      if (response && response.status === "NEED_CONFIRMATION") {
        chrome.tabs.sendMessage(sender.tab.id, {
          type: "PG_SHOW_LINK_BANNER",
          data: response
        });
      }
    });
  }

  if (request.type === "PG_CONFIRM_LINK") {
    chrome.runtime.sendNativeMessage('com.passguard.os', {
      action: "force_link_origin",
      account_id: request.account_id,
      origin: request.origin
    });
  }
  return true;
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    try {
      switch (message?.type) {
        case "PG_GET_STATUS": {
          const response = await sendNativeMessage({ action: "status" });
          sendResponse({ ok: true, data: response });
          break;
        }

        case "PG_GET_CREDENTIALS_FOR_ACTIVE_TAB": {
          const tab = await getActiveTab();
          if (!tab?.url) return sendResponse({ ok: false, error: "NO_TAB_URL" });
        
          const searchTerm = getSmartSearchTerm(tab.url);
          const origin = normalizeOrigin(tab.url);
        
          const response = await sendNativeMessage({
            action: "get_credentials",
            origin: origin,
            searchTerm: searchTerm 
          });
          sendResponse({ ok: true, data: response });
          break;
        }

        case "PG_AUTOFILL_CREDENTIAL": {
          const tab = await getActiveTab();
          if (!tab?.id) return sendResponse({ ok: false, error: "NO_ACTIVE_TAB" });

          const contentResponse = await chrome.tabs.sendMessage(tab.id, {
            type: "PG_FILL_FORM",
            credential: message.credential,
          });
          sendResponse({ ok: true, data: contentResponse });
          break;
        }

        case "PG_LOCK_NOW": {
          const response = await sendNativeMessage({ action: "lock_now" });
          sendResponse({ ok: true, data: response });
          break;
        }

        case "PG_SAVE_SUGGESTION": {
          const response = await sendNativeMessage({
            action: "check_link_status",
            ...message.payload
          });
        
          if (response.status === "NEED_CONFIRMATION" && sender.tab?.id) {
            chrome.tabs.sendMessage(sender.tab.id, {
              type: "PG_SHOW_LINK_BANNER",
              data: response
            });
          }
          sendResponse({ ok: true, status: response.status });
          break;
        }

        case "PG_CONFIRM_LINK": {
          const response = await sendNativeMessage({
            action: "force_link_origin",
            account_id: message.account_id,
            origin: message.origin
          });
          sendResponse({ ok: true, data: response });
          break;
        }

        default:
          sendResponse({ ok: false, error: "UNKNOWN_MESSAGE_TYPE" });
      }
    } catch (err) {
      console.error("Background Async Error:", err);
      sendResponse({
        ok: false,
        error: err?.message || "UNKNOWN_BACKGROUND_ERROR",
      });
    }
  })();

  return true;
});
