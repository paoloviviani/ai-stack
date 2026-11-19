# ADR 0111: Slides artifact (reveal.js in the preview sandbox)

- Status: accepted and shipped in Cerea v0.46.0 (slides artifact).
- Builds on: the artifact panel and its sandboxed previews (HTML, React, Mermaid); the built-in skills (ADR 0072)
  and the question card (`ask_user_question`).
- Direction (owner, 2026-11-07, revised twice): less structure over capable models. reveal.js is the engine only.

## Decision

A new artifact type, **slides**. The model writes the deck as **HTML**: `<section>` elements (nested sections
allowed), any inline HTML and CSS it likes, a `<style>` block allowed, notes in `<aside class="notes">`. Cerea runs
it with reveal.js in the Artifacts panel and supplies navigation, the slide counter, Present (full screen), notes,
overview, touch, and PDF export. **Markdown is an optional shortcut** (reveal's Markdown plugin: `---` between
slides, `Note:`, optional front matter) for quick decks and smaller models. PowerPoint stays the answer when a user
needs an editable Office file; the `slides` and `powerpoint` skills route between the two.

A deck is HTML when it contains a `<section>`, Markdown otherwise.

## Sandbox

The deck renders in **the same sandboxed `srcdoc` iframe** every preview uses: `allow-scripts` without
`allow-same-origin` or `allow-modals`, the same CSP (`default-src 'none'`, no network, images and fonts from
`data:` only) and the same error and link hook. A deck has no access to the Cerea origin, cookies or APIs.

- reveal.js **5.2.1**, pinned exactly in `package.json`, and its Markdown plugin are inlined into the srcdoc from
  `node_modules` (`?raw`) in a lazy chunk loaded the first time a deck is shown: no CDN, works offline.
- Initialised at width 1280, height 720, `center: false`, margin 0 for HTML decks (Markdown decks centre
  vertically with a small margin). Reveal's scroll view is off: below 435 px it would switch layout and touch
  `sessionStorage`, which the sandbox forbids.
- **Tidied out of the model's HTML** (and of HTML inside a Markdown deck, outside code fences and inline code) before it reaches the frame, and counted (`ParsedDeck.stripped`):
  `<script>` (the engine is ours); inline event handlers (`on*=`, also after a slash or a closing quote) and `javascript:` URLs; remote `src`, `poster`,
  `srcset`, CSS `url(http...)` and `@import`; `<link>`, `<base>`, `<meta>`, `<iframe>`, `<object>`, `<embed>`; and the
  document wrappers (`<html>`, `<head>`, `<body>`, doctype, `<title>`), keeping `<style>`. This is tidying, not the
  boundary: the sandbox plus CSP are, and they hold whatever the tidying misses. Links to `https:` pages stay: the frame's hook
  sends them through the external-link confirm.
- **Not loaded, on purpose:** reveal's notes plugin (its speaker view is a popup, blocked in the sandbox: notes show
  in a drawer under the slide, bound to **N** and **S**), the highlight plugin (nearly a megabyte; Markdown decks are
  pre-highlighted by the app), and the math plugin (math is pre-rendered by the app instead, see Math).

## Look

**No theme is applied unless asked.** What every deck gets is a neutral base: reveal.css (structural; its one
colour/line-height default on the viewport is removed) plus a small reset written entirely in `:where()`, so it has
no specificity and any CSS the model writes wins. Font, size and line-height sit on `body` because the engine's
reset sets `font: inherit` on every element.

- **Brand variables** are always defined on `:root`: `--brand-accent`, `--brand-on-accent`, `--brand-font`, and
  `--brand-logo-url` when a logo is set. They come from the organisation default (admin) and can be overridden in a
  deck's front matter (`accent`, `font`, `logo`). The model may use them; nothing is enforced.
- **Organisation default:** accent colour, font (one of four system stacks) and logo (a data URL under 300 kB), off
  by default; the page data carries only the small fields and a `hasLogo` flag, and the panel fetches the logo
  once from `/api/v2/slides/logo` (auth-checked, cacheable, served as bytes under a locked-down policy), one compact section under Administration -> Assistant, stored as JSON in `config`
  (`CHAT_SLIDES_DEFAULTS`), validated on save and on read.
- **Optional themes**, named in front matter or by `data-theme="..."` on a section: **Cerea** and **Cerea dark**
  (written for Cerea on reveal's CSS variables) and reveal's own **white, black, simple, moon, solarized, dracula**
  with every `@import` and comment removed (system font fallbacks; nothing loads from outside). A brand accent
  overrides a theme's link colour. The Cerea themes still carry layout classes (title, two-columns, ...); they are
  not advertised.
- Validated values only: accent is a hex colour, font and theme are from lists, a logo is an image data URL or a
  chat file name; each emitted as a fixed declaration. The model's own CSS is its own business; the front matter
  cannot add any.

## Math

LaTeX in slides is rendered with KaTeX (the version the chat already bundles, with mhchem for `\ce{}`) **in the
app, before the deck goes into the frame**, the same way code is pre-highlighted: the frame holds finished HTML and
CSS and runs no math JavaScript. It works in HTML and Markdown decks, in every PDF path (they all build the deck
the same way), and only once a deck is shown, so while it is still streaming the deck is code and math is simply
part of it.

- Delimiters `$...$`, `$$...$$`, `\(...\)`, `\[...\]`. Untouched: fenced and inline code, `<pre>`, `<code>`,
  `<style>`, `<script>`, and the inside of tags. `\$` is a literal dollar. Currency follows the chat renderer's rules:
  a single-dollar formula is tight (`$x$`) or padded (`$ x $`) on both sides, and its closing `$` is never followed by
  a digit, so `$5 and $10` is text.
- A formula KaTeX cannot read is shown as its source in red (`throwOnError: false`); the deck is never broken by
  one. Size and count are capped.
- `\newcommand` only lasts for its own formula in KaTeX, so each one is rewritten as the equivalent `\gdef`, which
  the shared macro table keeps: a definition on one slide serves the rest of the deck.
- Markdown decks get KaTeX's HTML-only output (its MathML annotation carries the TeX source, which the Markdown
  engine would read as Markdown); HTML decks get HTML plus MathML.
- The stylesheet is KaTeX's own, with **only the woff2 fonts, as `data:` URIs** (the CSP allows fonts from `data:`
  only), trimmed to the font families the rendered formulas can reach (a typical deck carries a fraction of the
  300 kB all of them weigh). The library, the stylesheet and the fonts are one lazy module, fetched only for a deck
  that could contain math.

## PDF

One **PDF** control uses the best path the deployment has; a small menu lists the others.

1. **Vector PDF from the server, one click,** where the kit's `fetch` profile runs its boxed Playwright Chromium
   (JavaScript on, Chromium's sandbox on, a network of its own). The app builds the print document (reveal's print
   layout, one 1280x720 page per slide, vertical slides included, notes optionally on pages of their own), connects
   to the renderer and calls `page.pdf()`. The browser is told to trust nothing: the document is handed over with
   `route.fulfill` at a fake address (it never fetches from Cerea, no credentials), every other request is aborted,
   the document's own content policy forbids the network anyway, the context is fresh (no cookies or storage), and
   there are size limits (2 MB in, 100 MB out), a 60 s timeout and a cap of two renders at once. The text in the PDF
   is real and selectable. `GET /api/v2/slides/pdf` says whether the renderer answers (the app's existing health
   probe); `POST` renders the deck sent in the body, authenticated, and nothing is looked up by id.
2. **"Print or save as PDF", no server.** The same print document, opened in a tab of its own by posting a form to
   `/api/v2/slides/print`. The response carries the protection as **headers**: the document's content policy (no
   network) and `Content-Security-Policy: sandbox allow-scripts allow-modals`, so the tab is an opaque origin (no
   cookies, no storage, no access to Cerea) that may still call `window.print()`. Not a `blob:` URL from the app
   origin, which would inherit that origin. Auth-checked; the content is what the request carries (the deck on
   screen, any version), so one user can never be served another's deck. A bar and an automatic print call at
   load; a hint to turn on background graphics (the CSS also asks the browser to keep them). Without the server
   renderer this is what the PDF button does.
3. **PDF as pictures,** the earlier path, as the last option and labelled so: a second offscreen copy of the deck in
   the preview sandbox, one SnapDOM picture per slide, a small PDF writer. No server, but the text cannot be
   selected.

Rejected: Gotenberg (optional, and Chromium with JavaScript off cannot run reveal.js); `window.print()` inside the
preview iframe (needs `allow-modals`, which the preview sandbox withholds so generated code cannot hold the tab);
printing from the app's own origin.

Slides are walked in reading order (top-level sections, and the inner sections of a vertical stack one by one), so
the counter and the picture PDF both count `1 / N` over every slide, stacks included. The picture export holds the
page pictures in memory, so it stops with a clear error past 150 MB or 200 slides, can be cancelled from the panel
(a Cancel control while it runs), and is aborted when the panel is destroyed; its offscreen frame is always removed.
Offscreen cross-origin frames get no animation frames, so its capture uses timers.

## Panel

Rendered in the Artifacts panel like other artifacts (kind `slides`, shown once the artifact completes: a deck
streams as code). Below the frame: previous, next, counter ("3 / 12"), notes, PDF, present. **Present** asks the
browser for full screen on the frame and falls back to a fixed in-page overlay with an exit button where element
full screen is not available (iPhone). The panel header's download saves the source: `.html` for an HTML deck, `.md` for Markdown. While a deck is being
written or edited, the frame is rebuilt only after the content holds still for 400 ms. Works at 390 px;
the chrome follows the app's light and dark theme.

## Skills and routing

A short built-in `slides` skill: one `<section>` per slide, notes in `<aside class="notes">`, design freely at
1280x720, brand variables available, keep text readable; Markdown shortcut in one paragraph; themes named, not
taught. When a user asks for slides, a deck or a presentation and it is unclear whether they need an editable file,
the model asks once with the question card, "Slides to present or share here" or "A PowerPoint file to edit". No
question when the user said "PowerPoint", "pptx" or "file to edit" (powerpoint) or "just slides" or "present"
(slides). Both skills' descriptions and bodies state the routing. Skills can be disabled by admins; the model sees
only enabled skills in its list, and both bodies say not to ask when the other skill is not listed (or when
artifacts are unavailable).

## Deferred

- The real speaker-view window (blocked by the sandbox).
- Bundled web fonts (system stacks only).
- Logos from user-uploaded chat images (run-produced files work).
