// Runs at documentEnd in the isolated .defaultClient content world for Marketplace.app and Groups.app.

(function () {
  "use strict";

  function postToNative(payload) {
    try {
      window.webkit?.messageHandlers?.hubBridge?.postMessage(payload);
    } catch (_) {}
  }

  function isVisible(el) {
    if (!el) return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  function normalizePath(p) {
    if (!p) return "/";
    return p.endsWith("/") && p.length > 1 ? p.slice(0, -1) : p;
  }

  // Forward Web Notification shim events to native UNUserNotificationCenter
  function observeWebNotifications() {
    const root = document.documentElement;
    if (!root) return;
    let lastRaw = "";
    const obs = new MutationObserver(() => {
      const raw = root.getAttribute("data-hub-web-notif") || "";
      if (raw && raw !== lastRaw) {
        lastRaw = raw;
        try {
          const parsed = JSON.parse(raw);
          postToNative({
            type: "notification",
            title: parsed.title,
            body: parsed.body,
            tag: parsed.tag || "hub-notif",
            url: location.href,
          });
        } catch (_) {}
      }
    });
    obs.observe(root, { attributes: true, attributeFilter: ["data-hub-web-notif"] });
  }

  window.__HUB_BRIDGE = {
    navigateSection(targetURLString) {
      try {
        const targetURL = new URL(targetURLString, location.origin);
        const targetNorm = normalizePath(targetURL.pathname);

        // Prefer clicking an existing in-page link so React transitions instantaneously without full reload
        const matchingLink = [...document.querySelectorAll("a[href]")].find((a) => {
          if (!isVisible(a)) return false;
          try {
            const candidate = new URL(a.href, location.origin);
            return (
              candidate.origin === targetURL.origin &&
              normalizePath(candidate.pathname) === targetNorm &&
              !candidate.search
            );
          } catch (_) {
            return false;
          }
        });

        if (matchingLink) {
          matchingLink.click();
          return true;
        }
      } catch (_) {}

      location.assign(targetURLString);
      return true;
    },

    focusSearch() {
      const candidates = [
        ...document.querySelectorAll(
          '[role="navigation"] input[type="search"], [role="main"] input[type="search"], input[placeholder*="Marketplace" i], input[placeholder*="groups" i], input[type="search"], input[role="combobox"]'
        ),
      ].filter(isVisible);

      if (candidates.length > 0) {
        const input = candidates[0];
        input.click();
        input.focus();
        if (typeof input.select === "function") input.select();
        return true;
      }

      // Some Group views collapse in-group search behind a magnifying glass button
      const searchButton = [
        ...document.querySelectorAll('[role="main"] [aria-label*="Search" i], [aria-label*="Search" i]'),
      ].find(isVisible);
      if (searchButton) {
        searchButton.click();
        return true;
      }
      return false;
    },

    triggerPrimaryAction(mode, fallbackURL) {
      if (mode === "groups") {
        // If viewing a specific group, open the "Write something..." post composer right inside that group
        const path = location.pathname.toLowerCase();
        const isSpecificGroup =
          path.startsWith("/groups/") &&
          !/^\/groups\/(feed|discover|joins|create|notifications)(\/|$)/.test(path);

        if (isSpecificGroup) {
          const composerPrompt = [...document.querySelectorAll('[role="main"] [role="button"]')].find(
            (btn) => {
              if (!isVisible(btn)) return false;
              const txt = (btn.innerText || btn.getAttribute("aria-label") || "").trim();
              return /^(write something|create (a )?(public )?post|start a discussion|ask a question)/i.test(
                txt
              );
            }
          );
          if (composerPrompt) {
            composerPrompt.click();
            return true;
          }
        }
      } else if (mode === "marketplace") {
        const createLink = [...document.querySelectorAll('a[href*="/marketplace/create"]')].find(
          isVisible
        );
        if (createLink) {
          createLink.click();
          return true;
        }
      }

      location.assign(fallbackURL);
      return true;
    },
  };

  observeWebNotifications();
})();
