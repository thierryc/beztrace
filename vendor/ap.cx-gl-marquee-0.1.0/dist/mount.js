import { createMarqueeRenderer } from './renderer.js';
/** Mount one decorative canvas. The host must have a nonzero CSS height. */
export function mountMarquee(host, options) {
    const doc = host.ownerDocument;
    const view = doc.defaultView;
    if (!view)
        throw new Error('mountMarquee requires a browser document');
    const computed = view.getComputedStyle(host);
    const fontFamily = options.fontFamily ?? computed.fontFamily;
    const fontWeight = options.fontWeight ?? computed.fontWeight;
    const canvas = doc.createElement('canvas');
    canvas.setAttribute('aria-hidden', 'true');
    canvas.style.display = 'block';
    canvas.style.pointerEvents = 'none';
    let appearanceOverride = options.appearance;
    function resolveAppearance() {
        if (appearanceOverride)
            return appearanceOverride;
        let background = 'rgb(255, 255, 255)';
        for (let node = host; node; node = node.parentElement) {
            const color = view.getComputedStyle(node).backgroundColor;
            if (color !== 'transparent' && color !== 'rgba(0, 0, 0, 0)') {
                background = color;
                break;
            }
        }
        return { background, text: view.getComputedStyle(host).color };
    }
    // Validate and create before mutating the host.
    const renderer = createMarqueeRenderer({ ...options, canvas, fontFamily, fontWeight, appearance: resolveAppearance() });
    host.append(canvas);
    const motion = view.matchMedia('(prefers-reduced-motion: reduce)');
    const scheme = view.matchMedia('(prefers-color-scheme: dark)');
    let disposed = false;
    let started = false;
    let rafId = 0;
    const isReduced = () => options.reducedMotion ?? motion.matches;
    function resize() {
        const rect = host.getBoundingClientRect();
        renderer.updateAppearance(resolveAppearance());
        renderer.resize({ width: rect.width, height: rect.height, dpr: view.devicePixelRatio || 1 });
    }
    function draw(now) {
        rafId = 0;
        if (disposed || !started || doc.hidden)
            return;
        renderer.render(isReduced() ? 0 : now / 1000);
        if (!isReduced())
            rafId = view.requestAnimationFrame(draw);
    }
    function refresh() {
        if (disposed)
            return;
        view.cancelAnimationFrame(rafId);
        rafId = 0;
        resize();
        draw(view.performance.now());
    }
    const observer = typeof view.ResizeObserver === 'function' ? new view.ResizeObserver(refresh) : null;
    observer?.observe(host);
    if (!observer)
        view.addEventListener('resize', refresh);
    // Track common theme switches without rebuilding the renderer each frame.
    const themeObserver = new view.MutationObserver(refresh);
    for (let node = host; node; node = node.parentElement) {
        themeObserver.observe(node, { attributes: true, attributeFilter: ['class', 'style', 'data-theme'] });
    }
    motion.addEventListener('change', refresh);
    scheme.addEventListener('change', refresh);
    doc.addEventListener('visibilitychange', refresh);
    canvas.addEventListener('webglcontextrestored', refresh);
    const fontReady = doc.fonts
        ? Promise.resolve().then(() => doc.fonts.load(`${fontWeight} ${options.fontSize ?? 96}px ${fontFamily}`, options.message)).catch(() => [])
        : Promise.resolve([]);
    const ready = fontReady.then(() => {
        if (disposed)
            return;
        started = true;
        refresh();
    });
    return {
        ready,
        refresh,
        updateAppearance(appearance) {
            appearanceOverride = appearance;
            refresh();
        },
        destroy() {
            if (disposed)
                return;
            disposed = true;
            view.cancelAnimationFrame(rafId);
            observer?.disconnect();
            themeObserver.disconnect();
            view.removeEventListener('resize', refresh);
            motion.removeEventListener('change', refresh);
            scheme.removeEventListener('change', refresh);
            doc.removeEventListener('visibilitychange', refresh);
            canvas.removeEventListener('webglcontextrestored', refresh);
            renderer.destroy();
            canvas.remove();
        },
    };
}
