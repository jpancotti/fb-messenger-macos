// Runs at documentStart in the .page content world for Marketplace.app and Groups.app.
// 1. Disables SharedWorker so realtime updates never stall when macOS reaps background worker processes.
// 2. Routes short static.fbcdn.net ping sounds through Web Audio + suspends idle AudioContexts.
// 3. Shims window.Notification & navigator.permissions.
// 4. Tags <html data-hub-mode="active"|"auth"> so chrome-stripping CSS never hides login/2FA UI.

(function () {
  "use strict";

  if ("SharedWorker" in window) {
    try {
      delete window.SharedWorker;
    } catch (_) {}
    if ("SharedWorker" in window) {
      try {
        Object.defineProperty(window, "SharedWorker", {
          value: undefined,
          configurable: true,
          writable: true,
        });
      } catch (_) {}
    }
  }

  function updateHubMode() {
    const root = document.documentElement;
    if (!root) return;
    const host = (location.hostname || "").toLowerCase();
    const path = location.pathname || "/";

    let mode = "other";
    if (host === "facebook.com" || host.endsWith(".facebook.com")) {
      const isAuth = /^\/(login|checkpoint|recover|two_step_verification|authn|auth|cookie|privacy\/consent|dialog)/i.test(
        path
      );
      mode = isAuth ? "auth" : "active";
    } else if (host === "messenger.com" || host.endsWith(".messenger.com")) {
      mode = "active";
    }

    if (root.getAttribute("data-hub-mode") !== mode) {
      root.setAttribute("data-hub-mode", mode);
    }
  }

  updateHubMode();

  for (const method of ["pushState", "replaceState"]) {
    const original = history[method];
    if (typeof original === "function") {
      history[method] = function (...args) {
        const result = original.apply(this, args);
        updateHubMode();
        return result;
      };
    }
  }
  window.addEventListener("popstate", updateHubMode, { passive: true });
  document.addEventListener("DOMContentLoaded", updateHubMode, { once: true });

  // Idle AudioContext suspension
  const NativeAudioContext = window.AudioContext;
  if (NativeAudioContext && window.AudioScheduledSourceNode) {
    const states = new WeakMap();
    const stateFor = (ctx) => {
      let s = states.get(ctx);
      if (!s) {
        s = { playing: 0, timer: null, pinned: false };
        states.set(ctx, s);
      }
      return s;
    };

    const scheduleIdleSuspend = (ctx) => {
      const s = stateFor(ctx);
      clearTimeout(s.timer);
      if (s.pinned || s.playing > 0) return;
      s.timer = setTimeout(() => {
        if (!s.pinned && s.playing === 0 && ctx.state === "running") {
          ctx.suspend().catch(() => {});
        }
      }, 4000);
    };

    window.AudioContext = new Proxy(NativeAudioContext, {
      construct(target, args, newTarget) {
        const ctx = Reflect.construct(target, args, newTarget);
        scheduleIdleSuspend(ctx);
        return ctx;
      },
    });

    const nativeResume = NativeAudioContext.prototype.resume;
    NativeAudioContext.prototype.resume = function (...args) {
      const res = nativeResume.apply(this, args);
      scheduleIdleSuspend(this);
      return res;
    };

    for (const method of [
      "createMediaStreamSource",
      "createMediaElementSource",
      "createMediaStreamDestination",
    ]) {
      const orig = NativeAudioContext.prototype[method];
      if (!orig) continue;
      NativeAudioContext.prototype[method] = function (...args) {
        const s = stateFor(this);
        s.pinned = true;
        clearTimeout(s.timer);
        if (this.state === "suspended") nativeResume.call(this).catch(() => {});
        return orig.apply(this, args);
      };
    }

    const origStart = AudioScheduledSourceNode.prototype.start;
    AudioScheduledSourceNode.prototype.start = function (...args) {
      const ctx = this.context;
      if (ctx instanceof NativeAudioContext) {
        const s = stateFor(ctx);
        s.playing += 1;
        clearTimeout(s.timer);
        this.addEventListener(
          "ended",
          () => {
            s.playing = Math.max(0, s.playing - 1);
            scheduleIdleSuspend(ctx);
          },
          { once: true }
        );
        if (ctx.state === "suspended") nativeResume.call(ctx).catch(() => {});
      }
      return origStart.apply(this, args);
    };
  }

  // Short ping sound routing via Web Audio so Now Playing media keys are never hijacked
  const staticSoundRegex = /^https:\/\/static\.[^/]*fbcdn\.net\//i;
  if (window.HTMLMediaElement && window.AudioContext) {
    const nativePlay = HTMLMediaElement.prototype.play;
    const bufferCache = new Map();
    let pingContext = null;

    const loadSoundBuffer = (src) => {
      if (!bufferCache.has(src)) {
        pingContext = pingContext || new window.AudioContext();
        const promise = fetch(src, { mode: "cors", credentials: "omit" })
          .then((r) => {
            if (!r.ok) throw new Error("HTTP " + r.status);
            return r.arrayBuffer();
          })
          .then((buf) => pingContext.decodeAudioData(buf));
        promise.catch(() => bufferCache.delete(src));
        bufferCache.set(src, promise);
      }
      return bufferCache.get(src);
    };

    HTMLMediaElement.prototype.play = function (...args) {
      const src = this.currentSrc || this.src || "";
      const isShortPing =
        this instanceof HTMLAudioElement &&
        !this.loop &&
        !this.srcObject &&
        staticSoundRegex.test(src);

      if (!isShortPing) return nativePlay.apply(this, args);

      const el = this;
      return loadSoundBuffer(src).then(
        (audioBuffer) => {
          const sourceNode = pingContext.createBufferSource();
          sourceNode.buffer = audioBuffer;
          const gainNode = pingContext.createGain();
          gainNode.gain.value = el.muted ? 0 : el.volume;
          sourceNode.connect(gainNode);
          gainNode.connect(pingContext.destination);
          sourceNode.addEventListener("ended", () => el.dispatchEvent(new Event("ended")), {
            once: true,
          });
          sourceNode.start();
          el.dispatchEvent(new Event("play"));
          el.dispatchEvent(new Event("playing"));
        },
        () => nativePlay.apply(el, args)
      );
    };
  }

  // Web Notification shim
  if (navigator.permissions && typeof navigator.permissions.query === "function") {
    const origQuery = navigator.permissions.query.bind(navigator.permissions);
    navigator.permissions.query = function (desc) {
      if (desc && desc.name === "notifications") {
        return Promise.resolve({
          state: "granted",
          onchange: null,
          addEventListener() {},
          removeEventListener() {},
        });
      }
      return origQuery(desc);
    };
  }

  function NativeNotification(title, options) {
    const opts = options || {};
    this.title = String(title || "");
    this.body = opts.body ? String(opts.body) : "";
    this.tag = opts.tag ? String(opts.tag) : "";
    this.onclick = null;
    this.onshow = null;
    this.onclose = null;
    this.onerror = null;

    if (document.documentElement && (this.title || this.body)) {
      document.documentElement.setAttribute(
        "data-hub-web-notif",
        JSON.stringify({
          title: this.title.slice(0, 200),
          body: this.body.slice(0, 500),
          tag: this.tag.slice(0, 120),
          ts: Date.now(),
        })
      );
    }
    const self = this;
    setTimeout(() => {
      if (typeof self.onshow === "function") self.onshow();
    }, 0);
  }
  NativeNotification.permission = "granted";
  NativeNotification.requestPermission = function (cb) {
    if (typeof cb === "function") cb("granted");
    return Promise.resolve("granted");
  };
  NativeNotification.prototype.close = function () {};
  NativeNotification.prototype.addEventListener = function () {};
  NativeNotification.prototype.removeEventListener = function () {};
  window.Notification = NativeNotification;
})();
