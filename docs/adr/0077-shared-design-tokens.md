# 0077 — One look for chat and console: the chat's values, the token mechanism, shared

Date: 2026-09-18

## Status

Accepted. Stage 1 built: the token file reconciled, the chat vendoring it
with a drift test, its dialog constants expressed through tokens, and the
sign-in page converted — including `Button`, pulled forward from stage 2 (see
below). Stages 2 (the 18 remaining primitives) and 3 (the 18 route screens)
are sequenced but not started.

## Context

The admin console and the chat read as two products. The console speaks an
indigo accent on zinc greys, flat tonal cards and pill buttons; the chat
speaks blue-600 on a pure-neutral ramp, gradient cards, rounded-full status
pills, tinted summary strips and dashed empty states. The sharpest evidence
it matters is the sign-in flow: signing into the chat already lands on the
console's login page, so the first screen a chat user ever sees is styled by
the other product.

The asymmetry that decides the shape: the console owns its look in one file
(`packages/ui/src/tokens.css`, restyled three times at that price — 0042
twice, then 0047), and every component reads it through Tailwind's
`@theme inline` mapping, which is also the entire dark-mode mechanism. The
chat has no such layer — some sixty literal class strings centralised in one
constants file, which is why converting it is tractable, but no tokens behind
them. Ripping the token file out and hardcoding utilities in the console
would discard the property the three restyles proved, and the next palette
change would cost sixty hand edits on each side instead of one file each.

## Decision

**The chat's idiom wins on values; the console's architecture wins on
mechanism.** The accent, the greys, the gradient cards, the rounded-full
pills, the tinted strips and the dashed empty states become the chat's. The
mechanism stays `tokens.css` plus `@theme inline`, and the chat gains that
mechanism rather than the console losing it.

This **partly reverses 0047's no-decoration stance** — "no blur, glass, glow,
or scale-on-hover; a console is read, not admired" — on the specific ground
that the stance fused two claims: readability requirements, which hold, and
a refusal of the chat's card-and-pill vocabulary, which produced the
two-product split. Gradient cards, tinted strips, pills and dashed empty
states come to the console through stages 2 and 3. What of 0047 survives is
everything structural: the token file's ownership of the look, the `@theme
inline` mapping, the readability requirements (4.5:1 floor, tabular figures,
sentence-case labels), and the refusal of blur, glass, glow and
scale-on-hover, which the chat's vocabulary never needed.

Concretely, in stage 1:

- **Accent to the blue-600 family.** The fill step is blue-600 — the chat's
  signature button, white on it 5.2:1, better than white on the old indigo's
  4.5:1. The text step is held at blue-700 rather than the chat's 600:
  blue-600 on the subtle fill is 4.2:1, under the floor the console's figures
  require; blue-700 on it is 5.5:1. A new pinned `--colour-accent-solid`
  carries fills that must not move between themes, because the text step
  lifts toward blue-400 in the dark theme and a fill that followed it would
  drop white text under 3:1. The chat's primary button keeps its dark-invariant
  blue through that token.
- **Greys to the chat's neutral ramp**, ground for ground, in both themes —
  including the dark page and card grounds, which now match the chat's exactly.
- **Semantic text tones stepped to the 700 weight where tokens express them.**
  Measured, not assumed: green-600 on green-100 is 3.0:1 and red-600 on
  red-100 is 4.0:1, so the chat's pill pairings as literally written fail the
  floor; green-700 is 4.6:1 and red-700 is 5.3:1 on the same fills. The pills
  keep the chat's fills and shape with text one step deeper. Dark faint ink
  stays hint-grade (3.7:1), as before — it is placeholders and hints, never
  figures.
- **Type and geometry reconciled, not replaced.** The chat's two extra text
  steps join the shared scale; the radius steps already cover both apps'
  values. Both apps set Roboto — already vendored under the Apache License
  2.0 with its licence beside it, so no new licence question, and the
  vendored copy carries the fonts and the licence with it.
- **The chat vendors the token file** (`src/styles/tokens.css`, byte copy)
  with a drift test that fails naming the differing lines. Both repositories
  must stay independently clonable and buildable — the installer work
  established that — so a build-time read from a sibling checkout was
  rejected. The earlier silent-divergence failure is the reason the copy is
  acceptable only with the test.
- **The sign-in page converts first**, because both products already send
  people to it: a card in the shared idiom with a title block, logic
  untouched. Money formatting is untouched everywhere — a restyle must never
  change what a figure says.
- **`Button` converts with it, one primitive pulled forward from stage 2.**
  A restyled card around the console's old outline-ring primary read worse
  than the card it replaced — once every button shares one radius, a ring
  around plain surface no longer reads as "press this", which is the one
  thing a page's primary action has to say. `primary` becomes a solid
  `--colour-accent-solid` fill with white text and `rounded-lg`, matching the
  chat's `PRIMARY` (`overlay/styles.ts`); `secondary`, `ghost` and `danger`
  keep their existing token-expressed colours and only pick up the shared
  radius. Every prop and variant the component already offered still works —
  this primitive serves all 18 route screens, not just the sign-in card.
  `rounded-full` is not carried forward to any of them: 0047 gave it to
  buttons, 0077 gives it to status pills instead, arriving with stages 2 and
  3.

## Consequences

- The next palette change costs one file per repository, verified by the
  drift test — the property 0042 proved twice and 0047 kept.
- Stages 2 and 3 convert the 18 remaining primitives (card, pill, empty-state
  and strip vocabulary through tokens) and then the 18 route screens. Screens
  keep their behaviour and their tests assert behaviour, not class names, so
  the conversion is styling-only by construction.
- One accepted difference is recorded rather than fixed: the console's hover
  wash (`hover:bg-sunken`) recesses in the dark theme where the chat's old
  hover lifted. Unifying the hover direction is a new token both themes must
  agree on, and stage 1 deliberately adds only the solid-fill token it could
  not do without.
- Found while building, fixed alongside: the chat's pill tones as written
  fail 4.5:1 (above); the console's dark faint was already hint-grade and
  stays so, documented instead of silently kept.
- **Found while building `Button`'s fill, fixed in both repositories:**
  `tokens.css`'s own form-control reset (`input, button, textarea, select {
  font: inherit; color: inherit; }`, kept for a consumer running no Tailwind
  at all) is unlayered plain CSS, so it wins over every `@layer utilities`
  rule regardless of specificity or source order — including a colour or
  weight utility written directly on a `<button>`, which is how both `Button`
  and the chat's `overlay/styles.ts` constants are built. It was invisible
  until a variant's colour differed from the page's own ink: the chat's
  converted dialog buttons measured `rgb(10, 10, 10)` where `text-white` was
  written, and `Button`'s new solid `primary` measured the same 3.83:1 white-
  on-accent instead of 5.17:1. Neither `tokens.css` (shared, drift-tested)
  nor the components could fix it alone; each repository now carries one
  `revert-layer` rule in its own Tailwind entry point (`Cerea/src/styles/
  main.css`, `apps/console/src/index.css`) that un-does exactly the
  sub-properties the reset touches, leaving its `font-family: inherit`
  intent — the one part Tailwind's own preflight already agrees with —
  untouched. The bug predates this ADR; it was latent in the console because
  no existing variant's utility colour ever disagreed with inherited ink.
