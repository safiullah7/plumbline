# <Module> design principles

Owner: UX engineer. Checked and updated every feature.

## Principles
5-8 principles specific to this product, each with one line on why.
1.

## Design tokens and components
The single source of truth is docs/product/<module>/tokens.css (a :root block of
CSS custom properties: colours, type scale, spacing, radius). Prototypes paste
that block; the app's theme mirrors it. List the component library in use and
where each component is defined in the code.

## Accessibility baseline
WCAG 2.2 AA: text contrast 4.5:1, visible focus, every input labeled, targets at
least 24x24 px, no meaning carried by color alone, full keyboard operation,
reduced motion respected.

## Patterns to reuse
| Pattern | Where it's used | Notes |
| --- | --- | --- |

## Patterns to avoid
Generic "template" UI that makes every product look the same:
- identical rounded cards in a grid with the same shadow, for content that isn't a set of equals
- gradient washes and glows as decoration
- tracked-out ALL-CAPS eyebrow labels above every heading
- arrows or icons on buttons that already say what they do
- two near-identical fonts; use one family, or two clearly different ones
- meaning carried by colour alone, or grey text on grey below 4.5:1
- motion everywhere; at most one deliberate transition per screen
Add product-specific ones as they come up.
