# Euro-Office spike (C12 / Cerea #18), 2026-10-26

Research only. No Cerea/Pystino changes, nothing committed. Image `ghcr.io/euro-office/documentserver:v9.3.7` (released 2026-10-24; the `9.3.7` tag does not exist, the tag is `v9.3.7`). Scratch code: `/var/tmp/eo-spike/` (`integ/server.py` integrator, `integ/plugin/`, `pw/*.js` Playwright, `bld/*.docbuilder`, `docbuilder_call.py`, `runhard.sh`). Screenshots: `ai-stack/reports/screenshots/2026-10-26-euro-office/` (24 PNG). All containers, volumes, the image, firewall rules and servers were removed at the end.

## Verdict

| Part | Go/no-go | Effort (Sonnet worker + review) |
|---|---|---|
| A. Editor in the side panel | GO | 4 to 6 days |
| B. Server-side engine (Document Builder) | GO | 4 to 5 days |
| C. Live co-editing through a plugin | GO, with the channel below (not `createConnector`) | 5 to 8 days |
| Kit packaging (compose service, secrets, volumes, healthcheck, docs) | needed for all three | 2 to 3 days |

Minimum hardware to recommend when enabled: 2 vCPU and 4 GB RAM dedicated to the service (container limit 2 GB, never below 1.5 GB), 10 GB free disk (image is 7.2 GB unpacked), SSD. For the box itself: Cerea + Mongo + Authelia + this needs 6 GB RAM total at the very least; 8 GB is comfortable.

## Q1. Runs at all: YES

- Pull: 2 m 20 s here, **7.2 GB** on disk (the official docs say 5 GB; they are out of date). amd64 and arm64 published.
- Run: `docker run -d --memory 3g -p 127.0.0.1:8080:80 -e JWT_SECRET=<40 random> -e ALLOW_PRIVATE_IP_ADDRESS=true ...`. Single container bundling nginx, docservice, converter, PostgreSQL, RabbitMQ and Redis under supervisord (102 processes, 102 PIDs).
- **Time to healthy** (`/healthcheck` returns `true`): 102 to 137 s on every start, including `docker restart`. The entrypoint regenerates fonts (`AllFonts.js`), presentation themes and the JS cache on every start (`GENERATE_FONTS=true` default). Plan the compose healthcheck with `start_period: 180s`.
- **RAM** (`docker stats`, 2 s sampling): peak 1.34 GiB while booting; idle 850 to 870 MiB; with docx + xlsx + pptx open in edit mode at once and typing, max 868 MiB; cold-opening a 1.2 MB / 50 000-row xlsx, max 916 MiB. Per open document the increment is small (tens of MB).
- **CPU** (4-core box): idle 0.5 %; opening one document 30 to 110 % of one core for 3 to 6 s; typing/co-editing negligible; 3 editors + typing mean 13 %, peak 74 %; big xlsx peak 158 %.
- What the image lacks versus deb/rpm (from the entrypoint, the release assets and the Euro-Office docs): the image is the "standalone" variant only, PostgreSQL is the only DB (`DB_TYPE` other than postgres exits), no systemd units (supervisord instead), admin panel and example app are off by default, and **`sdkjs-plugins/` ships empty** (no default plugins, no `plugin-list-default.json`). Release notes for v9.3.7 contain a single line (Node 24 bump); the README calls the image "for testing and integration purposes"; the production-grade signed builds are the Nextcloud-branded ones. The CHANGELOG shows the project is young (Euro-Office fork of ONLYOFFICE 9.3, weekly releases).

## Q2. Integrator round trip: YES

Throwaway Python server (stdlib + PyJWT, `integ/server.py`): serves `/files?f=&t=<jwt>` (DS fetched it with an `Authorization` header JWT, we also accepted the query token), an HTML page with `DocsAPI.DocEditor` and a signed config (`token` field), `/callback`, and a Command Service client. It listens on 127.0.0.1 and on the docker bridge address 172.17.0.1 only (needed so the container can call back; `ALLOW_PRIVATE_IP_ADDRESS=true` is required for that).

Evidence (`integ/events.log`):
```
13:02:49 CALLBACK status 1  (user connected)
13:02:57 FORCESAVE {'key': ..., 'error': 0}      # Command Service {"c":"forcesave"}
13:02:59 CALLBACK status 6 forcesavetype 0  -> SAVED 40228 bytes
13:03:10 CALLBACK status 2  (after the browser closed) -> SAVED 40238 bytes
```
Typing ` EDIT-ONE-FROM-PLAYWRIGHT` then ` SECOND-EDIT` through the real editor UI: the status 6 file contains the first edit, the status 2 file both (`python-docx` reads table cell `d EDIT-ONE-FROM-PLAYWRIGHT SECOND-EDIT`; CRC ok, 20 parts). Both callbacks were JWT-verified (token in body and in the header). JWT is mandatory: a Command Service/docbuilder call without a token returns `{"error":-8}`.

Fidelity caveat for versioning: a save **rewrites every part** (`styles.xml` 349 KB to 1.15 MB, `numbering.xml`, theme, fontTable, docProps; thumbnail and `stylesWithEffects.xml` dropped; footnotes/endnotes parts added). Text, runs, bold/italic/size were preserved. Cerea must treat each save as a new opaque version, not a patch.

Document keys must change after status 2 (a new key per version), or DS serves its cache.

**Time to first paint** (Chromium headless, localhost, page navigation to event; warm-ish): `api.js` loaded 7 to 14 ms; editor chrome (`onAppReady`) 1.0 to 1.6 s; document rendered (`onDocumentReady`) 4.0 to 5.6 s for the 37 KB docx, 7.6 KB xlsx, 28 KB pptx (a cold conversion to the internal format is part of it); the 50 k-row xlsx 6.3 to 7.3 s. Plan a loading state of about 5 s.

Screenshots: `desktop-view-docx|xlsx|pptx.png`, `desktop-edit-docx.png`, phone ones below.

## Q3. Server-side engine: YES, Document Builder ships and works

- Binary `/var/www/euro-office/documentserver/server/FileConverter/bin/docbuilder` (usage `docbuilder "script"`), plus `x2t`. Run inside the container with `LD_LIBRARY_PATH` set to that bin dir.
- **HTTP endpoint exists**: `POST /docbuilder` with JWT, body `{"async":false,"url":"<url of a .docbuilder script>"}` returns `{"key":..., "urls":{"out.docx":"http://.../cache/files/data/<key>/output/out.docx/..."},"end":true}`. The script itself can `builder.OpenFile("http://integrator/files?...&t=<jwt>")` so inputs are fetched by signed URL and the output is downloaded from the returned URL. 2.05 to 3.07 s per call end to end (docx replace). This is exactly the "Cerea serves a signed link, the engine returns a file" pattern, no files on the DS disk.
- Script test (docx): `SearchAndReplace("PLACEHOLDER" -> "1,234")` plus appending a run. Result: the replaced run keeps `<w:i/><w:sz w:val="28"/>` (italic, 14 pt), the neighbouring bold run is untouched. 2.29 s wall via CLI, 32 MB RSS for the process.
- Script test (xlsx): `GetRange("A2").SetValue("pears")`, B2 99, C2 "new col", B3 `=B2*3`. Reopened with openpyxl: values right, formula kept, **cached value recomputed (297)**. 1.68 s. On the 50 k-row, 1.2 MB xlsx setting 100 cells: 3.53 s wall.
- Fidelity: it is an open/convert/save cycle, so like Q2 all parts are rewritten (docx diff identical to the interactive save: 15 parts differ, 2 dropped, 5 added; xlsx: 9 parts differ, `sharedStrings.xml` and `theme.xml` added, `styles.xml` shrank 2550 to 1607 bytes). Content semantics held for the fixtures; **unknown for exotic content** (x14 extensions, charts, SmartArt, macros). The `xlsx_patch.py` approach (byte-identical untouched parts) is strictly safer for files the user cares about; Document Builder is the right engine when a document is open or needs recalculation/rendering features.
- API surface is the same `Api.*` as the plugin (ONLYOFFICE Document Builder API), so one set of typed operations can be compiled to builder scripts for the server engine and to `callCommand` bodies for the live engine. Not tested: charts, tables insertion, comments, tracked changes.

## Q4. Plugins and live editing: YES

- **Installing without rebuilding the image: yes, two ways.**
  1. Host the plugin anywhere (the integrator) and reference it in the editor config: `editorConfig.plugins = {autostart:[guid], pluginsData:["http://.../plugin/config.json"]}`. Needs CORS (`Access-Control-Allow-Origin: *`) on the plugin files. Worked on the default container.
  2. Bind-mount a folder into `/var/www/euro-office/documentserver/sdkjs-plugins/<name>:ro` (nginx served `/sdkjs-plugins/cerea-bridge/config.json` with 200) and use only `autostart:[guid]`. Worked, **including without running `documentserver-pluginsmanager.sh`** (the docs say to run it; we did not need to).
- Plugin: `integ/plugin/` (config.json `isSystem:true`, invisible; index.html about 40 lines; `plugins.js` taken from `Euro-Office/plugins/sdkjs-plugins/v1`, Apache-2.0, must be vendored because the image has none). It exposes `insertParagraph`, `setCell`, `replaceText` and applies them with `Asc.plugin.callCommand(fn, false, true, cb)` using `Asc.scope` for arguments.
- **Live and co-edit demonstrated**: two browser sessions (u1 with plugin, u2 without) on the same key; the op executes in u1 (reply `{"done":"insertParagraph"}`) and u2's screenshot shows the paragraph (docx) / cells D2, D3 (xlsx) with the "2 users" badge. Screenshots `plugin-live-docx|xlsx-user2-coedit.png`, `...after-poll.png`, and the `mounted-plugin-live-*` set from the hardened container.
- **Channel from the Cerea page to the plugin**: `createConnector` is absent (no occurrence of "connector" in `api.js`). Two channels work:
  1. **postMessage by frame traversal**: the plugin runs in an iframe inside the editor iframe (`window.frames[0].frames[0]`); `window.frames[i]` and `postMessage` are allowed cross-origin, so the host page does `frames[0].frames[k].postMessage({cerea:'op',op},'*')`; the plugin replies with `window.top.postMessage(...)`. Works for both hosting variants. Fragile if the editor changes its frame nesting; the plugin must filter by `event.source`/origin in the real implementation.
  2. **Plugin-initiated pull**: the plugin polls (or SSE/WebSocket) the Cerea backend, e.g. an op queue per document. Works only when the plugin is hosted at the integrator origin (variant 1); a plugin mounted into DS cannot use same-origin relative URLs and would need CORS on Cerea. Best for server-pushed operations (model edits when no page is listening to postMessage).
  Neither was affected by the JWT config. The `DocEditor` object also has `insertImage`, `insertLink`, `insertPlainText`, `serviceCommand` but nothing generic for scripts.
- Co-editing semantic caveat: `InsertContent` inserted at the caret/start of the document, the model-level ops need explicit anchors (content controls, bookmarks, paragraph indexes) and concurrent human edits shift indexes.

## Q5. Isolation: PARTLY

- **No outbound internet: YES.** Run behind a host firewall rule (`iptables DOCKER-USER`: container IP may reach only 172.17.0.0/16, everything else DROP, rules removed afterwards): the DROP counter stayed at **0 packets** across boot, view, edit, plugin, docbuilder and forcesave (rules were inserted about 1 s after container start, so the first second is unobserved). `ss` inside the container showed only 127.0.0.1 connections (Postgres 5432, RabbitMQ 5672). The browser made **0 requests to non-localhost hosts**; fonts are bundled (`core-fonts`, `dictionaries`), no CDN. The only external names in config are the CORS allow-list entries (`onlyoffice.github.io`, `onlyoffice-plugins.github.io`) and the sharp/libvips notice in logs.
- **Non-root: NO for the container.** `--user 1000:1000` exits 1 (`mkdir /var/www/euro-office/Data/.private: Permission denied`). The entrypoint needs root; inside, supervisord/nginx master run as root and workers as `ds`, `postgres`, `rabbitmq`, `redis`, `www-data`. Mitigation: `--cap-drop ALL` plus `CHOWN SETUID SETGID DAC_OVERRIDE FOWNER KILL`, `--security-opt no-new-privileges`, `--pids-limit 400`: worked.
- **Read-only root filesystem: PARTLY.** `--read-only` with tmpfs `/tmp /run` and writable volumes for `/etc`, `/var/lib`, `/var/log`, `/var/cache`, `/usr/share/fonts` and **`/var/www/euro-office`** works (everything above passed in this container). Making only parts of the app tree writable fails: the start script writes `AllFonts.js`, thumbnails, themes and rewrites `web-apps/.../api.js` inside the app tree, and without it the editor hangs at `Script error for "allfonts"` (HTTP 404 on `sdkjs/common/AllFonts.js`). Cost: the volume copy makes the first start about 137 s. `runhard.sh` has the exact command.
- **Memory limits** (writable container, boot + opening 3 docs + the 50 k-row sheet): 1.5 GB and 1 GB both fine (peak 996 MiB reported, mostly reclaimable cache; no OOM). At **640 MB and 512 MB the stack never becomes healthy**: the kernel OOM-kills the node `MainThread` processes (docservice/converter), supervisord restarts them in a loop, and **the container stays "running"** (exit 0, `OOMKilled=true`, healthcheck never true). Needs an HTTP healthcheck, not a "container up" check. Recommend `mem_limit: 2g`.
- Others: the bundled Postgres/RabbitMQ/Redis listen on localhost only; publish nginx on 127.0.0.1 or the internal compose network, never publicly; keep admin panel and example app off; JWT secret via env (without it the entrypoint generates one into `Data/.private/jwt_secret`).

## Q6. Licence and attribution

- Core licence: **AGPL-3.0** (GitHub licence API for DocumentServer, sdkjs, web-apps; `LICENSE.txt` in the image is the standard AGPL text). Source headers add Section 7(a) (warranty of non-infringement excluded), say modified interactive UIs must display Appropriate Legal Notices (Section 5), and put GUI elements, icons and technical writing under **CC BY-SA 4.0**. Unlike upstream ONLYOFFICE, I found no logo-retention clause in the headers or `LICENSE`; the About dialog (changelog 9.3.6-rc.1) shows build commits and a Euro-Office legal notice, so leave it intact. `3rd-Party.txt` lists bundled components (Bootstrap Apache-2.0, RequireJS, jQuery MIT, etc.); `core-fonts` and `dictionaries` carry their own licences (SIL OFL, Hunspell and similar; each folder has a README).
- Unmodified container run as a separate service, talking over HTTP: Cerea's own code is not a derivative work and stays Apache-2.0. What Cerea owes: ship/point to the AGPL text and the corresponding source for the version in the kit (link to `github.com/Euro-Office/DocumentServer` tag `v9.3.7`, plus sdkjs/web-apps/server/core at the commits listed in the About dialog), name it and its licence in the kit's third-party notices and in the docs, keep the unmodified UI (About dialog) visible. Section 13 (offer source to network users) is only triggered by modified versions; if we ever patch the image we must offer the patched source. Not legal advice; one lawyer read before default-on.
- The plugin we write: it runs inside the AGPL editor's JS context and calls `Api.*`, and it vendors `plugins.js`. `plugins.js` is Apache-2.0 (compatible, keep its header). Our plugin code is best kept Apache-2.0 under Cerea's own licence; it is a separate work loaded as a plugin and communicating through a documented API, but the linking-through-API boundary is arguable for AGPL, so treat the plugin as "may be combined with AGPL code" and avoid copying any sdkjs source into it. Bundled-with-image or mounted plugin files distributed together with the image would need the same notice treatment.
- Everything in this repo (Apache-2.0 policy) stays compatible as long as Euro-Office is an optional, separately run, unmodified service, off by default.

## Q7. Phone: YES with a configuration

- Default `DocEditor` on a 390 px viewport loads the **desktop-style** viewer at 100 % zoom: the page is cut off at the right, toolbar crammed (`phone-view-docx-default.png`). Not good.
- With `type: "mobile"` in the config the **mobile editors** are used (`apps/*/mobile` exist for documenteditor, spreadsheeteditor, presentationeditor): page fits the width, clean top bar (title, search, users, menu), spreadsheet grid with formula bar and sheet tab, and in edit mode a floating pencil button to switch to editing. Screenshots: `phone-view-docx|xlsx|pptx-typemobile.png`, `phone-edit-docx|xlsx|pptx-typemobile.png` (devices scale 2, 390x844). Reading is comfortable; editing on a phone is workable for small edits, not for layout work. Load time on the mobile editor equals desktop (4.0 to 6.4 s).
- Recommendation: choose `type:"mobile"` from a `matchMedia` check in the Cerea panel; view mode by default on phones.

## Risks

1. **Maturity and support**: 9.3.x community builds from a young fork; weekly releases; the README says "testing and integration". Pin by tag/digest, test each bump. Production-signed builds exist only via Nextcloud's packaging.
2. **Size and start**: 7.2 GB image, about 100 to 137 s to healthy on each start/restart; compose healthchecks and dependency ordering must allow it.
3. **Memory-limit failure is silent** (crash loop under a running container). Use an HTTP healthcheck on `/healthcheck` and a restart policy; document the 2 GB floor.
4. **Not rootless, root FS read-only only with a big writable volume**: security hardening is partial; the service must sit on an internal network behind Cerea's reverse proxy.
5. **Save rewrites the whole file**: versions in GridFS are full copies, round-trip fidelity for exotic documents is untested (charts, SmartArt, macros, x14), and the helper `xlsx_patch.py` remains the lowest-risk path for edits when the editor is not involved.
6. **Plugin channel is unofficial**: postMessage by frame traversal depends on frame nesting; `createConnector` is missing. Prefer the pull channel for model-driven ops and keep the postMessage path behind a feature check with a fallback to "reload the editor with the new version".
7. **Concurrency semantics**: model edits and human edits both go through the editor model; ops need stable anchors; DS key rotation after each status 2 and forcesave/versions need a Cerea-side lock.
8. **Document Builder API coverage and limits** untested for charts/pptx/comments; each call takes 2 to 3.5 s and one converter process (about 32 MB RSS for small files, more for big); add a concurrency cap (the box has 4 cores).
9. **AGPL compliance** is an obligation to track per release (source links, notices) and a blocker if we ever patch the image.
10. One unexplained non-reproducible event: the first editor open after a restart of my integrator timed out once at `constructed` (no `appReady`) before any hardening; the 3 later runs and all following sessions were fine. Not investigated further (log: `docservice` showed only an expired `UpdateVersion` warning). Worth a retry loop/timeout in the panel.

## Method notes

Lock `/tmp/heavy.lock` held for the whole run, released at the end; disk before/after 20 G to 20 G free (peak 13 G). A host firewall rule was used only for the egress test and removed by exact match. `pgrep -f` self-match killed my own shell twice early on (see memory note); later runs used PID files.
