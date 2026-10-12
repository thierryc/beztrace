const MAX_RENDER_DPR = 2;
const GRID_COLUMNS = 128;
const GRID_ROWS = 64;
const SAFE_MAX_ATLAS_TEXTURE_SIZE = 8192;
const DEFAULT_TEXT_ALPHA_MIN = 0.12;
const DEFAULT_TEXT_ALPHA_MAX = 0.2;
const DEFAULT_TEXT_TARGET_CONTRAST = 1.46;
const LIGHT_TEXT_ALPHA_MIN = 0.16;
const LIGHT_TEXT_ALPHA_MAX = 0.24;
const LIGHT_TEXT_TARGET_CONTRAST = 1.62;
const LIGHT_SURFACE_LUMINANCE_THRESHOLD = 0.5;
const vertexSource = `#version 300 es
precision highp float;

in vec2 aUnit;

uniform vec2 uResolution;
uniform vec2 uQuadSize;
uniform vec2 uQuadOffset;

out vec2 vUv;

void main() {
  vec2 local = aUnit * uQuadSize;
  vec2 position = uQuadOffset + local;

  vec2 clip = vec2(
    (position.x / max(uResolution.x, 1.0)) * 2.0 - 1.0,
    1.0 - (position.y / max(uResolution.y, 1.0)) * 2.0
  );

  gl_Position = vec4(clip, 0.0, 1.0);
  vUv = aUnit;
}
`;
const fragmentSource = `#version 300 es
precision highp float;

in vec2 vUv;
out vec4 outColor;

uniform sampler2D uAtlas;
uniform vec2 uAtlasSize;
uniform vec2 uQuadSize;
uniform float uTime;
uniform float uSpeed;
uniform float uWaveAmplitude;
uniform float uWaveFrequency;
uniform vec3 uTextColor;
uniform float uTextAlpha;

float sampleAtlas(vec2 uv) {
  if (uv.y < 0.0 || uv.y > 1.0) {
    return 0.0;
  }

  return texture(uAtlas, vec2(fract(uv.x), uv.y)).a;
}

void main() {
  float localX = vUv.x * uQuadSize.x;
  float localY = vUv.y;
  float wave = sin(localY * 3.4 + uTime * uWaveFrequency) * (uAtlasSize.x * uWaveAmplitude);
  float scroll = uTime * (uAtlasSize.x * uSpeed);
  vec2 tuv = vec2((localX + scroll + wave) / max(uAtlasSize.x, 1.0), localY);
  float mask = sampleAtlas(tuv);
  if (mask <= 0.001) {
    discard;
  }

  outColor = vec4(uTextColor, mask * uTextAlpha);
}
`;
export function createMarqueeRenderer({ appearance, canvas, message, mode = 'footer-banner', fontFamily = 'sans-serif', fontWeight = 400, fontSize: explicitFontSize, speed = 0.12, waveAmplitude = 0.019, waveFrequency = 2.1, }) {
    if (!message.trim())
        throw new TypeError('Marquee message must not be empty');
    for (const [name, value] of Object.entries({ speed, waveAmplitude, waveFrequency, fontSize: explicitFontSize })) {
        if (value !== undefined && (!Number.isFinite(value) || (name === 'fontSize' && value <= 0))) {
            throw new TypeError(`Invalid marquee ${name}`);
        }
    }
    const ownerDocument = canvas.ownerDocument;
    let destroyed = false;
    let contextLost = false;
    let unavailable = false;
    const measureCanvas = ownerDocument.createElement('canvas');
    const measureContext = measureCanvas.getContext('2d');
    if (!measureContext) {
        throw new Error('Unable to create text measurement context');
    }
    const measurementContext = measureContext;
    let appearanceState = normalizeAppearance(appearance, measurementContext);
    let atlasState = null;
    let metrics = { width: 1, height: 1, dpr: 1 };
    let shaderState = null;
    function handleContextLost(event) {
        event.preventDefault();
        contextLost = true;
    }
    function handleContextRestored() {
        disposeShaderState();
        contextLost = false;
        unavailable = false;
        atlasState = null;
    }
    function disposeShaderState() {
        if (!shaderState) {
            return;
        }
        shaderState.gl.deleteTexture(shaderState.atlasTexture);
        shaderState.gl.deleteBuffer(shaderState.vertexBuffer);
        shaderState.gl.deleteBuffer(shaderState.indexBuffer);
        shaderState.gl.deleteVertexArray(shaderState.vao);
        shaderState.gl.deleteProgram(shaderState.program);
        shaderState = null;
    }
    function resolveFontSize(width, height) {
        if (explicitFontSize !== undefined)
            return explicitFontSize;
        if (mode === 'footer-banner') {
            return clamp(Math.round(Math.max(width * 0.12, height * 1.08)), 96, 240);
        }
        return clampViewport(width, height, 76, 168, 0.11, 0.18);
    }
    function measureMessageWidth(messageText, fontSize) {
        measurementContext.font = `${fontWeight} ${fontSize}px ${fontFamily}`;
        return Math.ceil(measurementContext.measureText(messageText).width);
    }
    function resolveMaxAtlasTextureSize() {
        return shaderState
            ? shaderState.gl.getParameter(shaderState.gl.MAX_TEXTURE_SIZE)
            : SAFE_MAX_ATLAS_TEXTURE_SIZE;
    }
    function ensureAtlas() {
        const fontSize = resolveFontSize(metrics.width, metrics.height);
        const resolvedMessage = message.trim();
        const laneHeight = Math.round(fontSize * 1.34);
        const baseFontPixels = fontSize * metrics.dpr;
        const basePadding = Math.max(8, Math.round(fontSize * 0.14)) * metrics.dpr;
        const measuredBaseWidth = measureMessageWidth(resolvedMessage, baseFontPixels);
        const desiredPixelWidth = Math.max(1, measuredBaseWidth + basePadding * 2);
        const maxTextureSize = Math.max(1, resolveMaxAtlasTextureSize());
        const renderScale = Math.min(1, maxTextureSize / desiredPixelWidth, maxTextureSize / (laneHeight * metrics.dpr));
        if (atlasState &&
            atlasState.message === resolvedMessage &&
            atlasState.fontSize === fontSize &&
            atlasState.dpr === metrics.dpr &&
            atlasState.laneHeight === laneHeight &&
            atlasState.renderScale === renderScale) {
            return atlasState;
        }
        const nextCanvas = atlasState?.canvas ?? ownerDocument.createElement('canvas');
        const nextContext = atlasState?.context ?? nextCanvas.getContext('2d');
        if (!nextContext) {
            throw new Error('Unable to create atlas context');
        }
        const fontPixels = Math.max(1, Math.floor(baseFontPixels * renderScale));
        const padding = Math.max(1, Math.floor(basePadding * renderScale));
        nextContext.font = `${fontWeight} ${fontPixels}px ${fontFamily}`;
        const measuredWidth = Math.max(1, Math.ceil(nextContext.measureText(resolvedMessage).width));
        const pixelHeight = Math.min(maxTextureSize, Math.max(1, Math.floor(laneHeight * metrics.dpr * renderScale)));
        const pixelWidth = Math.min(maxTextureSize, Math.max(1, measuredWidth + padding * 2));
        nextCanvas.width = pixelWidth;
        nextCanvas.height = pixelHeight;
        nextContext.setTransform(1, 0, 0, 1, 0, 0);
        nextContext.clearRect(0, 0, nextCanvas.width, nextCanvas.height);
        nextContext.font = `${fontWeight} ${fontPixels}px ${fontFamily}`;
        nextContext.textAlign = 'left';
        nextContext.textBaseline = 'middle';
        nextContext.fillStyle = '#ffffff';
        nextContext.fillText(resolvedMessage, padding, nextCanvas.height / 2);
        atlasState = {
            canvas: nextCanvas,
            cssWidth: desiredPixelWidth / metrics.dpr,
            context: nextContext,
            dpr: metrics.dpr,
            cssHeight: laneHeight,
            fontSize,
            laneHeight,
            message: resolvedMessage,
            pixelHeight,
            pixelWidth,
            renderScale,
        };
        return atlasState;
    }
    function ensureShaderState() {
        if (contextLost || unavailable)
            return null;
        if (shaderState) {
            return shaderState;
        }
        const gl = canvas.getContext('webgl2', {
            alpha: true,
            antialias: true,
            depth: false,
            desynchronized: false,
            premultipliedAlpha: true,
            preserveDrawingBuffer: false,
            stencil: false,
        });
        if (!gl) {
            unavailable = true;
            return null;
        }
        const program = createProgram(gl);
        const mesh = createGridMesh(gl, GRID_COLUMNS, GRID_ROWS);
        const atlasTexture = createTexture(gl);
        shaderState = {
            gl,
            indexBuffer: mesh.indexBuffer,
            indexCount: mesh.indexCount,
            program,
            atlasTexture,
            textureKey: '',
            uniforms: {
                atlas: getUniform(gl, program, 'uAtlas'),
                atlasSize: getUniform(gl, program, 'uAtlasSize'),
                quadOffset: getUniform(gl, program, 'uQuadOffset'),
                quadSize: getUniform(gl, program, 'uQuadSize'),
                resolution: getUniform(gl, program, 'uResolution'),
                textAlpha: getUniform(gl, program, 'uTextAlpha'),
                textColor: getUniform(gl, program, 'uTextColor'),
                time: getUniform(gl, program, 'uTime'),
                speed: getUniform(gl, program, 'uSpeed'),
                waveAmplitude: getUniform(gl, program, 'uWaveAmplitude'),
                waveFrequency: getUniform(gl, program, 'uWaveFrequency'),
            },
            vao: mesh.vao,
            vertexBuffer: mesh.vertexBuffer,
        };
        return shaderState;
    }
    function updateAtlasTexture(state, atlas) {
        const key = `${atlas.message}:${atlas.fontSize}:${atlas.dpr}:${atlas.pixelWidth}:${atlas.pixelHeight}`;
        if (state.textureKey === key) {
            return;
        }
        state.textureKey = key;
        state.gl.bindTexture(state.gl.TEXTURE_2D, state.atlasTexture);
        state.gl.texImage2D(state.gl.TEXTURE_2D, 0, state.gl.RGBA, state.gl.RGBA, state.gl.UNSIGNED_BYTE, atlas.canvas);
        state.gl.bindTexture(state.gl.TEXTURE_2D, null);
    }
    function drawUnavailableMessage() {
        const context = canvas.getContext('2d');
        if (!context) {
            return;
        }
        const [bgR, bgG, bgB] = colorToRgba(appearanceState.background);
        const [textR, textG, textB, textAlpha] = colorToRgba(appearanceState.text);
        const fallbackAlpha = Math.max((appearanceState.textAlpha ?? 1) * textAlpha, 0.32);
        context.setTransform(1, 0, 0, 1, 0, 0);
        context.clearRect(0, 0, canvas.width, canvas.height);
        context.setTransform(metrics.dpr, 0, 0, metrics.dpr, 0, 0);
        context.fillStyle = toCssColor(bgR, bgG, bgB, 1);
        context.fillRect(0, 0, metrics.width, metrics.height);
        context.fillStyle = toCssColor(textR, textG, textB, fallbackAlpha);
        context.font = `${fontWeight} ${Math.min(explicitFontSize ?? 32, metrics.height * 0.6)}px ${fontFamily}`;
        context.textAlign = 'center';
        context.textBaseline = 'middle';
        context.fillText(message, metrics.width / 2, metrics.height / 2, metrics.width * 0.95);
    }
    canvas.addEventListener('webglcontextlost', handleContextLost);
    canvas.addEventListener('webglcontextrestored', handleContextRestored);
    return {
        resize(nextMetrics) {
            if (destroyed)
                return;
            for (const value of Object.values(nextMetrics)) {
                if (!Number.isFinite(value))
                    throw new TypeError('Marquee metrics must be finite');
            }
            metrics = {
                dpr: clamp(nextMetrics.dpr, 1, MAX_RENDER_DPR),
                height: Math.max(1, Math.round(nextMetrics.height)),
                width: Math.max(1, Math.round(nextMetrics.width)),
            };
            const pixelWidth = Math.max(1, Math.round(metrics.width * metrics.dpr));
            const pixelHeight = Math.max(1, Math.round(metrics.height * metrics.dpr));
            canvas.style.width = `${metrics.width}px`;
            canvas.style.height = `${metrics.height}px`;
            if (canvas.width !== pixelWidth) {
                canvas.width = pixelWidth;
            }
            if (canvas.height !== pixelHeight) {
                canvas.height = pixelHeight;
            }
        },
        render(timeSeconds) {
            if (destroyed || contextLost)
                return;
            if (!Number.isFinite(timeSeconds))
                throw new TypeError('Marquee time must be finite');
            const state = ensureShaderState();
            if (!state) {
                drawUnavailableMessage();
                return;
            }
            const atlas = ensureAtlas();
            updateAtlasTexture(state, atlas);
            const [textR, textG, textB, textAlpha] = colorToRgba(appearanceState.text);
            const [bgR, bgG, bgB] = colorToRgba(appearanceState.background);
            const quadY = Math.round((metrics.height - atlas.cssHeight) / 2);
            state.gl.viewport(0, 0, canvas.width, canvas.height);
            state.gl.disable(state.gl.DEPTH_TEST);
            state.gl.enable(state.gl.BLEND);
            state.gl.blendFunc(state.gl.SRC_ALPHA, state.gl.ONE_MINUS_SRC_ALPHA);
            state.gl.clearColor(bgR, bgG, bgB, 1);
            state.gl.clear(state.gl.COLOR_BUFFER_BIT);
            state.gl.useProgram(state.program);
            state.gl.bindVertexArray(state.vao);
            state.gl.activeTexture(state.gl.TEXTURE0);
            state.gl.bindTexture(state.gl.TEXTURE_2D, state.atlasTexture);
            state.gl.uniform1i(state.uniforms.atlas, 0);
            state.gl.uniform2f(state.uniforms.atlasSize, atlas.cssWidth, atlas.cssHeight);
            state.gl.uniform1f(state.uniforms.time, timeSeconds);
            state.gl.uniform1f(state.uniforms.speed, speed);
            state.gl.uniform1f(state.uniforms.waveAmplitude, waveAmplitude);
            state.gl.uniform1f(state.uniforms.waveFrequency, waveFrequency);
            state.gl.uniform2f(state.uniforms.resolution, metrics.width, metrics.height);
            state.gl.uniform2f(state.uniforms.quadSize, metrics.width, atlas.cssHeight);
            state.gl.uniform2f(state.uniforms.quadOffset, 0, quadY);
            state.gl.uniform1f(state.uniforms.textAlpha, (appearanceState.textAlpha ?? 1) * textAlpha);
            state.gl.uniform3f(state.uniforms.textColor, textR, textG, textB);
            state.gl.drawElements(state.gl.TRIANGLES, state.indexCount, state.gl.UNSIGNED_SHORT, 0);
            state.gl.bindTexture(state.gl.TEXTURE_2D, null);
            state.gl.bindVertexArray(null);
        },
        updateAppearance(nextAppearance) {
            if (destroyed)
                return;
            appearanceState = normalizeAppearance(nextAppearance, measurementContext);
        },
        destroy() {
            if (destroyed)
                return;
            destroyed = true;
            canvas.removeEventListener('webglcontextlost', handleContextLost);
            canvas.removeEventListener('webglcontextrestored', handleContextRestored);
            atlasState = null;
            disposeShaderState();
        },
    };
}
function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}
function clampViewport(width, height, min, max, vwFactor, vhFactor) {
    return clamp(Math.round(Math.min(width * vwFactor, height * vhFactor)), min, max);
}
function createGridMesh(gl, columns, rows) {
    const vertices = new Float32Array((columns + 1) * (rows + 1) * 2);
    const indices = new Uint16Array(columns * rows * 6);
    let vertexOffset = 0;
    for (let row = 0; row <= rows; row += 1) {
        const v = row / rows;
        for (let column = 0; column <= columns; column += 1) {
            const u = column / columns;
            vertices[vertexOffset] = u;
            vertices[vertexOffset + 1] = v;
            vertexOffset += 2;
        }
    }
    let indexOffset = 0;
    for (let row = 0; row < rows; row += 1) {
        for (let column = 0; column < columns; column += 1) {
            const topLeft = row * (columns + 1) + column;
            const topRight = topLeft + 1;
            const bottomLeft = topLeft + columns + 1;
            const bottomRight = bottomLeft + 1;
            indices[indexOffset] = topLeft;
            indices[indexOffset + 1] = bottomLeft;
            indices[indexOffset + 2] = topRight;
            indices[indexOffset + 3] = topRight;
            indices[indexOffset + 4] = bottomLeft;
            indices[indexOffset + 5] = bottomRight;
            indexOffset += 6;
        }
    }
    const vao = gl.createVertexArray();
    const vertexBuffer = gl.createBuffer();
    const indexBuffer = gl.createBuffer();
    if (!vao || !vertexBuffer || !indexBuffer) {
        throw new Error('Failed to create WebGL buffers');
    }
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
    gl.bindVertexArray(null);
    gl.bindBuffer(gl.ARRAY_BUFFER, null);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, null);
    return {
        vao,
        vertexBuffer,
        indexBuffer,
        indexCount: indices.length,
    };
}
function createProgram(gl) {
    const program = gl.createProgram();
    if (!program) {
        throw new Error('Failed to create shader program');
    }
    const vertexShader = createShader(gl, gl.VERTEX_SHADER, vertexSource);
    const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
    gl.attachShader(program, vertexShader);
    gl.attachShader(program, fragmentShader);
    gl.bindAttribLocation(program, 0, 'aUnit');
    gl.linkProgram(program);
    const linked = gl.getProgramParameter(program, gl.LINK_STATUS);
    gl.deleteShader(vertexShader);
    gl.deleteShader(fragmentShader);
    if (!linked) {
        const log = gl.getProgramInfoLog(program) ?? 'Unknown program link error';
        gl.deleteProgram(program);
        throw new Error(log);
    }
    return program;
}
function createShader(gl, type, source) {
    const shader = gl.createShader(type);
    if (!shader) {
        throw new Error('Failed to create shader');
    }
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        const log = gl.getShaderInfoLog(shader) ?? 'Unknown shader compile error';
        gl.deleteShader(shader);
        throw new Error(log);
    }
    return shader;
}
function createTexture(gl) {
    const texture = gl.createTexture();
    if (!texture) {
        throw new Error('Failed to create atlas texture');
    }
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, 1);
    gl.bindTexture(gl.TEXTURE_2D, null);
    return texture;
}
function getUniform(gl, program, name) {
    const location = gl.getUniformLocation(program, name);
    if (!location) {
        throw new Error(`Missing uniform ${name}`);
    }
    return location;
}
function normalizeAppearance(appearance, context) {
    // Let the browser resolve CSS color syntax (including named colors and hsl).
    function resolveColor(color) {
        context.fillStyle = '#000000';
        context.fillStyle = color;
        const resolved = context.fillStyle;
        if (resolved.startsWith('#') || /^rgba?\(/.test(resolved))
            return resolved;
        context.clearRect(0, 0, 1, 1);
        context.fillRect(0, 0, 1, 1);
        const [r = 0, g = 0, b = 0, a = 255] = context.getImageData(0, 0, 1, 1).data;
        return `rgba(${r}, ${g}, ${b}, ${a / 255})`;
    }
    appearance = { ...appearance, background: resolveColor(appearance.background), text: resolveColor(appearance.text) };
    if (appearance.textAlpha !== undefined && !Number.isFinite(appearance.textAlpha)) {
        throw new TypeError('Marquee textAlpha must be finite');
    }
    const resolvedTextAlpha = appearance.textAlpha ?? resolveDefaultTextAlpha(appearance.background, appearance.text);
    return {
        background: appearance.background,
        text: appearance.text,
        textAlpha: clamp(resolvedTextAlpha, 0, 1),
    };
}
function resolveDefaultTextAlpha(background, text) {
    const [backgroundRed, backgroundGreen, backgroundBlue] = colorToRgba(background);
    const [textRed, textGreen, textBlue, textColorAlpha] = colorToRgba(text);
    const effectiveTextAlpha = Math.max(textColorAlpha, 0.001);
    const backgroundRgb = [backgroundRed, backgroundGreen, backgroundBlue];
    const textRgb = [textRed, textGreen, textBlue];
    const backgroundLuminance = relativeLuminance(backgroundRgb);
    const isLightSurface = backgroundLuminance >= LIGHT_SURFACE_LUMINANCE_THRESHOLD;
    const alphaMin = isLightSurface ? LIGHT_TEXT_ALPHA_MIN : DEFAULT_TEXT_ALPHA_MIN;
    const alphaMax = isLightSurface ? LIGHT_TEXT_ALPHA_MAX : DEFAULT_TEXT_ALPHA_MAX;
    const targetContrast = isLightSurface
        ? LIGHT_TEXT_TARGET_CONTRAST
        : DEFAULT_TEXT_TARGET_CONTRAST;
    const maxContrast = contrastRatio(backgroundRgb, blendRgb(backgroundRgb, textRgb, alphaMax * effectiveTextAlpha));
    if (maxContrast <= targetContrast) {
        return alphaMax;
    }
    let low = alphaMin;
    let high = alphaMax;
    for (let iteration = 0; iteration < 12; iteration += 1) {
        const mid = (low + high) / 2;
        const nextContrast = contrastRatio(backgroundRgb, blendRgb(backgroundRgb, textRgb, mid * effectiveTextAlpha));
        if (nextContrast >= targetContrast) {
            high = mid;
        }
        else {
            low = mid;
        }
    }
    return high;
}
function colorToRgba(color) {
    const value = color.trim().toLowerCase();
    if (value.startsWith('#')) {
        const hex = value.slice(1);
        const expanded = hex.length === 3 || hex.length === 4
            ? hex
                .split('')
                .map((part) => part + part)
                .join('')
            : hex;
        const hasAlpha = expanded.length === 8;
        const red = Number.parseInt(expanded.slice(0, 2), 16) / 255;
        const green = Number.parseInt(expanded.slice(2, 4), 16) / 255;
        const blue = Number.parseInt(expanded.slice(4, 6), 16) / 255;
        const alpha = hasAlpha ? Number.parseInt(expanded.slice(6, 8), 16) / 255 : 1;
        return [red, green, blue, alpha];
    }
    const match = value.match(/rgba?\((.+)\)/);
    if (match) {
        const body = match[1] ?? '';
        let parts = body.trim().split(/\s*,\s*/);
        let alphaToken;
        if (parts.length === 1) {
            parts = body.trim().split(/\s+/);
            const slashIndex = parts.indexOf('/');
            if (slashIndex >= 0) {
                alphaToken = parts[slashIndex + 1];
                parts = parts.slice(0, slashIndex);
            }
        }
        else if (parts.length === 4) {
            alphaToken = parts[3];
        }
        const red = parseCssChannel(parts[0] ?? '0');
        const green = parseCssChannel(parts[1] ?? '0');
        const blue = parseCssChannel(parts[2] ?? '0');
        const alpha = alphaToken ? parseCssAlpha(alphaToken) : 1;
        return [red / 255, green / 255, blue / 255, alpha];
    }
    return [1, 1, 1, 1];
}
function parseCssAlpha(token) {
    const trimmed = token.trim();
    if (trimmed.endsWith('%')) {
        return clamp(Number.parseFloat(trimmed) / 100, 0, 1);
    }
    return clamp(Number.parseFloat(trimmed), 0, 1);
}
function parseCssChannel(token) {
    const trimmed = token.trim();
    if (trimmed.endsWith('%')) {
        return clamp((Number.parseFloat(trimmed) / 100) * 255, 0, 255);
    }
    return clamp(Number.parseFloat(trimmed), 0, 255);
}
function toCssColor(red, green, blue, alpha) {
    return `rgba(${Math.round(red * 255)}, ${Math.round(green * 255)}, ${Math.round(blue * 255)}, ${alpha})`;
}
function blendRgb(background, foreground, alpha) {
    return [
        background[0] * (1 - alpha) + foreground[0] * alpha,
        background[1] * (1 - alpha) + foreground[1] * alpha,
        background[2] * (1 - alpha) + foreground[2] * alpha,
    ];
}
function contrastRatio(colorA, colorB) {
    const luminanceA = relativeLuminance(colorA);
    const luminanceB = relativeLuminance(colorB);
    const lighter = Math.max(luminanceA, luminanceB);
    const darker = Math.min(luminanceA, luminanceB);
    return (lighter + 0.05) / (darker + 0.05);
}
function relativeLuminance([red, green, blue]) {
    const linearRed = toLinearSrgb(red);
    const linearGreen = toLinearSrgb(green);
    const linearBlue = toLinearSrgb(blue);
    return 0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue;
}
function toLinearSrgb(value) {
    if (value <= 0.04045) {
        return value / 12.92;
    }
    return ((value + 0.055) / 1.055) ** 2.4;
}
