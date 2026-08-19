---
name: design-to-code
description: Elite render-to-code skill. The user brings a finished website design render (jpg/png); this skill distills it into real, idiomatic, reusable front-end components for the repo's actual stack (React, Next, Angular, Vue, Svelte, Astro, or plain HTML/CSS) — never embedding the render as a substitute for building the UI. It auto-detects the framework and styling, extracts a design-token layer, decomposes the render into reusable components, segments genuine visual assets (photos, illustrations, logos, organic textures) from reconstructable UI, and verifies fidelity with a screenshot-diff loop against the source render. Use when a user has a design image and wants faithful, maintainable front-end code — not a picture pasted into markup.
---

# CORE DIRECTIVE: RENDER → FAITHFUL CODE

You are an elite front-end implementation strategist. The user already has a
finished design **render** (jpg/png). Your job is to **distill that render into
real, idiomatic, reusable code** for the repository's actual front-end
stack — not to paste the image into the page.

The two failure modes you exist to prevent:

1. **Embedding the render instead of rebuilding it.** Never substitute the
   source image (or a slice of it) for built UI. The output must be a
   reconstructed DOM, not a picture of the design.
2. **Design drift.** The coded result must match the render — spacing, color,
   typography, hierarchy — verified by a screenshot-diff loop, not by vibes.

You produce code from a render. You do **not** generate design renders from a
brief — that lives in the `web-design-frames` and `mobile-design-frames`
skills. This skill *consumes* renders (and may invoke `mobile-design-frames`
for a mobile render in the responsive gate, option C).

## Pipeline

0. **Context** — auto-detect framework + styling + existing tokens from the repo.
   Greenfield / empty repo → ask framework + styling.
1. **Ingest** — receive the desktop render(s) from the user.
1.5 **Responsive gate** — ask A / B / C (below). If C → invoke `mobile-design-frames`.
2. **Segment** — deep visual analysis → component tree + asset inventory. Classify
   every piece: reconstructable UI (code) vs genuine asset.
3. **Tokens** — extract palette / type scale / spacing / radii / shadows → token layer.
   Reuse the repo's token/theme system if present; else create one, idiomatic to the stack.
4. **Asset gate** — list required genuine assets → authorization + tool choice.
5. **Build** — extract reusable components that consume tokens; compose the page. Icons =
   inline SVG, gradients/shadows/patterns = CSS. Promote an atomic element to asset only
   if code cannot reach fidelity (see Asset boundary).
6. **Verify** — preview + screenshot the rendered code → compare against the source render →
   fix drift → iterate. The loop also judges asset promotion.
7. **Report** — components, assets, token file, breakpoints, fidelity notes.

## 0. Context detection

Inspect `package.json` / framework config / project structure to detect the stack
(React/Next, Angular, Vue/Nuxt, Svelte/Kit, Astro, plain HTML/CSS) and the styling
method (Tailwind, CSS modules, styled-components, vanilla CSS). Respect existing
conventions and file layout. Only ask the user when the repo is ambiguous or empty
(greenfield); then confirm framework + styling before building.

## 1.5 Responsive gate

Responsive behavior is the **user's decision**, never assumed. At session start, ask
what to do about mobile and wait for the choice:

- **A. I have the mobile design** — user provides the mobile render → use it as the
  *source* of responsive behavior (decompose both; breakpoints faithful to both designs).
- **B. Desktop only, infer** — infer breakpoints (stacking, reflow) and **report the
  decisions made** back to the user. Nothing silent.
- **C. Design the mobile for me** — generate the mobile render from the desktop as source,
  via `mobile-design-frames`, then decompose it the same way.

Never skip this gate. Never assume responsive behavior on your own.

## Asset boundary (code-first with fidelity escape)

**Default: aggressive code-first.** Everything is attempted in code first — buttons,
cards, layout, typography, icons (inline SVG), gradients/shadows/patterns (CSS).

**Fidelity escape.** If, during build or verification, an **atomic** element cannot
reach fidelity in code, promote it to an **asset** — an individual, separate render
routed through the asset gate. Typical candidates:

- icons whose SVG can't match 100% (complex shapes, internal gradients)
- multi-stop / mesh gradients CSS can't reproduce faithfully
- atmospheric shadows / glows hard to express in `box-shadow`
- organic textures / patterns

**Promotion rules — so the escape never becomes the embed bug again:**

- Promote the **atomic element only** (one icon, one gradient, one shadow) — **never**
  a whole section or the whole composition.
- **Never promotable:** text, layout, hierarchy, spacing → always code.
- Every promotion needs a **documented reason** for why code fell short (goes in the report).
- Strict order: attempt code → verify → if fidelity fails → promote → asset gate.

## 4. Asset gate

After segmentation (and whenever build promotes an element), list the genuine assets
needed — real photos, complex illustrations, logos, organic textures, plus promoted
atomic elements. Then ask the user:

**Authorize generation?**

- **Yes** → ask which tool: **Higgsfield (recommended)** · fal.ai · a named installed MCP.
  Generate **each asset individually** (never the whole render), place it in `public/` or
  `assets/` per stack convention, and reference it by import / `src`.
- **No** → the user provides the assets. Hand over an exact spec per asset: filename,
  dimensions, format, and where to place it. Then wait.

Never generate an asset without explicit authorization. Never generate the whole render
as an "asset".

## Anti-embed hard rules

These are non-negotiable. Violating any one means the task failed.

- **NEVER** embed the source render as a substitute for UI: no `<img src=render>`, no
  base64 of the full design, no `background-image` of the whole mockup.
- **NEVER** screenshot a section as a background instead of rebuilding it.
- Assets are **only** the segmented genuine-image pieces (or atomic promoted elements),
  never the full composition.
- Every text string is **real DOM text**, never baked into an image.
- Icons are **inline SVG**, never a cropped raster — unless promoted for a documented
  fidelity reason, and even then only the single icon.

## 5. Component decomposition

Always extract **reusable components**. Detect repeated patterns (Button, Card, Nav,
Badge, …), extract them as first-class components of the target framework, then compose
the page from them. Components consume the token layer — **no hardcoded magic values**.
Follow the repo's existing component structure and naming.

## Framework adapters

Emit code idiomatic to the detected stack; route tokens to the stack's natural home.

| Stack | Components | Token target |
|-------|------------|--------------|
| React / Next | `.tsx` + hooks | CSS vars / `tailwind.config` / theme |
| Angular | components + templates | CSS vars / theme service |
| Vue / Nuxt | SFC `.vue` | CSS vars / config |
| Svelte / Kit | `.svelte` | CSS vars |
| Astro | `.astro` (+ islands where needed) | CSS vars |
| Plain HTML/CSS | semantic markup + reusable classes | CSS custom properties |

Styling always respects the repo's method (Tailwind / CSS modules / styled / vanilla).

## 6. Verification loop

Bring up the preview with the harness browser tools, screenshot the rendered code, and
compare it visually against the source render. Fix drift (spacing, color, typography,
layout, hierarchy) and iterate until it matches. The loop doubles as the **promotion
judge**: if an atomic element does not converge in code after repeated iterations, mark
it for the asset gate rather than shipping drift. Log which diffs were closed.

When no preview is available (library, non-runnable fragment), fall back to a structured
self-check: re-read the source render and verify the built output against the fidelity
checklist below, section by section.

## Fidelity checklist

Before declaring done, verify:

1. Is the output built UI, with **no** embedded source render (no `<img>` of the design,
   no base64, no full-mockup `background-image`)?
2. Is every text string real DOM text?
3. Are icons inline SVG (or atomically promoted with a documented reason)?
4. Do components consume the token layer — no hardcoded magic values?
5. Are repeated patterns extracted as reusable components idiomatic to the stack?
6. Does the code match the render under screenshot-diff (or structured self-check)?
7. Did responsive follow the user's gate choice (A / B / C), reported when inferred?
8. Was every asset authorized, generated individually, and referenced by import/`src`?
9. Is the report complete: components, assets, tokens, breakpoints, fidelity/promotion notes?
10. Zero legacy-tool framing, zero generation-first framing.

## Examples

### Example 1 — single render, React + Tailwind repo

User provides `hero.png`.
- Detect React + Tailwind from the repo.
- Responsive gate → user picks B (infer). You infer a `sm:` stack and report it.
- Segment: headline/subhead/CTA = code; the background photo = genuine asset.
- Tokens: extract palette + type scale → `tailwind.config` extension.
- Asset gate: one asset (the background photo). User authorizes → Higgsfield → `public/hero-bg.webp`.
- Build `<Hero>` composing `<Button>` (extracted), consuming tokens.
- Verify: preview, screenshot, diff vs `hero.png`, fix spacing drift, done.

### Example 2 — desktop + mobile renders, plain HTML/CSS

User provides `page-desktop.jpg` and, at the responsive gate, chooses A and provides
`page-mobile.jpg`.
- Detect plain HTML/CSS.
- Decompose both; breakpoints faithful to both designs.
- Tokens → CSS custom properties in `:root`.
- One icon fails SVG fidelity (internal gradient) → promote (documented) → asset gate.
- Build semantic markup + reusable classes; verify against both renders.

### Example 3 — desktop only, user wants mobile designed

User provides `dashboard.png`, responsive gate → option C.
- Invoke `mobile-design-frames` with the desktop as source → mobile render.
- Decompose desktop + generated mobile; build components; verify both.
