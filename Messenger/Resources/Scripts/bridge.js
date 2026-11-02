// Runs at documentEnd in the isolated .defaultClient content world.
// Observes Messenger's conversation sidebar (on both facebook.com/messages and messenger.com),
// tracks unread counts, detects incoming messages for native macOS notifications, tracks active
// conversation URLs, and exposes keyboard shortcut actions solely to Swift.

(function () {
  "use strict";

  const ALT_EMOJI_MAP = {
    "(Y)": "👍",
    "<3": "❤️",
    "❤": "❤️",
  };

  const SELF_PREFIXES = [
    "you:",
    "you sent",
    "you reacted",
    "you unsent",
    "you replied",
    "you missed",
    "you called",
  ];

  const SCREEN_READER_UNREAD_RE =
    /\b(unread message|unread|nieprzeczytana|ungelesene|non lu|no leído)\b/i;

  function postToNative(payload) {
    try {
      window.webkit?.messageHandlers?.messengerBridge?.postMessage(payload);
    } catch (_) {}
  }

  function isVisible(el) {
    if (!el) return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  // Extract visible text while turning emoji <img alt="..."> into emoji characters
  // and skipping screen-reader-only announcement nodes.
  function extractCleanText(node) {
    if (!node) return "";
    let out = "";
    for (const child of node.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) {
        out += child.textContent || "";
      } else if (child.nodeType === Node.ELEMENT_NODE) {
        if (child.classList.contains("x1i1rx1s")) continue;
        const style = window.getComputedStyle(child);
        if (
          style.display === "none" ||
          style.visibility === "hidden" ||
          (parseFloat(style.width) <= 1 &&
            parseFloat(style.height) <= 1 &&
            style.overflow === "hidden")
        ) {
          continue;
        }
        if (child.tagName === "IMG") {
          const alt = child.getAttribute("alt") || "";
          if (alt.length <= 12) {
            out += ALT_EMOJI_MAP[alt] || alt;
          }
        } else {
          out += extractCleanText(child);
        }
      }
    }
    return out;
  }

  function extractThreadId(href) {
    if (!href) return "";
    const match = href.match(/\/t\/([^/?#]+)/);
    return match ? match[1] : "";
  }

  function resolveAbsoluteURL(raw) {
    if (!raw) return "";
    try {
      return new URL(raw, location.href).href;
    } catch (_) {
      return "";
    }
  }

  function hasBlueUnreadDotElement(rowRoot) {
    const rowRect = rowRoot.getBoundingClientRect();
    if (rowRect.width <= 0) return false;
    const candidates = rowRoot.querySelectorAll('[role="button"] span, [role="button"] div, span, div');
    for (const el of candidates) {
      if (el.children.length > 0) continue;
      const r = el.getBoundingClientRect();
      // Unread dot is a small ~8–14px circle on the right side of the chat row
      if (r.width < 6 || r.width > 16 || Math.abs(r.width - r.height) > 2) continue;
      if (r.left < rowRect.left + rowRect.width * 0.65) continue;

      const style = window.getComputedStyle(el);
      const radius = parseFloat(style.borderRadius) || 0;
      if (radius < r.width * 0.4 && style.borderRadius !== "50%") continue;

      const bg = style.backgroundColor || "";
      const m = bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/);
      if (!m) continue;
      const red = parseInt(m[1], 10);
      const green = parseInt(m[2], 10);
      const blue = parseInt(m[3], 10);
      const alpha = m[4] !== undefined ? parseFloat(m[4]) : 1.0;
      // Messenger's unread indicator is a vibrant blue/accent dot (high blue channel, non-neutral)
      if (alpha > 0.5 && blue > 180 && blue > red + 40) {
        return true;
      }
    }
    return false;
  }

  function detectRowUnread(rowRoot, link) {
    // 1. Explicit ARIA or known unread dot class (.x1spa7qu) inside the row
    if (
      rowRoot.querySelector(
        '[aria-label*="Mark as read" i], [aria-label*="Unread" i], [role="button"] .x1spa7qu, .x1spa7qu'
      )
    ) {
      return true;
    }

    // 2. Screen-reader unread prefix anywhere inside the row
    const fullText = rowRoot.textContent || "";
    if (SCREEN_READER_UNREAD_RE.test(fullText)) {
      return true;
    }

    // 3. Geometric/computed-style blue dot check on the right side of the row
    if (hasBlueUnreadDotElement(rowRoot)) {
      return true;
    }

    // 4. Computed font-weight check: in Messenger, unread rows bold the message snippet (second dir="auto" block)
    const dirAutoBlocks = [...link.querySelectorAll('span[dir="auto"]')].filter(
      (node) => !(node.parentElement && node.parentElement.closest('span[dir="auto"]'))
    );
    if (dirAutoBlocks.length >= 2) {
      const snippetBlock = dirAutoBlocks[1];
      const weightNodes = [snippetBlock, ...snippetBlock.querySelectorAll("span")];
      for (const node of weightNodes) {
        if (!(node.textContent || "").trim()) continue;
        const weight = parseInt(window.getComputedStyle(node).fontWeight, 10);
        if (!Number.isNaN(weight) && weight >= 600) {
          return true;
        }
      }
    }

    return false;
  }

  function detectRowMuted(rowRoot) {
    if (
      rowRoot.querySelector(
        '[aria-label*="Muted" i], [aria-label*="Unmute" i], svg.x14rh7hd'
      )
    ) {
      return true;
    }
    return false;
  }

  function parseRowSenderAndSnippet(link) {
    const candidateLines = [];
    const autoNodes = link.querySelectorAll('span[dir="auto"]');
    for (const node of autoNodes) {
      if (node.parentElement && node.parentElement.closest('span[dir="auto"]')) continue;
      const cleaned = extractCleanText(node).replace(/\s+/g, " ").trim();
      if (cleaned) candidateLines.push(cleaned);
    }

    if (candidateLines.length >= 2) {
      return {
        sender: candidateLines[0],
        snippet: sanitizeSnippet(candidateLines[1]),
      };
    }

    const rawLines = extractCleanText(link)
      .split("\n")
      .map((l) => l.replace(/\s+/g, " ").trim())
      .filter(Boolean);

    return {
      sender: rawLines[0] || "Messenger",
      snippet: sanitizeSnippet(rawLines[1] || ""),
    };
  }

  function sanitizeSnippet(raw) {
    if (!raw) return "";
    return raw
      .replace(/^unread message:\s*/i, "")
      .replace(/\s*·\s*(\d+\s*[smhdwy]|just now|now|\d{1,2}:\d{2}(\s*[ap]m)?)$/i, "")
      .trim();
  }

  function findConversationRows() {
    // Query across ALL [role="navigation"] and [role="grid"] containers in the document
    // (on facebook.com/messages there are multiple [role="navigation"] elements).
    const links = [
      ...document.querySelectorAll(
        '[role="navigation"] [role="row"] a[href*="/t/"], [role="grid"] a[href*="/t/"], [role="navigation"] a[href*="/t/"], a[href*="/messages/t/"], a[href*="/messages/e2ee/t/"]'
      ),
    ].filter((a) => {
      if (!isVisible(a)) return false;
      const rect = a.getBoundingClientRect();
      return rect.left < Math.max(520, window.innerWidth * 0.65);
    });

    const rows = [];
    const seen = new Set();

    for (const link of links) {
      const href = link.getAttribute("href") || "";
      const threadId = extractThreadId(href);
      if (!threadId || seen.has(threadId)) continue;

      const mediaEl = link.querySelector("img, image");
      if (!mediaEl) continue;

      seen.add(threadId);
      const rowRoot = link.closest('[role="row"]') || link.parentElement || link;
      const { sender, snippet } = parseRowSenderAndSnippet(link);
      const avatarRaw =
        mediaEl.currentSrc ||
        mediaEl.src ||
        mediaEl.getAttribute("href") ||
        mediaEl.getAttribute("xlink:href") ||
        "";

      rows.push({
        index: rows.length,
        threadId,
        href: resolveAbsoluteURL(href),
        rawHref: href,
        link,
        top: link.getBoundingClientRect().top,
        sender,
        snippet,
        avatarURL: resolveAbsoluteURL(avatarRaw),
        isUnread: detectRowUnread(rowRoot, link),
        isMuted: detectRowMuted(rowRoot),
      });
    }

    rows.sort((a, b) => a.top - b.top);
    rows.forEach((r, idx) => {
      r.index = idx;
    });
    return rows;
  }

  function isSelfSnippet(snippet) {
    const lower = (snippet || "").trim().toLowerCase();
    return SELF_PREFIXES.some((prefix) => lower.startsWith(prefix));
  }

  function currentActiveThreadId() {
    return extractThreadId(location.pathname);
  }

  let snapshots = null;
  let lastBadgeCount = -1;
  let lastReportedConversation = "";
  let scanTimer = null;

  function reportActiveConversationIfChanged() {
    const path = location.pathname || "";
    if (path.includes("/t/")) {
      const full = location.origin + path;
      if (full !== lastReportedConversation) {
        lastReportedConversation = full;
        postToNative({ type: "activeConversation", url: full });
      }
    }
  }

  function parseTitleCount() {
    const m = (document.title || "").match(/^\((\d+)\)/);
    return m ? parseInt(m[1], 10) : null;
  }

  function computeGlobalUnreadDotsCount() {
    // Fast global check for unread dot indicators across the chat list grid
    const grid =
      document.querySelector('[role="navigation"] [role="grid"]') ||
      document.querySelector('[role="grid"]');
    if (!grid) return 0;
    const explicitDots = grid.querySelectorAll(
      '[role="row"] [role="button"] .x1spa7qu, [role="row"] [aria-label*="Mark as read" i], [role="row"] [aria-label*="Unread" i]'
    );
    return explicitDots.length;
  }

  function scanConversations(trigger) {
    reportActiveConversationIfChanged();

    const rows = findConversationRows();
    if (rows.length === 0) {
      const titleCount = parseTitleCount();
      if (titleCount !== null && titleCount !== lastBadgeCount) {
        lastBadgeCount = titleCount;
        postToNative({ type: "badge", count: titleCount });
      }
      return;
    }

    const rowUnreadCount = rows.filter((r) => r.isUnread && !r.isMuted).length;
    const dotUnreadCount = computeGlobalUnreadDotsCount();
    const unreadCount = Math.max(rowUnreadCount, dotUnreadCount);

    if (unreadCount !== lastBadgeCount) {
      lastBadgeCount = unreadCount;
      postToNative({ type: "badge", count: unreadCount });
    }

    const isInitialSnapshot = snapshots === null;
    if (isInitialSnapshot) {
      snapshots = new Map();
    }

    const activeThread = currentActiveThreadId();
    const windowFocused = document.hasFocus() && document.visibilityState === "visible";

    for (const row of rows) {
      const prev = snapshots.get(row.threadId);
      snapshots.set(row.threadId, {
        sender: row.sender,
        snippet: row.snippet,
        isUnread: row.isUnread,
        isMuted: row.isMuted,
      });

      if (isInitialSnapshot) continue;
      if (row.isMuted) continue;
      if (!row.snippet || isSelfSnippet(row.snippet)) continue;

      if (windowFocused && activeThread && row.threadId === activeThread) {
        continue;
      }

      let shouldNotify = false;
      if (row.isUnread) {
        if (!prev) {
          shouldNotify = row.index === 0;
        } else if (!prev.isUnread || prev.snippet !== row.snippet) {
          shouldNotify = true;
        }
      } else if (trigger === "sound" && prev && prev.snippet !== row.snippet && row.index === 0) {
        shouldNotify = true;
      }

      if (shouldNotify) {
        postToNative({
          type: "notification",
          threadId: row.threadId,
          href: row.href,
          title: row.sender || "Messenger",
          body: row.snippet,
          icon: row.avatarURL,
        });
      }
    }
  }

  function scheduleScan(trigger, delayMs = 120) {
    clearTimeout(scanTimer);
    scanTimer = setTimeout(() => scanConversations(trigger), delayMs);
  }

  // Observe chat list DOM mutations and upgrade to [role="navigation"] [role="grid"] as soon as React mounts it
  function attachSidebarObserver() {
    let navObserver = null;
    let currentTarget = null;

    const ensureAttached = () => {
      const preferredGrid =
        document.querySelector('[role="navigation"] [role="grid"]') ||
        document.querySelector('[role="grid"]');
      const target = preferredGrid || document.body;

      if (target && target !== currentTarget) {
        navObserver?.disconnect();
        currentTarget = target;
        snapshots = null;
        navObserver = new MutationObserver(() => scheduleScan("mutation", 120));
        navObserver.observe(target, {
          subtree: true,
          childList: true,
          characterData: true,
          attributes: true,
          attributeFilter: ["aria-selected", "aria-label", "class", "style"],
        });
        scheduleScan("attach", 60);
      }
    };

    ensureAttached();
    const bodyObserver = new MutationObserver(() => {
      const preferredGrid =
        document.querySelector('[role="navigation"] [role="grid"]') ||
        document.querySelector('[role="grid"]');
      if (
        !currentTarget ||
        !document.contains(currentTarget) ||
        (preferredGrid && currentTarget !== preferredGrid)
      ) {
        ensureAttached();
      }
      reportActiveConversationIfChanged();
    });
    if (document.body) {
      bodyObserver.observe(document.body, { childList: true, subtree: true });
    }

    // Periodic 2.5s safety sync so CSS/class-only unread transitions never get missed
    setInterval(() => scheduleScan("poll", 0), 2500);
  }

  function attachRootSignalObserver() {
    const root = document.documentElement;
    if (!root) return;

    let lastSoundTs = "";
    let lastWebNotifRaw = "";

    const rootObserver = new MutationObserver((mutations) => {
      for (const m of mutations) {
        if (m.attributeName === "data-msgr-sound-ts") {
          const ts = root.getAttribute("data-msgr-sound-ts") || "";
          if (ts && ts !== lastSoundTs) {
            lastSoundTs = ts;
            scheduleScan("sound", 220);
          }
        } else if (m.attributeName === "data-msgr-web-notif") {
          const raw = root.getAttribute("data-msgr-web-notif") || "";
          if (raw && raw !== lastWebNotifRaw) {
            lastWebNotifRaw = raw;
            try {
              const parsed = JSON.parse(raw);
              postToNative({
                type: "notification",
                threadId: parsed.tag || "web-notif",
                href: location.href,
                title: parsed.title || "Messenger",
                body: parsed.body || "",
                icon: resolveAbsoluteURL(parsed.icon || ""),
              });
            } catch (_) {}
          }
        }
      }
    });

    rootObserver.observe(root, {
      attributes: true,
      attributeFilter: ["data-msgr-sound-ts", "data-msgr-web-notif"],
    });
  }

  window.__MESSENGER_BRIDGE = {
    newMessage() {
      const composeButton = [...document.querySelectorAll("[aria-label]")].find((el) => {
        if (!isVisible(el)) return false;
        const label = (el.getAttribute("aria-label") || "").trim();
        return /^(new message|compose|write a message)/i.test(label);
      });
      if (composeButton) {
        composeButton.click();
        return true;
      }

      const composeLink = [
        ...document.querySelectorAll('a[href="/messages/new/"], a[href="/messages/new"], a[href*="/new"]'),
      ].find(isVisible);
      if (composeLink) {
        composeLink.click();
        return true;
      }

      const targetPath = location.hostname.includes("facebook.com") ? "/messages/new/" : "/new/";
      history.pushState(null, "", targetPath);
      window.dispatchEvent(new PopStateEvent("popstate", { state: null }));
      return true;
    },

    focusSearch() {
      const searchInput = [
        ...document.querySelectorAll(
          '[role="navigation"] input[type="search"], [role="navigation"] input[role="combobox"], input[placeholder*="Messenger" i], input[type="search"]'
        ),
      ].find(isVisible);
      if (!searchInput) return false;
      searchInput.click();
      searchInput.focus();
      if (typeof searchInput.select === "function") searchInput.select();
      return true;
    },

    openChat(oneBasedIndex) {
      const rows = findConversationRows();
      const target = rows[oneBasedIndex - 1];
      if (!target) return false;
      target.link.click();
      return true;
    },

    openThread(hrefOrThreadId) {
      if (!hrefOrThreadId) return false;
      const tid = extractThreadId(hrefOrThreadId) || hrefOrThreadId;
      const matchingLink = [...document.querySelectorAll('a[href*="/t/"]')].find(
        (a) => extractThreadId(a.getAttribute("href") || "") === tid
      );
      if (matchingLink) {
        matchingLink.click();
        return true;
      }
      if (hrefOrThreadId.startsWith("http")) {
        location.assign(hrefOrThreadId);
      } else {
        const prefix = location.hostname.includes("facebook.com") ? "/messages/t/" : "/t/";
        location.assign(prefix + encodeURIComponent(tid) + "/");
      }
      return true;
    },
  };

  attachRootSignalObserver();
  attachSidebarObserver();
})();
