# Visual system and native mapping

Adapt [Geist](https://vercel.com/geist/introduction) to a native Mac developer utility. Use the official color-role and typography hierarchy as guidance, not Vercel branding or an assertion that their React components are native SwiftUI controls.

## Tokens

| Role | Light | Dark |
| --- | --- | --- |
| Main background | #FFFFFF | #0A0A0A |
| Secondary background | #FAFAFA | #111111 |
| Hover / selected neutral | #F2F2F2 | #1A1A1A |
| Default border | #EAEAEA | #262626 |
| Strong border | #D4D4D4 | #3E3E3E |
| Primary text | #171717 | #EDEDED |
| Secondary text | #666666 | #A1A1A1 |
| Focus / active accent | #0070F3 | #52A8FF |
| Running / success | #067A3B | #45C985 |
| Attention | #946000 | #F5B943 |
| Error / destructive | #C52A31 | #FF7077 |
| Start action | #25704B | #79B995 |
| Start button surface | #EEF7F1 | #14251C |
| Stop action | #A34850 | #D38E92 |
| Stop button surface | #FBF0F1 | #2A1B1D |

The selected layout is A (Grouped list). Start and Stop use quiet semantic text/icon colors; labeled buttons add a soft tinted surface, and icon-only controls reveal the tint on hover. Restart stays neutral. Disabled controls remain subdued, and removal actions retain the separate destructive color.

The native Dockey wordmark is rounded project artwork from the selected **Rounded 01** concept, rendered as cached vector geometry. Its shared sidebar/About component uses a filled-area optical center computed offline; see [branding](branding.md) for reference assets, dimensions, and regeneration details. Geist Sans remains the interface and window-title typeface, with Geist Mono for logs, identifiers, commands, and ports. The wordmark does not load an image or an additional font at runtime. The earlier prototype retains its Geist wordmark. Default body 13px/19px in the prototype, secondary metadata 11–12px, compact rows at least 40px, comfortable rows at least 52px, headings 18–24px. Essential actions retain adequate target areas and keyboard focus even when their glyphs are small. Interface and log text sizes are adjustable independently.

Spacing: 4/8/12/16/20/24/32px. Controls 6px radius, panels 8px, app window 12px. One subtle border per edge. Avoid repeated stat cards, hero areas, gradients, decorative charts, and oversized headings.

Motion: short opacity/state transitions; suppress under reduced motion. Running/health state uses text plus icon/color. Async actions show pending state and block duplicate invocation.

## Native implementation mapping

| Prototype element | Intended native implementation |
| --- | --- |
| Navigation / inspector | SwiftUI NavigationSplitView and split-view sizing; AppKit integration where needed |
| Grouped container table | SwiftUI Table/OutlineGroup or NSOutlineView if interaction/performance calls for it |
| Menus / command search | Native Menu/Commands, contextual menus, keyboard shortcuts |
| Settings | Native settings window with sidebar categories and application-specific controls |
| Logs | Bounded backing buffer and performant text presentation; selectable text and accessible controls |
| Run/configuration flows | Native sheets with validation and precise operation summaries |
| macOS window chrome | Real title bar, toolbar, standard traffic lights, minimum window sizing |

The browser study mimics window chrome to communicate composition. It is not the shipped desktop runtime.
