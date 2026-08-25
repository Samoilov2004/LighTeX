# LighTex Design System

This file is the visual source of truth for the native macOS application.

## Product character

- Quiet, precise, compact, native, professional.
- Document-first: source and PDF receive the most space and the least decoration.
- Light appearance only in the current product phase.
- Native macOS interaction and focus behavior take precedence over custom styling.

## Typography

- Application UI: macOS system font (SF Pro), Regular / Medium / Semibold.
- Welcome title: 28 pt Semibold.
- Standard UI: 12–14 pt.
- Secondary and status text: 11–12 pt.
- Source editor: SF Mono when available, platform monospace fallback, 13.5 pt default, 1.46 line-height multiple.
- Do not bundle web fonts.

## Color and surfaces

- Main canvas and editor: system white.
- Sidebar: `NSColor.controlBackgroundColor`.
- Secondary bars: `NSColor.windowBackgroundColor`.
- PDF surround: `NSColor.underPageBackgroundColor`.
- Dividers: `NSColor.separatorColor` at restrained opacity.
- Selection and primary interaction: current macOS system accent color.
- Errors and warnings: semantic system red/orange, always paired with an icon and text.
- No brand gradient or fixed purple/cyan palette.

## Layout

- 4 / 8 pt spacing rhythm; dense editor controls use 5–12 pt gaps and padding.
- Toolbar and tab rows: 34 pt.
- Status bar: 24 pt.
- Sidebar: 185–330 pt.
- Editor minimum: 360 pt.
- PDF minimum: 320 pt; user can hide it when width is constrained.
- Panels are separated by draggable native split dividers, not cards.

## Components

- Use standard SwiftUI/AppKit controls and SF Symbols.
- Small control radius: native 6–8 pt behavior.
- Settings use a 420 pt trailing overlay with native Form sections and a system segmented control.
- The project hub toolbar exposes only Settings; project creation and opening remain in the main content.
- First-run TeX setup is a required, content-area onboarding flow with Minimal, Standard, and Full runtime choices.
- Hover backgrounds may use black at roughly 4–5% opacity without movement or scaling.
- Active editor tab: white surface and medium-weight title, without an accent baseline.
- The sidebar starts directly with the file tree and uses a lower resizable Outline pane for document headings.
- Recompile is the primary toolbar action; Auto Compile is a secondary toggle beside it.
- Problems panel stays collapsed until requested or a build fails.

## Motion

- No decorative entrance animation.
- No spring, scale, glow, or layout-shifting hover effects.
- Native control state transitions only; the UI remains fully useful with reduced motion.
- The Settings overlay uses a 220 ms trailing move plus opacity transition and becomes immediate with Reduce Motion.

## Accessibility

- Preserve native focus rings and keyboard navigation.
- Icon-only buttons need an accessibility label and tooltip.
- Never communicate build state using color alone; include symbol and text.
- Normal text should meet 4.5:1 contrast on its surface.
- Truncated file paths provide their full value through help text where practical.

## Anti-patterns

- No card around every panel.
- No giant rounded welcome actions.
- No web dashboard chrome, fake statistics, decorative badges, or marketing copy.
- No emoji icons, gradients, excessive translucency, blur behind source/PDF, or arbitrary shadows.
