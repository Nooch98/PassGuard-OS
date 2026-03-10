const NATIVE_HOST_NAME = "com.passguard.os";

function sendNativeMessage(payload) {

  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, payload, (response) => {
      if (chrome.runtime.lastError) {
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

async function getActiveTab() {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  return tabs[0] || null;
}

function normalizeOrigin(url) {
  try {
    return new URL(url).origin;
  } catch (e) {
    return "";
  }
}

chrome.commands.onCommand.addListener(async (command) => {
  if (command === "fill-credentials") {
    
    try {
      const tab = await getActiveTab();
      if (!tab?.id) {
        return;
      }
      const origin = normalizeOrigin(tab.url);
      const rawResponse = await sendNativeMessage({
        action: "get_credentials",
        origin: origin
      });
      const credentialObject = rawResponse?.credentials?.[0];
      if (credentialObject && credentialObject.username && credentialObject.password) {
        try {
          const response = await chrome.tabs.sendMessage(tab.id, {
            type: "PG_FILL_FORM",
            credential: {
              username: credentialObject.username,
              password: credentialObject.password
            }
          });
        } catch (sendMessageError) {
        }
      } else {
      }
    } catch (err) {
    }
  }
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

          if (!tab?.url) {
            sendResponse({ ok: false, error: "NO_ACTIVE_TAB_URL" });
            return;
          }

          const origin = normalizeOrigin(tab.url);
          if (!origin) {
            sendResponse({ ok: false, error: "INVALID_ORIGIN" });
            return;
          }

          const response = await sendNativeMessage({
            action: "get_credentials",
            origin,
          });

          sendResponse({ ok: true, data: response, origin });
          break;
        }

        case "PG_AUTOFILL_CREDENTIAL": {
          const tab = await getActiveTab();

          if (!tab?.id) {
            sendResponse({ ok: false, error: "NO_ACTIVE_TAB" });
            return;
          }

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

        default:
          sendResponse({ ok: false, error: "UNKNOWN_MESSAGE_TYPE" });
      }
    } catch (err) {
      sendResponse({
        ok: false,
        error: err?.message || "UNKNOWN_BACKGROUND_ERROR",
      });
    }
  })();

  return true;
});
