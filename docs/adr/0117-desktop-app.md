# ADR 0117: Cerea desktop app: Electron, with the connector built in and a first-class browser

- Status: accepted 2026-11-13 (owner: "Electron is fine"). macOS first; no code yet.
- Builds on:
  - ADR 0116 (browser use; phase 2 live view and takeover, Cerea #214);
  - Cerea #209 (the "Cerea connector" macOS menu-bar app, C108);
  - ADR 0097/0099 (Plan · Ask · Allow).
- Supersedes, once shipped: the Cerea connector menu-bar app as the main way to connect a Mac.

## Context

Users reach Cerea today through:
- the web app or the PWA;
- galopin, either from the CLI or through the Cerea connector menu-bar app, which runs local connectors, agents and the browser runtime.

The browser runtime drives its own Chrome through Playwright and CDP, in a window separate from Cerea.

The owner wants one desktop app with three parts:
- Cerea itself;
- every connector function (pairing, local MCP servers, agents);
- a built-in browser as a first-class citizen. The user browses and signs in to sites in it, the agent drives the same browser, and handover works in both directions.

Tauri was suggested first, for its size. The browser requirement rules it out:
- Tauri uses the system web view: WebKit on macOS, WebView2 on Windows, WebKitGTK on Linux.
- The runtime needs Chromium and CDP (ADR 0116 §7a: Playwright's AI snapshot, CDP screencast and input).

## Options

| | Built-in browser | Verdict |
|---|---|---|
| **A. Tauri + galopin's Chrome, streamed** | The pane shows ADR 0116 phase 2's live view and sends input. | Small, but the browser is second-class in a streamed view: typing, selection, scrolling, file pickers and password managers suffer. Rejected. |
| **B. Electron** | A real Chromium pane (`WebContentsView`) driven over CDP. | **Chosen.** Native input and real sign-ins. Node is built in, so it hosts the browser runtime, opencode and the MCP servers without a bundled Node. The ~100 MB of Chromium is a cost we already partly pay. |
| **C. Tauri with a bundled Chromium** | A real pane. | Not mature enough to rely on. Rejected. |

## Decision

### 1. Shell

- An Electron app, "Cerea", whose main window loads the user's Cerea origin. Sign-in happens in that window: it is Chromium, so the OIDC redirects work as in a browser.
- Native additions:
  - a tray or menu-bar item;
  - notifications for Needs-you;
  - a `cerea://` deep link;
  - start at login.
- Only the configured Cerea origin may run in the main window. Other origins open in the built-in browser or the system browser. `contextIsolation` and `sandbox` are on, and `nodeIntegration` is off for all web content.
- A minimal preload bridge exposes only what the web app needs:
  - "open in the built-in browser";
  - connector status;
  - "Edit connectors…".

### 2. Connector built in

- galopin keeps running as a separate process, so agents and connectors keep working when the window is closed.
  - The app installs and manages it as the menu-bar app does today: launchd user agent, pairing, "Edit connectors…", and Quit stopping all of galopin's processes.
  - The tray logic in `agent/internal/trayapp` is reused or ported.
- Pairing runs inside the app, with the address taken from the main window's origin, so the user doesn't type it.

### 3. Built-in browser

- **Placement:** a browser area in the app window (tabs, address bar, back and forward) or its own window, made of `WebContentsView`s in a dedicated session partition.
  - Its profile is separate from the Cerea window's session.
  - It persists, so sign-ins survive.
- **Driving it:**
  - **First choice:** the browser runtime (ADR 0116 §2) attaches to these views over CDP, with Playwright's `connectOverCDP`, so the snapshot, act, classification and approval code is unchanged.
  - **Constraint:** Electron's CDP endpoint must not be a TCP port that any local process can use.
    - Preferred: a pipe or a per-launch secret.
    - Fallback: an adapter over Electron's `webContents.debugger` API, with the runtime inside the app.
  - **First step:** a spike decides which one.
- **Who drives:** the agent drives only tabs it opened or tabs the user handed over. That is the ADR 0116 lent-tab rule, now with a visible "lend this tab to Cerea" control on each tab.
- **Takeover:** the user is already in front of the real page. Takeover and hand-back become a bar on the tab, not a stream.
  - The phase 2 stream is still used to watch from the phone or the web while the app runs on the Mac.
- **Where it runs:** the app's browser is a computer like any other in Cerea (ADR 0116 machine choice), named after the Mac. It replaces galopin's Playwright Chrome on that Mac while the app is running.

### 4. Distribution and updates (macOS)

- Builds for arm64 and x64, packaged with electron-builder in CI: a zip and a DMG on the GitHub release.
  - The macOS app job's release-safety rules apply: upload only to the release created by `release.sh`, and pin and verify the toolchain.
- No Apple Developer account:
  - ad-hoc signing;
  - first launch by right-click → Open, or the installer line that clears quarantine (as for #209).
- **Updates:** Electron's built-in updater (Squirrel.Mac) needs a properly signed app, so it is not used. The app checks the GitHub release, verifies the sha256, then downloads and swaps the bundle the way the #209 installer does.
- Windows and Linux follow later, with the same code and their own packaging.

### 5. Security

- The app holds the user's Cerea session and galopin's device credentials. Electron's hardening checklist is mandatory:
  - no remote code in privileged contexts;
  - navigation and `window.open` guards;
  - a permission request handler that denies by default;
  - a restricted `webContents` creation.
- The built-in browser partition never shares cookies with the Cerea window.

## Phases

1. **Spike:** attaching the runtime to an Electron `WebContentsView` without an open TCP debugging port, with snapshot, act and screencast. The result decides §3.
2. **macOS app:**
   - shell, sign-in, tray, notifications;
   - galopin management (pairing, Quit, Edit connectors);
   - the built-in browser with lend and handover;
   - packaging and the update check.
3. Retire the menu-bar app: the installer offers the desktop app instead.
4. Windows and Linux.

## Consequences

- One install gives a user Cerea, local connectors and a browser the agent can use, with no terminal and no separate Chrome window.
- The desktop browser makes takeover native. The phase 2 stream is kept for watching or taking over from other devices.
- The app is about 150–200 MB. Electron security updates mean a release whenever Chromium ships a security fix.
