# LighTex Design System

This file is the visual source of truth for the macOS and Linux desktop application.

## Product character

- Quiet, precise, compact, platform-aware, professional.
- Document-first: source and PDF receive the most space and the least decoration.
- Light appearance only in the current product phase.
- Native window behavior, dialogs, keyboard conventions, and focus semantics take precedence over decorative consistency.

## Typography

- macOS UI: system font; Linux UI: Inter/Segoe UI fallback stack.
- Welcome title: 28 px Semibold.
- Standard UI: 12–14 px.
- Secondary and status text: 11–12 px.
- Source editor: SF Mono on macOS, JetBrains Mono/Liberation Mono fallback on Linux, 13.5 px default.
- Do not download fonts at runtime.

## Color and surfaces

- Main canvas and editor: white.
- Sidebar and window surfaces: neutral platform-aware grays.
- PDF surround: darker neutral under-page surface.
- Dividers: restrained one-pixel separators.
- Selection and primary interaction: one accent blue.
- Errors and warnings: semantic red/orange, always paired with icon and text.
- No brand gradient or fixed purple/cyan palette.

## Layout

- 4 / 8 px spacing rhythm; dense editor controls use 5–12 px gaps and padding.
- Toolbar and tab rows: 34 px; status bar: 24 px.
- Sidebar: 185–330 px; editor minimum: 360 px; PDF minimum: 320 px.
- Panels use draggable split dividers rather than cards.
- Source and PDF headers begin on the same horizontal line.
- Insert Shelf belongs only to the source column and opens as a compact bottom drawer.

## Components

- Use semantic HTML controls, Tauri-native dialogs/menus, Lucide icons, and visible focus rings.
- Small control radius: 6–8 px.
- Settings use a 420 px trailing overlay and a segmented tab control.
- Templates are a dedicated in-window view: `Yours` first, followed by bundled templates with real first-page previews.
- First-run TeX setup is required when no system or managed provider is configured.
- Hover backgrounds may use black at roughly 4–5% opacity without movement or scaling.
- Recompile is primary; Auto Compile is a secondary toggle beside it.
- Problems stays collapsed until requested or a build fails.
- Clearing Recent Projects requires confirmation and states that local files remain untouched.

## Motion and performance

- No decorative entrance animation, spring, scale, glow, or layout-shifting hover effects.
- Respect `prefers-reduced-motion`.
- Settings may use a 220 ms trailing move plus opacity transition.
- PDF pages render lazily near the continuous-scroll viewport.
- Searchable catalogs defer filtering and preserve stable list keys.

## Accessibility

- Preserve platform focus rings and full keyboard navigation.
- Icon-only buttons need an accessible label and tooltip.
- Never communicate build state using color alone.
- Normal text should meet 4.5:1 contrast.
- Controls should keep at least a 24 × 24 px target in dense desktop layouts.

## Anti-patterns

- No card around every panel.
- No giant rounded welcome actions.
- No web-dashboard chrome, fake statistics, decorative badges, emoji icons, gradients, excessive translucency, or arbitrary shadows.
