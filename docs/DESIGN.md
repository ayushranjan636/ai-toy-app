# Design system

Tokens live in `app/lib/core/design/tokens.dart`. Theme: `theme.dart`.
Components: `button.dart`, `layout.dart` (StepScaffold, InlineNotice,
StateView, ZSection/ZRow, StatusLabel), `illustrations.dart`.

## Colour roles and measured contrast (WCAG 2.x)

| Pairing | Ratio | Use |
|---|---|---|
| Teal `#214E47` on Cream `#FFF8EE` | 8.87 | Headings, primary actions, links |
| Charcoal `#293B36` on Cream | 11.23 | Body text |
| White on Teal | 9.35 | Primary button label |
| Teal on Mint surface `#E6F1EC` | 8.09 | Text on subtle panels |
| Muted `#5A6B66` on Cream | 5.34 | Secondary text, input borders |
| Muted on Mint surface | 4.87 | Secondary text on panels |
| Error `#A63A2A` on Cream | 6.11 | Errors |
| Charcoal on Coral `#F28F79` | 5.06 | Allowed, but not used yet |
| **Coral on Cream** | **2.22** | **Never text.** Accent marks and dots only |
| **Mint `#A8CEC3` on Cream** | **1.62** | **Never text or a sole boundary.** Decorative shapes only |

Status is never shown by colour alone: StatusLabel and InlineNotice
always pair an icon or dot with text.

## Type, spacing, shape, motion

- System fonts (SF Pro / Roboto) for platform fidelity, with no runtime font downloads.
  Scale: display 30, title 22, heading 18, body 16, label 15, caption 13.
- Spacing: 4, 8, 12, 16, 24, 32, 48. Page margin 24.
- Radii: 8 / 14 / 20. A single soft shadow is reserved for sheets.
- Motion: 120 / 220 / 360 ms, ease-out. `ZMotion.of()` returns zero under
  reduce-motion. The connection pulse stops when reduce-motion is on and
  when it's not actively connecting.

## Accessibility

- Minimum touch target 48dp. Buttons are 52pt tall.
- Text scales up to 2.0× (clamped beyond that). A test checks the Welcome screen
  at 2× for overflow, and that test found and fixed real overflows.
- Headers, live regions for errors and progress, and labelled icon buttons
  (Back, Show password, Delete…).
- Onboarding screens have one primary action pinned above the keyboard, with
  scrollable content for small phones.

## Brand assets

No logo or product photography was supplied. The leaf mark and "zivoo" text
wordmark are placeholders and do not depict the product. Put the supplied
files in `app/assets/brand/` (see the README there) and swap `ZivooWordmark`,
`_WelcomeArt` and `_ToyIllustration` for `Image.asset`, without redrawing or
distorting them.
