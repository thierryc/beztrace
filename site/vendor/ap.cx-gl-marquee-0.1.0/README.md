# @ap.cx/gl-marquee

The wavy WebGL text marquee from AP.CX, ready to use in any footer or banner.
The core has **zero runtime dependencies**. React is an optional adapter, imported
separately. Ships as ESM JavaScript with TypeScript declarations; use `import`,
not CommonJS `require`.

```sh
npm install @ap.cx/gl-marquee
```

## React

```tsx
import { GLMarquee } from '@ap.cx/gl-marquee/react'

export function Footer() {
  return (
    <footer>
      <GLMarquee
        message="Your studio. Your next idea."
        fontFamily='"Your Font", sans-serif'
        appearance={{ background: '#14141a', text: '#f7f7f8' }}
        style={{ height: 220 }}
      />
    </footer>
  )
}
```

Works with React 18 and 19. The component is safe to import and server-render:
it creates its canvas in an effect. React Strict Mode cleanup is supported.
Props such as `className`, `style`, and `data-*` attributes pass through to its
host div. The default height is 200px; override it using `style`. When sizing
through a CSS class, use `style={{ height: 'var(--marquee-height)' }}` or
`style={{ height: '100%' }}` inside a parent with an explicit height.

## Plain JavaScript

```html
<div id="marquee" style="height: 220px; background: #14141a; color: #f7f7f8"></div>
```

```js
import { mountMarquee } from '@ap.cx/gl-marquee'

const marquee = mountMarquee(document.querySelector('#marquee'), {
  message: 'Your studio. Your next idea.',
  fontFamily: 'sans-serif',
})

await marquee.ready

// Optional: explicit color changes, or refresh after a stylesheet change.
marquee.updateAppearance({ background: '#f7f7f8', text: '#14141a' })
marquee.refresh()

// Call when removing the host or leaving the page in an SPA.
marquee.destroy()
```

The host needs a nonzero height. Its font family, weight, text color, and nearest
nontransparent background are used unless supplied explicitly. Define custom
`@font-face` rules in your application. Mounting waits for that font before the
first frame and uses the browser's fallback font if loading fails. Font binaries
and AP.CX branding are **not included**.

## Options

Both `mountMarquee` and `GLMarquee` accept:

| Option | Default | Meaning |
| --- | --- | --- |
| `message` | Required | Nonempty text to repeat. |
| `fontFamily` | Host's computed family | CSS family list, with quoted names when needed. |
| `fontWeight` | Host's computed weight | CSS font weight, e.g. `400` or `'bold'`. |
| `fontSize` | Responsive | Fixed CSS pixel size, if supplied. |
| `mode` | `'footer-banner'` | Large footer type; `'standalone-preview'` uses smaller type for taller boards. |
| `appearance` | Host's computed colors | `{ background, text, textAlpha? }`, with browser-supported CSS colors. |
| `speed` | `0.12` | Text repetitions per second. Negative reverses direction; zero stops scrolling. |
| `waveAmplitude` | `0.019` | Displacement as a fraction of the text atlas width. Zero removes the wave. |
| `waveFrequency` | `2.1` | Wave phase in radians per second. |
| `reducedMotion` | System preference | `true` freezes at time zero; `false` explicitly enables motion. |

Without `textAlpha`, subtle opacity is chosen to suit the background. Supply a
value between 0 and 1 for explicit opacity. `speed: 0` still allows the wave to
animate; set `reducedMotion: true` to freeze the entire scene.

Mounting handles resize, device pixel ratio (capped at 2), light/dark system
changes, and common ancestor theme changes (`class`, `style`, `data-theme`).
Use `refresh()` for other CSS changes. Font changes require remounting.
Animation pauses while the document is hidden. The renderer restores resources
after WebGL context loss. When WebGL2 is unavailable, it renders static text
with Canvas 2D.

The animation is decorative and its canvas is hidden from assistive technology.
The React host is also `aria-hidden` by default. Place meaningful text in regular
HTML elsewhere. Low default opacity is intended for decoration.

## Control the frames yourself

For video tools, custom loops, and deterministic previews:

```js
import { createMarqueeRenderer } from '@ap.cx/gl-marquee'

await document.fonts.load('400 96px "Your Font"', 'Your message')
const renderer = createMarqueeRenderer({
  canvas: document.querySelector('canvas'),
  message: 'Your message',
  fontFamily: '"Your Font", sans-serif',
  appearance: { background: '#14141a', text: '#f7f7f8' },
})
renderer.resize({ width: 1280, height: 220, dpr: 2 })
renderer.render(1.5) // seconds
renderer.updateAppearance({ background: '#fff', text: '#111' })
renderer.destroy()
```

This API performs no font loading, animation scheduling, resizing observation,
or reduced-motion detection. Its default font is `sans-serif`, weight 400.
Call it only in a browser. Importing the package requires no browser globals.

## Develop and publish

Inside the AP.CX repository:

```sh
pnpm install
pnpm run build:marquee
pnpm run test:marquee
```

Or copy this entire folder into a separate project:

```sh
npm install
npm test
npm pack --dry-run
```

For a browser demo, build, serve this folder with a static HTTP server, and open
`examples/index.html`. No bundler or React is needed for the demo.

Before the first release, confirm the name/version and MIT license below, log
into an npm account with publish access to the `@ap.cx` organization, then run
from **this package directory**:

```sh
npm login
npm publish --dry-run
npm publish --access public
```

The public access flag follows [npm's scoped package publishing instructions](https://docs.npmjs.com/creating-and-publishing-scoped-public-packages/).
Publishing may prompt for your account's two-factor authentication.
`prepack` and `prepublishOnly` build and test before creating a release. Only
compiled `dist` files, this README, the license, and package metadata are packed;
no font assets, site files, examples, or test fixtures are shipped.
For later releases, increment the package version before publishing.

## License

MIT for this package's code. Fonts are supplied by the consuming project and
retain their own licenses.
