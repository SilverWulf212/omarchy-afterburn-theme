// Lightning cursor for Ghostty (`custom-shader`).
// Pressing Enter (a prompt sent in Claude Code, a command run in zsh, via
// `cursor-fx signal`) sends a surge of electric-blue current from the cursor
// along the lines of Claude Code's input box out to both edges: a bright head,
// three wandering strands behind it, sparks spraying off, and a glow that
// lingers. In a shell, with no box, the surge runs under the line that was
// sent. Typing throws off small
// sparks (with TYPING_LINE_SPARK, one of them jumps to a box line), and an idle
// cursor crackles faintly now and then. A jump along the cursor's own row
// (delete-all, Home) strikes a jagged, branching bolt from where it was to
// where it lands (JUMP_EFFECTS); jumps to another row never do, so a program
// redrawing stays quiet. Only the area around the bolt, the lines and the
// cursor changes. Sparks and crackle skip the off half of a blinking cursor.
// Its cursor is charged: small jagged arcs of current keep jumping between
// points on its outline, in a faint ice-blue glow. The prompt mark (❯) on its
// line takes the same style.
// The input box's lines are live wires: a faint current flows along them and a
// spark runs across now and then.
// TEXT_COLOR shows your text (Claude Code's input box and sent prompts, zsh's
// command line) in the cursor's color, as easy to read as the terminal's text.

// macOS: true. On Linux, change it to false (install.sh does this for you);
// otherwise the effect plays upside down.
#define Y_DOWN true

// A translucent window (background-opacity below 1): `cursor-fx` sets this from your Ghostty
// config when you switch effects, and install.sh on install. Off, its code costs nothing.
#define SEE_THROUGH false

// A light theme (or a light:…,dark:… pair): `cursor-fx` sets this from your Ghostty config when
// you switch effects, and install.sh on install. Off, the light-theme code costs nothing.
#define LIGHT_THEME false

// Panes drawn inside the terminal (herdr, tmux): `cursor-fx` turns this on when you pick an effect
// inside one, or with `cursor-fx panes on|off`. The input box is then found from the cursor's
// column and the effects stay in the cursor's pane. Off, its code costs nothing.
#define PANES false

// --- settings: the ones worth a tweak (edit and save, or use `cursor-fx edit`; Ghostty reloads on Command+Shift+,) ---
// -- Typing
const bool  TYPE_EFFECT    = true;  // sparks fly off the cursor with every keystroke
const float SPARKS         = 4.0;   // sparks per keystroke
// -- Enter & done
const bool  ENTER_EFFECT   = true;  // surge along the input box lines on Enter (`cursor-fx enter off` pauses every effect's Enter)
const bool  DONE_EFFECT   = true;  // play it again, from the edges inward, when Claude finishes answering (Stop hook) or a long zsh command ends
const float SEND_DURATION  = 0.6;  // seconds the surge and its glow last
// -- Delete-all
const bool  JUMP_EFFECTS   = true;  // strike a bolt when the cursor jumps along its row (`cursor-fx jumps on|off`)
// -- Cursor
const bool  CURSOR_EFFECT  = true;  // the cursor's own look: charged, small arcs of current jumping around it
const bool  IDLE_EFFECTS   = true;  // the faint idle crackle (`cursor-fx idle on|off`; off keeps the screen calm)
// -- Prompt mark
const bool  PROMPT_EFFECT  = true;  // the prompt mark (❯) at the start of the cursor's line: charged: ice-blue with a white-hot core that flickers, a spark running along it
// -- Box lines
const bool  LINE_TINT      = true;  // the input box lines take the cursor's color (a plain color, no glow)
const float LINE_COLOR     = 0.42;  // how much of the cursor's color the lines take, at their own brightness (0 to 1)
const bool  LINE_EFFECT    = false;  // the input box lines, always: a live wire: current flowing along them, a spark running across now and then
const float LINE_STRENGTH  = 1.0;  // how bright the animated lines are
// -- Your text
const bool  TEXT_COLOR     = false;  // your text in the cursor's color (Claude Code's input box and your sent prompts, zsh's command line), as easy to read as the terminal's text; dim and colored text stay as they are
const bool  TEXT_TYPING    = true;  // the text you're typing (Claude Code's input box, zsh's command line)
const bool  TEXT_SENT      = true;  // your sent prompts (the grey bars Claude Code shows them on)
// -- Look
const bool  SUBTLE         = false;  // the calm version for every day: smaller, dimmer moments and a quieter cursor (`cursor-fx subtle on|off`)
const vec3  BOLT_COLOR     = vec3(0.30, 0.62, 1.00);  // the glow of the bolts and sparks
const vec3  CORE_COLOR     = vec3(0.88, 0.95, 1.00);  // their hot center
const float GLOW_RADIUS    = 0.35;  // how far the glow reaches, in character heights

// --- fine-tuning ---
// -- Typing
const bool  PHRASE_EFFECT  = true;  // picking a character or phrase from your input method plays the typing effect too (like one keystroke)
const float SPARK_DURATION = 0.2;  // seconds the sparks last
const bool  TYPING_LINE_SPARK = false;  // each keystroke also throws a spark from the cursor to a box line
// -- Enter & done
const float SURGE_TIME     = 0.3;  // seconds the surge's head takes to cross the window
// -- Delete-all
const float BOLT_DURATION  = 0.35;  // seconds a bolt flickers
const float BOLT_JAGGED    = 0.12;  // how far a bolt wanders sideways, as a share of its length
const float BRANCHES       = 2.0;   // side branches per bolt
// -- Cursor
const float IDLE_CHANCE    = 0.5;  // how likely the faint idle crackle is each time it gets a chance (0 to 1)
const float IDLE_PERIOD    = 3.0;  // seconds between the idle crackle's chances
const float IDLE_DURATION  = 0.15;  // seconds an idle crackle lasts
// -- Box lines
// -- Your text
const float TEXT_TINT      = 1.0;  // how much of the cursor's color your text takes
// -- Look
const float BOLT_WIDTH     = 0.06;  // the hot core's thickness, in character heights
// --- fixed values (not shown in the panel; edit them here if you must) ---
#define LINE_CRACKLE 2.0  // how far the line crackles either side of where that spark lands, in characters
#define LINE_REACH 0.8  // how close to a box line the surge lights pixels, in character heights
#define BOLT_MIN_CELLS 3.0  // moves this long or longer are a jump (in characters; a row counts as two)
#define MAX_JAGGED 2.5  // the most a bolt wanders sideways, in character heights
#define MAX_BRANCH 4.0   // longest side branch, in character heights
#define CURSOR_STRENGTH 1.0  // how strong the cursor's own look is
#define FLICKER_RATE 30.0  // flicker steps per second
#define SETTLE 0.04  // seconds the cursor must stay put before an effect starts
#define JUMP_SETTLE 0.12  // the same after a jump (gives the Enter signal time to arrive)

// Ghostty hands shaders y-down pixels on macOS (Metal) and y-up ones on Linux
// (OpenGL). The effects are written y-up (embers rise, curtains hang upward),
// so with Y_DOWN (top of the file) mainImage turns its pixel and the cursors
// over and screenAt() turns every read of the screen back.

// Light themes: the effects add light, which a light background can't show. So on a light
// background everything below works on an inverted picture (screen and colors), and mainImage()
// inverts the result back: light becomes ink in the same color. A dark theme is untouched.
bool lightTheme() {
    return LIGHT_THEME && dot(iBackgroundColor, vec3(0.2126, 0.7152, 0.0722)) > 0.5;
}

// Whether the screen texture is linear (see colorDist()), set once per pixel by mainImage(). The
// inversion has to happen in sRGB, like the colors', or the two would no longer match.
bool screenLinear = false;

vec3 themeFlip(vec3 c) {
    if (!screenLinear) return 1.0 - c;
    c = clamp(c, 0.0, 1.0);
    c = 1.0 - mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// A built-in color, inverted like the theme's on a light background so its ink keeps the hue.
vec3 themeColor(vec3 c) {
    return lightTheme() ? 1.0 - c : c;
}

#define iBackgroundColor (lightTheme() ? 1.0 - iBackgroundColor : iBackgroundColor)
#define iForegroundColor (lightTheme() ? 1.0 - iForegroundColor : iForegroundColor)
#define iCursorText (lightTheme() ? 1.0 - iCursorText : iCursorText)
#define iCurrentCursorColor (lightTheme() ? vec4(1.0 - iCurrentCursorColor.rgb, iCurrentCursorColor.a) : iCurrentCursorColor)
#define iPreviousCursorColor (lightTheme() ? vec4(1.0 - iPreviousCursorColor.rgb, iPreviousCursorColor.a) : iPreviousCursorColor)

// The terminal's color at uv (0 to 1, y-up).
vec4 screenAt(vec2 uv) {
    vec4 c = texture(iChannel0, Y_DOWN ? vec2(uv.x, 1.0 - uv.y) : uv);
    // A translucent window: Ghostty hands the screen over premultiplied, so the background
    // would never match iBackgroundColor. mainImage() multiplies again at the end.
    if (SEE_THROUGH && c.a > 0.0 && c.a < 1.0) c.rgb /= c.a;
    if (lightTheme()) c.rgb = themeFlip(c.rgb);
    return c;
}

// A cursor rectangle with .xy its top-left corner in y-up pixels. Ghostty gives
// the "-X, +Y corner": bottom-left on macOS, top-left on Linux.
vec4 upCursor(vec4 c) {
    return Y_DOWN ? vec4(c.x, iResolution.y - c.y + c.w, c.zw) : c;
}

// One cell's width. On a Chinese character the block cursor covers two cells (it is
// then about as wide as it is tall; a single cell is about twice as tall as wide).
float cellWOf(vec4 c) {
    return iCurrentCursorStyle == CURSORSTYLE_BLOCK && c.w < 1.4 * c.z ? 0.5 * c.z : c.z;
}

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

// Ghostty passes colors in sRGB, but the shader works in linear light.
vec3 sRGBToLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// Distance from a screen pixel to a uniform color, in whichever form (sRGB or
// linear) the screen texture turns out to use.
float colorDist(vec3 s, vec3 c) {
    return min(distance(s, c), distance(s, sRGBToLinear(c)));
}
// --- Panes (PANES): a box line through the cursor's column ---
// The input box lines run across the pane Claude Code is in, not across the window: a sidebar
// or a split (herdr, tmux) can take the rest. With PANES a box line is found from the cursor's
// column: it passes through that column, is one color for at least BOX_LINE_CELLS cells around
// it (a zsh underline or a row of text never is) and has background four pixels above and below.
#define BOX_LINE_CELLS 24.0

float boxColumnX() {
    vec4 c = upCursor(iCurrentCursor);
    return c.x + 0.5 * cellWOf(c);
}

bool onBoxLine(float y, vec2 res) {
    float w = cellWOf(upCursor(iCurrentCursor)), x = boxColumnX();
    vec3 ink = screenAt(vec2(x, y) / res).rgb;
    if (colorDist(ink, iBackgroundColor) < 0.03
            || colorDist(screenAt(vec2(x, y + 4.0) / res).rgb, iBackgroundColor) > 0.03
            || colorDist(screenAt(vec2(x, y - 4.0) / res).rgb, iBackgroundColor) > 0.03) return false;
    float cells = 0.0;
    for (int side = 0; side < 2; side++) {
        float dir = side == 0 ? 1.0 : -1.0;
        for (int i = 1; i <= 12; i++) {
            float at = x + dir * float(i) * 2.0 * w;
            if (at < 0.0 || at > res.x || distance(screenAt(vec2(at, y) / res).rgb, ink) > 0.03) break;
            cells += 2.0;
        }
    }
    return cells >= BOX_LINE_CELLS;
}

// A box line at height y: with PANES through the cursor's column (above), else across the whole
// window: ink at five points along it and background four pixels above and below.
bool boxLineAt(float y, vec2 res) {
    if (PANES) return onBoxLine(y, res);
    vec3 xs = vec3(0.45, 0.66, 0.88) * res.x;
    if (colorDist(screenAt(vec2(xs.x, y) / res).rgb, iBackgroundColor) < 0.03
            || colorDist(screenAt(vec2(xs.y, y) / res).rgb, iBackgroundColor) < 0.03
            || colorDist(screenAt(vec2(xs.z, y) / res).rgb, iBackgroundColor) < 0.03) return false;
    // Claude Code's box lines run across the whole window; a shorter line (zsh's
    // underline under a path, a rule in some output) is not one.
    if (colorDist(screenAt(vec2(0.05 * res.x, y) / res).rgb, iBackgroundColor) < 0.03
            || colorDist(screenAt(vec2(0.95 * res.x, y) / res).rgb, iBackgroundColor) < 0.03) return false;
    if (colorDist(screenAt(vec2(xs.x, y + 4.0) / res).rgb, iBackgroundColor) > 0.03
            || colorDist(screenAt(vec2(xs.x, y - 4.0) / res).rgb, iBackgroundColor) > 0.03) return false;
    return true;
}


// Is the cursor drawn in this frame, or blinked off? Checks three points along
// its left edge: each counts if it looks more like the cursor color than like
// the background or the text color. Two of three must match.
bool cursorDrawn(vec2 lo, vec4 cur, vec2 res) {
    // A drawn cursor fills its rectangle up to the corners, where letters don't reach:
    // both top corners must be its color (and one more point lower down). While an input
    // method composes, Ghostty hides the cursor and the first pinyin letter sits in its
    // cell; with a light cursor color that letter alone used to pass for the cursor.
    vec2 ins = vec2(min(1.5, 0.5 * cur.z), min(1.5, 0.5 * cur.w));
    float top = 0.0, low = 0.0;
    for (int k = 0; k < 5; k++) {
        vec2 at = k == 0 ? vec2(lo.x + ins.x, lo.y + cur.w - ins.y) : k == 1 ? vec2(lo.x + cur.z - ins.x, lo.y + cur.w - ins.y)
                : k == 2 ? vec2(lo.x + ins.x, lo.y + ins.y) : k == 3 ? vec2(lo.x + cur.z - ins.x, lo.y + ins.y) : vec2(lo.x + ins.x, lo.y + 0.5 * cur.w);
        vec3 s = screenAt(at / res).rgb;
        float dc = colorDist(s, iCurrentCursorColor.rgb);
        float hit = step(dc, colorDist(s, iBackgroundColor)) * step(dc, colorDist(s, iForegroundColor));
        if (k < 2) top += hit; else low += hit;
    }
    return top >= 2.0 && low >= 1.0;
}

// Enter (a prompt sent in Claude Code, a command run in zsh): `cursor-fx signal`
// sets the lowest bit of the cursor color's blue value for a moment, and flips the
// red value's lowest bit with every signal, so a new one is always a change of
// color. True while this frame belongs to that moment: the signal just started
// (blue turned odd, or red flipped while it was), or `back`: the cursor jumped while
// it was on in a way that means the same Enter (Claude Code clearing its input box
// after the signal arrived).
bool oddByte(float v) {
    if (lightTheme()) v = 1.0 - v;  // the signal's bit is in the real color
    return mod(floor(v * 255.0 + 0.5), 2.0) > 0.5;
}

bool signalFlipped() {
    return oddByte(iCurrentCursorColor.r) != oddByte(iPreviousCursorColor.r);
}

bool enterSignal(bool back) {
    return oddByte(iCurrentCursorColor.b) && (!oddByte(iPreviousCursorColor.b) || signalFlipped() || back);
}

// Done (Claude Code finished answering, via its Stop hook; a long zsh command
// finished): `cursor-fx signal done` sets the green value's lowest bit instead.
bool doneSignal(bool back) {
    return oddByte(iCurrentCursorColor.g) && !oddByte(iCurrentCursorColor.b)
        && (!oddByte(iPreviousCursorColor.g) || signalFlipped() || back);
}

// paneWall() is further down, with the pane checks.
bool paneWall(float left, float w, vec4 cur, vec2 res);

// The height of the line that was just sent, for a shell (no input box): the
// cursor's row, or the row above when the cursor is at the left edge. Claude
// Code's sent prompt would show on a lighter bar above the input box; that is
// looked for first (right end of a row off the background near its top and
// bottom), so the same shader works if the box lines ever go missing.
float sentRowY(vec4 cur, float cellW, vec2 res) {
    float x = res.x - max(0.06 * res.x, 3.0 * cellW);
    for (int k = 1; k <= 12; k++) {
        float rowLo = cur.y + float(k - 1) * cur.w;
        if (rowLo + cur.w > res.y) break;
        vec3 a = screenAt(vec2(x, rowLo + 0.2 * cur.w) / res).rgb;
        vec3 b = screenAt(vec2(x, rowLo + 0.8 * cur.w) / res).rgb;
        if (colorDist(a, iBackgroundColor) > 0.012 && colorDist(b, iBackgroundColor) > 0.012) return rowLo + 0.5 * cur.w;
    }
    // At the left edge of the window, or with PANES of its pane (next to herdr's sidebar, in a split).
    bool atLeft = cur.x <= 1.5 * cellW || (PANES && paneWall(cur.x - cellW, cellW, cur, res));
    return atLeft ? cur.y + 0.5 * cur.w : cur.y - 0.5 * cur.w;
}

vec2 rotate(vec2 v, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

// Smooth random wander along a bolt, between -1 and 1 (three octaves of value noise).
float wander(float t, float seed) {
    float v = 0.0, amp = 0.6, freq = 3.0;
    for (int o = 0; o < 3; o++) {
        float x = t * freq + seed * 13.1;
        float i = floor(x), u = fract(x);
        v += amp * mix(hash11(i), hash11(i + 1.0), u * u * (3.0 - 2.0 * u));
        freq *= 2.3;
        amp *= 0.5;
    }
    return v / 1.05 * 2.0 - 1.0;
}

// Point at position t (0 to 1) along a jagged bolt from a to b; the ends stay put.
vec2 boltPoint(vec2 a, vec2 b, float t, float jag, float seed) {
    vec2 dir = b - a;
    vec2 n = vec2(-dir.y, dir.x) / max(length(dir), 1e-3);
    return a + dir * t + n * jag * sin(3.14159 * t) * wander(t, seed);
}

// Distance from p to a bolt made of `segs` straight pieces. Only the five pieces
// nearest to p along the bolt are checked, which is exact for the bright core
// and keeps long bolts cheap.
float boltDist(vec2 p, vec2 a, vec2 b, float jag, float seed, float segs) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    float first = clamp(floor(t * segs) - 2.0, 0.0, segs - 1.0);
    vec2 prevPt = boltPoint(a, b, first / segs, jag, seed);
    float d = 1e9;
    for (int i = 1; i <= 5; i++) {
        float k = first + float(i);
        if (k > segs) break;
        vec2 pt = boltPoint(a, b, k / segs, jag, seed);
        d = min(d, segDist(p, prevPt, pt));
        prevPt = pt;
    }
    return d;
}

// Light from a bolt at distance d: thin hot core plus soft glow in `glowCol` (linear).
vec3 boltLightC(float d, float width, float glow, float strength, vec3 glowCol) {
    float core = 1.0 - smoothstep(width * 0.5, width, d);
    float halo = exp(-d / glow);
    return (sRGBToLinear(CORE_COLOR) * core + glowCol * halo * 0.8) * strength;
}

vec3 boltLight(float d, float width, float glow, float strength) {
    return boltLightC(d, width, glow, strength, sRGBToLinear(themeColor(BOLT_COLOR)));
}

// The bolt's flicker: the first two steps always strike, later ones at random.
float flickerOn(float t) {
    float stepId = floor(t * FLICKER_RATE);
    return stepId < 2.0 ? 1.0 : step(0.35, hash11(stepId + mod(iTimeCursorChange, 100.0)));
}

// Claude Code draws its input box with a thin grey line across the whole width
// above and below the typed text. Looks for the nearest such line within
// `reach` of the pixel: ink at three points along the width with background a
// few pixels above and below (a letter or the sent-message bar doesn't
// qualify), outside the cursor's own row, at most 4 rows above its center
// (the box grows upward for a long prompt) and 1.6 rows below it (the status
// lines never count). Returns its height, or -1.
float boxLineY(vec2 p, vec2 center, vec4 cur, vec2 res, float reach) {
    float stepPx = max(1.0, reach / 40.0);
    for (int i = 0; i < 80; i++) {
        float dy = floor(float(i) * 0.5) * stepPx * (mod(float(i), 2.0) < 0.5 ? 1.0 : -1.0);
        if (abs(dy) > reach) break;
        float y = p.y + dy;
        if (y < 0.0 || y > res.y || y - center.y > 4.0 * cur.w || center.y - y > 1.6 * cur.w
                || (y > cur.y - cur.w && y < cur.y)) continue;
        if (!boxLineAt(y, res)) continue;
        return y;
    }
    return -1.0;
}

// A surge of current along the line at height lineY, out from x0 toward both
// edges: a bright head travelling at the front, three wandering strands behind
// it, sparks spraying off just behind the head, and a glow that lingers and
// fades over SEND_DURATION. t = seconds in.
vec3 surge(vec2 p, float lineY, float x0, float t, vec2 res, float cellH, float cellW, bool inward) {
    vec3 glowCol = sRGBToLinear(themeColor(BOLT_COLOR));
    float glowPx = GLOW_RADIUS * cellH * (SUBTLE ? 0.45 : 1.0);  // subtle: a tighter glow, one strand, no sparks
    float frontDist = t / SURGE_TIME * res.x;
    float side = inward ? (p.x < 0.5 * res.x ? 1.0 : -1.0) : (p.x < x0 ? -1.0 : 1.0);  // which way the head moves here
    float origin = inward ? (p.x < 0.5 * res.x ? 0.0 : res.x) : x0;                        // where it started on this side
    float headX = origin + side * frontDist;
    float behind = frontDist - abs(p.x - origin);  // > 0 once the head has passed this pixel
    float dy = p.y - lineY;
    float fade = pow(max(0.0, 1.0 - t / SEND_DURATION), 1.5) * flickerOn(t);
    float edge = 1.0 - smoothstep(0.7, 1.0, abs(dy) / (LINE_REACH * cellH * (SUBTLE ? 0.5 : 1.0)));  // nothing beyond LINE_REACH
    float tick = floor(t * FLICKER_RATE);
    vec3 light = vec3(0.0);

    float head = exp(-length(vec2(p.x - headX, dy)) / ((SUBTLE ? 0.3 : 0.5) * cellH));
    light += (sRGBToLinear(CORE_COLOR) * 0.5 + glowCol) * head * fade;

    if (behind > 0.0) {
        float hot = exp(-behind / (0.12 * res.x));  // brightest just behind the head
        float level = 0.35 + 0.65 * hot;
        for (int k = 0; k < 3; k++) {
            if (SUBTLE && k > 0) break;
            float fk = float(k);
            float off = wander(p.x / cellW * (0.5 + 0.35 * fk), tick * 0.37 + fk * 7.0 + lineY * 0.01) * (0.07 + 0.08 * fk) * cellH;
            float w = k == 0 ? 1.0 : 0.55;
            light += boltLightC(abs(dy - off), BOLT_WIDTH * cellH * w, glowPx * w, level * fade * (k == 0 ? 1.0 : 0.5), glowCol);
        }
        for (int k = 0; k < 4; k++) {
            if (SUBTLE) break;
            float fk = float(k);
            float h1 = hash11(tick * 3.3 + fk * 1.7 + lineY), h2 = hash11(tick * 5.1 + fk * 2.9 + lineY);
            float h3 = hash11(tick * 7.7 + fk * 4.3 + lineY);
            vec2 a = vec2(headX - side * (0.3 + 2.5 * h1) * cellH, lineY);
            if (abs(p.x - a.x) > 1.2 * cellH) continue;
            float ang = (h2 < 0.5 ? 1.0 : -1.0) * (1.57 + (h3 - 0.5) * 1.6);  // up or down, tilted
            vec2 b = a + vec2(cos(ang), sin(ang)) * cellH * (0.25 + 0.5 * h3);
            float sd = boltDist(p, a, b, 0.2 * distance(a, b), tick + fk * 13.0, 4.0);
            light += boltLightC(sd, BOLT_WIDTH * cellH * 0.5, glowPx * 0.4, fade * 0.9, glowCol);
        }
    }
    return light * edge;
}

// --- The cursor's own look (CURSOR_EFFECT) ---

// Pixel hash and smooth value noise for the cursor's look.
float clHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float clNoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(clHash(i), clHash(i + vec2(1.0, 0.0)), f.x),
               mix(clHash(i + vec2(0.0, 1.0)), clHash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Signed distance to a box of half-size b centered at the origin (negative inside).
float clBox(vec2 p, vec2 b) {
    vec2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// How much a pixel belongs to the cursor block itself: closer to the cursor
// color than to the background and to the letter color. Relative, because
// Ghostty's block isn't exactly the uniform's color; a letter under the cursor
// stays as it is.
float clOnBlock(vec3 col) {
    return smoothstep(0.0, 0.05, min(colorDist(col, iBackgroundColor), colorDist(col, iCursorText))
                                - colorDist(col, iCurrentCursorColor.rgb));
}

// Lightning's cursor: charged. A faint ice-blue glow, and several times a
// second a small arc of current jumps between two nearby points on the block's
// outline: a jagged white-blue thread with a soft glow, bulging outward.
vec3 cursorLook(vec2 p, vec3 col) {
    vec4 cur = upCursor(iCurrentCursor);
    vec2 lo = vec2(cur.x, cur.y - cur.w), hi = vec2(cur.x + cur.z, cur.y);
    vec2 c = 0.5 * (lo + hi), hs = 0.5 * (hi - lo);
    float cellH = max(cur.w, cellWOf(cur) * 2.0);
    vec2 q = abs(p - c) - hs;
    if (max(q.x, q.y) > 0.45 * cellH) return col;
    vec2 res = iResolution.xy;
    if (!cursorDrawn(lo, cur, res)) return col;
    float t = IDLE_EFFECTS ? iTime : 0.0, live = IDLE_EFFECTS ? 1.0 : 0.0;
    vec3 k = sRGBToLinear(iCurrentCursorColor.rgb);
    float d = clBox(p - c, hs);
    vec3 light = k * exp(-max(d, 0.0) / (0.1 * cellH)) * 0.3 * step(0.0, d);
    float beat = floor(t * 9.0);
    if (live > 0.0 && clHash(vec2(beat, 1.7)) < 0.7) {
        float a = 6.2832 * clHash(vec2(beat, 2.3));
        float b = a + (0.5 + 0.7 * clHash(vec2(beat, 3.9))) * (clHash(vec2(beat, 5.1)) < 0.5 ? -1.0 : 1.0);
        vec2 da = vec2(cos(a), sin(a)), db = vec2(cos(b), sin(b));
        vec2 A = c + hs * da / max(abs(da.x), abs(da.y)) + 1.5 * da;
        vec2 B = c + hs * db / max(abs(db.x), abs(db.y)) + 1.5 * db;
        vec2 dir = B - A;
        float len = max(length(dir), 1.0);
        dir /= len;
        vec2 nrm = vec2(-dir.y, dir.x);
        if (dot(nrm, 0.5 * (A + B) - c) < 0.0) nrm = -nrm;
        float s = clamp(dot(p - A, dir) / len, 0.0, 1.0);
        float off = sin(3.14159 * s) * (0.25 + (clNoise(vec2(s * 7.0, beat * 3.1)) - 0.5) * 0.7) * len;
        float dd = length(p - (A + dir * s * len + nrm * off));
        float fade = 0.6 + 0.4 * (1.0 - fract(t * 9.0));
        light += (mix(k, vec3(1.0), 0.75) * exp(-dd / 0.8) + k * exp(-dd / (0.06 * cellH)) * 0.6) * fade;
    }
    return col + light * CURSOR_STRENGTH;
}

// --- The prompt mark's look (PROMPT_EFFECT) ---

// Ink of the prompt mark's glyph at a point, only inside its cell (m is the
// cell's top-left corner, w and h its size).
float clMarkInk(vec2 at, vec2 m, float w, float h, vec2 res) {
    if (at.x < m.x || at.x > m.x + w || at.y > m.y || at.y < m.y - h) return 0.0;
    return smoothstep(0.04, 0.14, colorDist(screenAt(at / res).rgb, iBackgroundColor));
}

// Is the glyph in the cell at x shaped like a ❯ (or >)? Read in 17 rows of 12 points,
// in one pass: its ink reaches furthest right in the middle of its height (the tip),
// the top and bottom rows end at the same place well left of it, and at the tip the
// ink starts further right too. Letters, digits, Chinese characters, "-", "*", "$"
// don't pass (closing brackets do), so a one-letter word starting a continued or
// wrapped line ("a ", "I ") isn't taken for the prompt mark.
bool clChevron(float x, float w, vec4 cur, vec2 res) {
    float first = -1.0, last = -1.0, fL = 0.0, fR = 0.0, lL = 0.0, lR = 0.0;
    float most = -1.0, a = -1.0, b = -1.0, tipL = 0.0;
    for (int r = 0; r < 17; r++) {
        float y = cur.y - (0.1 + 0.05 * float(r)) * cur.w;
        float lo = 1.0, hi = 0.0;
        for (int i = 0; i < 12; i++) {
            float f = (float(i) + 0.5) / 12.0;
            if (colorDist(screenAt(vec2(x + f * w, y) / res).rgb, iBackgroundColor) > 0.08) { lo = min(lo, f); hi = max(hi, f); }
        }
        if (hi <= 0.0) continue;
        if (first < 0.0) { first = float(r); fL = lo; fR = hi; }
        last = float(r); lL = lo; lR = hi;
        if (hi > most + 0.01) { most = hi; a = float(r); b = a; tipL = lo; }
        else if (hi >= most - 0.01) { b = float(r); tipL = max(tipL, lo); }
    }
    if (first < 0.0 || last - first < 4.0) return false;
    float at = (0.5 * (a + b) - first) / (last - first);
    return at > 0.3 && at < 0.7 && most - max(fR, lR) > 0.15 && abs(fR - lR) < 0.15 && tipL - max(fL, lL) > 0.12;
}

// The prompt mark (the ❯ of Claude Code and of the shell): the first character
// on the cursor's row, when a blank cell follows it and both sit left of the
// cursor. Cells line up with the cursor's, so only the first few cells from the
// window's left edge are checked. Returns the mark cell's left edge, or -1.
float clMarkLeft(vec4 cur, vec2 res) {
    float w = cellWOf(cur), h = cur.w;
    if (w < 2.0) return -1.0;
    float x = mod(cur.x, w);
    for (int j = 0; j < 8; j++) {
        if (x + 2.0 * w > cur.x + 0.5) return -1.0;
        float hits = 0.0;
        for (int i = 0; i < 5; i++) {
            vec2 f = i == 0 ? vec2(0.3, 0.5) : i == 1 ? vec2(0.5, 0.36) : i == 2 ? vec2(0.5, 0.64) : i == 3 ? vec2(0.72, 0.5) : vec2(0.4, 0.42);
            hits += step(0.08, colorDist(screenAt(vec2(x + f.x * w, cur.y - f.y * h) / res).rgb, iBackgroundColor));
        }
        if (hits > 0.5) {
            float next = 0.0;
            for (int i = 0; i < 3; i++)
                next += step(0.08, colorDist(screenAt(vec2(x + (1.3 + 0.2 * float(i)) * w, cur.y - (0.35 + 0.15 * float(i)) * h) / res).rgb, iBackgroundColor));
            return next < 0.5 ? x : -1.0;
        }
        x += w;
    }
    return -1.0;
}

// The prompt mark of a prompt that wraps over several rows, the cursor on a later row:
// in Claude Code's input box, the first character under the box's top line, in the
// box's first column. Rows can be taller than the cursor, so the mark's cell is placed
// from its own glyph, which sits mid-cell. Callers check it is shaped like a mark.
// Returns the cell's top-left corner, or x < 0.
float clLineNear(float y0, float reach, vec2 res);  // further down, with the box lines' look
vec2 clMarkAbove(vec4 cur, vec2 res) {
    float w = cellWOf(cur), h = cur.w;
    if (w < 2.0) return vec2(-1.0);
    // The input box's top line: the first line across the window above the cursor's row.
    float stepY = max(1.0, floor(h / 16.0)), lineY = -1.0;
    for (int i = 0; i < 400; i++) {
        float y = cur.y + 1.0 + float(i) * stepY;
        if (y > cur.y + 10.0 * h || y > res.y) break;
        if (colorDist(screenAt(vec2(PANES ? boxColumnX() : 0.95 * res.x, y) / res).rgb, iBackgroundColor) < 0.03) continue;
        lineY = clLineNear(y, 1.0, res);
        if (lineY >= 0.0) break;
    }
    if (lineY < 0.0) return vec2(-1.0);
    // The box's first column: where that line starts (the window's padding can be wider
    // than a cell, so it is looked for along the cell grid).
    float x = -1.0, x0 = mod(cur.x, w);
    for (int k = 0; k < 10; k++) {
        float cx = x0 + float(k) * w;
        if (colorDist(screenAt(vec2(cx + 0.5 * w, lineY) / res).rgb, iBackgroundColor) > 0.03) { x = cx; break; }
    }
    if (x < 0.0) return vec2(-1.0);
    // The first glyph under the line in the first two cells: the mark (the rows after the
    // first are indented, so nothing else is there). Its cell from its middle.
    float top = -1.0, bot = -1.0, cell = x, gap = 0.0;
    for (int s = 0; s < 200; s++) {
        float y = lineY - 5.0 - float(s);
        if (y < cur.y - 0.5 * h || float(s) > 2.5 * h) break;
        bool any = false;
        for (int k = 0; k < 6; k++) {
            float cx = x + float(k / 3) * w;
            if ((top < 0.0 || cx == cell) && colorDist(screenAt(vec2(cx + (0.3 + 0.2 * float(k % 3)) * w, y) / res).rgb, iBackgroundColor) > 0.08) {
                if (top < 0.0) cell = cx;
                any = true;
            }
        }
        if (any) { if (top < 0.0) top = y; bot = y; gap = 0.0; }
        else if (top >= 0.0) { gap += 1.0; if (gap > 2.0) break; }
    }
    if (top < 0.0) return vec2(-1.0);
    return vec2(cell, 0.5 * (top + bot) + 0.5 * h);
}

// The prompt mark, charged: ice-blue with a white-hot core that flickers in
// steps, a blue glow, and a spark running down it now and then.
vec3 markLook(vec2 p, vec3 col, float ink, float halo, vec2 m, float w, float h, float t, float live) {
    vec3 k = sRGBToLinear(iCurrentCursorColor.rgb);
    vec2 res = iResolution.xy;
    float flick = 0.85 + 0.15 * step(0.5, clHash(vec2(floor(t * 15.0), 1.0))) * live;
    float run = fract(t / 2.2);
    float spark = live * step(run, 0.6) * exp(-pow((p.y - (m.y + 0.3 * h - run * 2.6 * h)) / (0.08 * h), 2.0));
    col = mix(col, mix(k, vec3(1.0), 0.35 + 0.5 * spark) * flick, ink);
    return col + k * halo * (1.0 - ink) * 0.6 * flick;
}

// Finds the prompt mark on the cursor's row and lets markLook() restyle its
// glyph (ink: how much the pixel is the glyph) and light the space around it
// (halo: the glyph blurred over a disc).
vec3 promptLook(vec2 p, vec3 col) {
    vec4 cur = upCursor(iCurrentCursor);
    float w = cellWOf(cur), h = cur.w;
    if (p.x > 9.0 * w + 0.4 * h) return col;
    vec2 res = iResolution.xy;
    vec2 m;
    if (abs(p.y - (cur.y - 0.5 * h)) <= 0.9 * h) {
        if (p.x > cur.x - 1.0) return col;
        float x0 = clMarkLeft(cur, res);
        if (x0 < 0.0 || p.x < x0 - 0.4 * h || p.x > x0 + max(w + 0.4 * h, 2.0 * w) || !clChevron(x0, w, cur, res)) return col;
        m = vec2(x0, cur.y);
    } else {
        // A prompt that wraps, the cursor on a later row: the mark on the prompt's first row.
        if (p.y < cur.y || p.y > cur.y + 10.5 * h || p.x > mod(cur.x, w) + 7.0 * w) return col;
        if (clMarkLeft(cur, res) >= 0.0) return col;  // the cursor's own row starts with the mark (or with text)
        // Only the box's first row (a line across the window at most a row and a half above) can hold the mark:
        // cheap, before the search.
        bool under = false;
        float stepY = max(1.0, floor(h / 16.0));
        for (int i = 0; i < 100; i++) {
            float y = p.y + float(i) * stepY;
            if (y > p.y + 2.2 * h || y > res.y) break;
            if (PANES ? onBoxLine(y, res)
                    : (colorDist(screenAt(vec2(0.95 * res.x, y) / res).rgb, iBackgroundColor) > 0.03
                    && colorDist(screenAt(vec2(0.05 * res.x, y) / res).rgb, iBackgroundColor) > 0.03
                    && colorDist(screenAt(vec2(0.5 * res.x, y) / res).rgb, iBackgroundColor) > 0.03)) { under = true; break; }
        }
        if (!under) return col;
        m = clMarkAbove(cur, res);
        if (m.x < 0.0 || abs(p.y - (m.y - 0.5 * h)) > 0.9 * h || p.x < m.x - 0.4 * h || p.x > m.x + max(w + 0.4 * h, 2.0 * w)
                || !clChevron(m.x, w, vec4(cur.x, m.y, cur.zw), res)) return col;
    }
    // The glow: the glyph blurred over a disc, 64 samples on a golden-angle spiral with a
    // soft falloff (two rings of 8 showed as separate ghost copies of the mark).
    float ink = clMarkInk(p, m, w, h, res), halo = 0.0, wsum = 0.0;
    for (int i = 0; i < 64; i++) {
        float r = sqrt((float(i) + 0.5) / 64.0), a = float(i) * 2.39996;
        float k = exp(-2.5 * r * r);
        halo += k * clMarkInk(p + 0.2 * h * r * vec2(cos(a), sin(a)), m, w, h, res);
        wsum += k;
    }
    halo /= wsum;
    // Still when the window isn't focused (its style stays, its motion stops).
    bool moving = IDLE_EFFECTS && iFocus != 0;
    float t = moving ? iTime : 0.0, live = moving ? 1.0 : 0.0;
    return markLook(p, col, ink, halo, m, w, h, t, live);
}

// --- The input box lines' look (LINE_EFFECT) ---

// The box line nearest to height y0, within `reach`: ink at three points across
// the window and background four pixels above and below it (like boxLineY()).
// Returns its height, or -1.
float clLineNear(float y0, float reach, vec2 res) {
    for (int i = 0; i < 81; i++) {
        float off = float((i + 1) / 2) * (i % 2 == 0 ? 1.0 : -1.0);
        if (abs(off) > reach) break;
        float y = floor(y0) + 0.5 + off;
        if (!boxLineAt(y, res)) continue;
        return y;
    }
    return -1.0;
}

// Whether a line across the window (like Claude Code's box lines) lies between heights y0 and
// y1 (y0 < y1): a line far above the cursor is the input box's own top line only when no
// other line is closer. Checked every pixel row (a line can be 1 px); most rows stop at
// the first sample.
bool clLineBetween(float y0, float y1, vec2 res) {
    for (int i = 0; i < 2400; i++) {
        float y = floor(y0) + 0.5 + float(i);
        if (y >= y1) break;
        if (PANES) {
            if (onBoxLine(y, res)) return true;
            continue;
        }
        if (colorDist(screenAt(vec2(0.95 * res.x, y) / res).rgb, iBackgroundColor) < 0.03
                || colorDist(screenAt(vec2(0.05 * res.x, y) / res).rgb, iBackgroundColor) < 0.03
                || colorDist(screenAt(vec2(0.45 * res.x, y) / res).rgb, iBackgroundColor) < 0.03
                || colorDist(screenAt(vec2(0.66 * res.x, y) / res).rgb, iBackgroundColor) < 0.03) continue;
        if (colorDist(screenAt(vec2(0.45 * res.x, y + 4.0) / res).rgb, iBackgroundColor) > 0.03
                || colorDist(screenAt(vec2(0.45 * res.x, y - 4.0) / res).rgb, iBackgroundColor) > 0.03) continue;
        return true;
    }
    return false;
}

// The box lines as live wires: a faint ice-blue current flowing along them,
// and every few seconds a spark running across with a short tail.
vec3 lineLook(vec2 p, vec3 col, float lineY, float h, vec2 res, float t, float live) {
    vec3 k = sRGBToLinear(iCurrentCursorColor.rgb);
    float dy = abs(p.y - lineY), core = exp(-dy / (0.03 * h)), soft = exp(-dy / (0.14 * h));
    float flow = 0.5 + 0.5 * clNoise(vec2(p.x / (1.2 * h) - t * 3.0, 3.0));
    float u = fract(t / 3.2), s = (u * 1.4 - 0.2) * res.x - p.x;
    float spark = live * step(u, 0.75) * (s >= 0.0 ? exp(-s / (2.0 * h)) : exp(s / (0.2 * h)));
    vec3 light = k * (core * 0.45 + soft * 0.18) * (0.45 + 0.55 * flow) + mix(k, vec3(1.0), 0.7) * spark * (core * 1.1 + soft * 0.35);
    return col + light * LINE_STRENGTH;
}

// LINE_COLOR: the box line's own pixels take the cursor's hue at about the line's own
// brightness. Done in the screen texture's own color space (found from the background),
// subtracting the line's grey and adding the new color, so anything drawn over the line
// (the Enter rain) and its antialiased edges stay as they are.
vec3 lineTint(vec2 p, vec3 col, float lineY, vec2 res) {
    vec3 bgTex = screenAt(vec2(p.x, lineY + 4.0) / res).rgb;          // background right above the line
    vec3 line = screenAt(vec2(p.x, lineY) / res).rgb;                  // the line's full color here
    vec3 s = screenAt(p / res).rgb;
    vec3 dl = line - bgTex;
    float ink = clamp(dot(s - bgTex, dl) / max(dot(dl, dl), 1e-6), 0.0, 1.0);
    if (ink <= 0.0) return col;
    bool linear = distance(bgTex, sRGBToLinear(iBackgroundColor)) < distance(bgTex, iBackgroundColor);
    vec3 k = linear ? sRGBToLinear(iCurrentCursorColor.rgb) : iCurrentCursorColor.rgb;
    vec3 lw = vec3(0.2126, 0.7152, 0.0722);
    vec3 matched = k * (1.25 * dot(line, lw) / max(dot(k, lw), 1e-3));
    return col + ink * (mix(line, min(matched, vec3(1.0)), LINE_COLOR) - line);
}

// Every pixel from a little below the cursor to a few rows above it (the box
// grows upward for a long prompt) looks for a box line within a fifth of the
// cursor's height of itself and lets lineLook() light it. Rows can be taller
// than the cursor (adjust-cell-height), so nothing here counts rows.
vec3 linesLook(vec2 p, vec3 col) {
    vec4 cur = upCursor(iCurrentCursor);
    float h = cur.w;
    if (p.y < cur.y - 2.6 * h || (p.y > cur.y - h && p.y < cur.y)) return col;
    // Far above the cursor (a tall prompt): only the line color, on the box's own top line.
    bool far = p.y > cur.y + 6.5 * h;
    if (far && !(LINE_TINT && LINE_COLOR > 0.0)) return col;
    if (far) {  // most of the screen: cheap tests first, the pixel's own color (no read) then its row
        vec3 bg = iBackgroundColor;  // as sRGB, and roughly as linear light (squared: no pow)
        if (distance(col, bg) < 0.03 || distance(col, bg * bg) < 0.03) return col;
        // The whole row must look like a line across the window: ink at five points along it and
        // background a few pixels above and below (text and a sent prompt's bar don't). These
        // reads are the same for every pixel of the row, so they cost next to nothing.
        vec3 bgT = screenAt(vec2(1.5) / iResolution.xy).rgb;  // the corner: background, as the texture holds it
        float v = p.y / iResolution.y, d4 = 4.0 / iResolution.y;
        if (PANES ? !onBoxLine(p.y, iResolution.xy)
                : distance(screenAt(vec2(0.95, v)).rgb, bgT) < 0.02 || distance(screenAt(vec2(0.05, v)).rgb, bgT) < 0.02
                || distance(screenAt(vec2(0.45, v)).rgb, bgT) < 0.02 || distance(screenAt(vec2(0.66, v)).rgb, bgT) < 0.02
                || distance(screenAt(vec2(0.88, v)).rgb, bgT) < 0.02
                || distance(screenAt(vec2(0.95, v + d4)).rgb, bgT) > 0.02 || distance(screenAt(vec2(0.95, v - d4)).rgb, bgT) > 0.02
                || distance(screenAt(vec2(0.45, v + d4)).rgb, bgT) > 0.02 || distance(screenAt(vec2(0.45, v - d4)).rgb, bgT) > 0.02) return col;
    }
    vec2 res = iResolution.xy;
    bool look = LINE_EFFECT && iFocus != 0;
    // With only the line color (no LINE_EFFECT light), background pixels have nothing to do.
    if ((!look || far) && colorDist(screenAt(p / res).rgb, iBackgroundColor) < 0.02) return col;
    // ...nor do pixels whose row isn't a line across the window (cheap, before the search).
    if ((!look || far) && (PANES ? colorDist(screenAt(vec2(boxColumnX(), p.y) / res).rgb, iBackgroundColor) < 0.02
            : (colorDist(screenAt(vec2(0.05 * res.x, p.y) / res).rgb, iBackgroundColor) < 0.02
            || colorDist(screenAt(vec2(0.95 * res.x, p.y) / res).rgb, iBackgroundColor) < 0.02))) return col;
    float lineY = clLineNear(p.y, far ? 2.0 : 0.2 * h, res);
    // With PANES the line can end before the window does: no look past its end.
    if (lineY < 0.0 || (PANES && colorDist(screenAt(vec2(p.x, lineY) / res).rgb, iBackgroundColor) < 0.03)) return col;
    // Only inside an input box: there is a box line just below the cursor too (a
    // shell, or a program with a long rule somewhere, stays plain).
    if (clLineNear(cur.y - 1.7 * h, 0.7 * h, res) < 0.0) return col;
    if (far) return clLineBetween(cur.y + 1.0, lineY - 3.0, res) ? col : lineTint(p, col, lineY, res);
    if (LINE_TINT && LINE_COLOR > 0.0) col = lineTint(p, col, lineY, res);
    if (!look) return col;
    float t = IDLE_EFFECTS ? iTime : 0.0, live = IDLE_EFFECTS ? 1.0 : 0.0;
    vec3 lit = lineLook(p, col, lineY, h, res, t, live);
    return SUBTLE ? mix(col, lit, 0.45) : lit;  // subtle: the moving look at under half (the line color stays)
}

// Everything that answers the cursor's moves and the signals (fragCoord is
// already y-up, fragColor already the screen).
void effects(inout vec4 fragColor, vec2 fragCoord) {
    vec2 res = iResolution.xy;
    if (iFocus == 0) return;

    // Cursor rectangles in pixels (y grows upward; .xy is the top-left corner).
    vec4 cur = upCursor(iCurrentCursor);
    vec2 lo = vec2(cur.x, cur.y - cur.w);
    vec2 hi = vec2(cur.x + cur.z, cur.y);
    float cellH = max(cur.w, cellWOf(cur) * 2.0);
    float cellW = max(cellWOf(cur), cellH * 0.4);
    vec2 center = (lo + hi) * 0.5;
    vec4 prv = upCursor(iPreviousCursor);
    vec2 from = vec2(prv.x + prv.z * 0.5, prv.y - prv.w * 0.5);

    float sinceMove = iTime - iTimeCursorChange;
    float moved = abs(cur.x - prv.x) / cellW + 2.0 * abs(cur.y - prv.y) / cellH;
    // Forward along the row by up to 40 cells is typed text, never a jump: a letter, a
    // Chinese character (two cells) or a whole phrase an input method commits at once
    // (the cursor stays put while you compose it, then jumps). It plays as typing.
    bool typedText = abs(cur.y - prv.y) < 0.5 * cellH && cur.x - prv.x > 0.5 * cellW && cur.x - prv.x < 40.5 * cellW;
    float signalMoved = moved;
    if (typedText) moved = min(moved, 1.0);  // a whole phrase plays like one keystroke
    bool typeOn = TYPE_EFFECT && (PHRASE_EFFECT || !(typedText && cur.x - prv.x > 1.5 * cellW));
    // Wait until the cursor has stayed put a moment (longer after a jump, so the
    // Enter signal can arrive first): spots a program's cursor passes through
    // while it redraws never show anything.
    sinceMove -= moved >= 3.0 ? JUMP_SETTLE : SETTLE;
    if (sinceMove < 0.0) return;
    // A jump while a signal is on means the same Enter only inside Claude Code's input box
    // (a box line just below the cursor: it cleared the box after the signal arrived), and
    // never forward along the row. A Tab completion, a prompt the shell redraws, a program
    // hopping the cursor elsewhere never start the effect again.
    bool back = signalMoved >= 3.0 && (oddByte(iCurrentCursorColor.b) || oddByte(iCurrentCursorColor.g))
        && !(abs(cur.y - prv.y) < 0.5 * cellH && cur.x > prv.x)
        && clLineNear(cur.y - 1.7 * cur.w, 0.7 * cur.w, res) >= 0.0;
    bool done = DONE_EFFECT && doneSignal(back);
    bool enter = (ENTER_EFFECT && enterSignal(back)) || done;
    bool send = enter && sinceMove < SEND_DURATION;
    if (enter && !send) return;
    if (iCursorVisible == 0 && !send) return;  // Enter still plays if the program hides the cursor
    // A jump counts only along the cursor's own row (delete-all, Home), and not
    // while the surge plays: a program hopping the cursor to another row while it
    // redraws must stay quiet. Only the color changed (the signal ending), or a
    // jump that doesn't count: not a move.
    bool jump = JUMP_EFFECTS && !send && moved >= BOLT_MIN_CELLS && abs(cur.y - prv.y) < 0.5 * cellH;
    if (!send && (moved < 0.5 || (moved >= BOLT_MIN_CELLS && !jump))) sinceMove = 1e4;
    bool bolt = jump && sinceMove < BOLT_DURATION;

    // Sparks after typing, or a rare crackle while idle.
    float sparkE = typeOn && moved < BOLT_MIN_CELLS && !send ? max(0.0, 1.0 - sinceMove / SPARK_DURATION) : 0.0;
    float win = floor(iTime / IDLE_PERIOD);
    float idleStart = win * IDLE_PERIOD + hash11(win + 0.37) * (IDLE_PERIOD - IDLE_DURATION);
    float sinceIdle = iTime - idleStart;
    bool idleNow = IDLE_EFFECTS && hash11(win * 1.7 + 9.1) < IDLE_CHANCE && sinceIdle >= 0.0
        && sinceIdle < IDLE_DURATION && sinceMove > 1.0;
    float sparkStrength = max(sparkE, idleNow ? 0.6 : 0.0);
    if (!bolt && !send && sparkStrength <= 0.0) return;

    vec2 p = fragCoord;
    float glowPx = GLOW_RADIUS * cellH * (SUBTLE ? 0.5 : 1.0);
    vec3 light = vec3(0.0);

    // The bolt along the row, from the old position to the new one, with side branches
    // (subtle: a low bolt that stays near the row, no branches).
    if (bolt) {
        vec2 to = center;
        float len = distance(from, to);
        float jag = min(BOLT_JAGGED * len, MAX_JAGGED * cellH) * (SUBTLE ? 0.25 : 1.0);
        float branchMax = SUBTLE ? 0.0 : min(0.25 * len, MAX_BRANCH * cellH);
        float reach = jag + branchMax + 8.0 * glowPx;
        if (segDist(p, from, to) < reach) {
            // Flicker: the first two steps always strike, later ones at random,
            // and each re-strike takes a slightly different path.
            float strength = pow(1.0 - sinceMove / BOLT_DURATION, 1.5) * flickerOn(sinceMove);
            float seed = mod(floor(sinceMove * 12.0) + floor(iTimeCursorChange * 7.0), 500.0);
            light += boltLight(boltDist(p, from, to, jag, seed, 16.0), BOLT_WIDTH * cellH, glowPx, strength);

            vec2 dir = (to - from) / max(len, 1e-3);
            for (float k = 0.0; k < 4.0; k += 1.0) {
                if (k >= BRANCHES || SUBTLE) break;
                vec2 start = boltPoint(from, to, 0.2 + 0.6 * hash11(seed + k * 3.7), jag, seed);
                float side = hash11(seed + k * 5.3) < 0.5 ? -1.0 : 1.0;
                float ang = side * (0.3 + 0.5 * hash11(seed + k * 6.1));
                vec2 end = start + rotate(dir, ang) * branchMax * (0.4 + 0.6 * hash11(seed + k * 7.9));
                float bjag = 0.25 * distance(start, end);
                if (segDist(p, start, end) < bjag + 8.0 * glowPx * 0.6) {
                    float bd = boltDist(p, start, end, bjag, seed + k + 1.0, 8.0);
                    light += boltLight(bd, BOLT_WIDTH * cellH * 0.6, glowPx * 0.6, strength * 0.6);
                }
            }

            // Flash where it lands, fading out within 0.1s.
            float flash = 1.0 - smoothstep(0.0, 2.0 * cellH, distance(p, to));
            light += sRGBToLinear(themeColor(BOLT_COLOR)) * flash * (SUBTLE ? 0.1 : 0.35) * max(0.0, 1.0 - sinceMove / 0.1);
        }
    }

    // Short sparks flying off the cursor's edges.
    vec2 hs = (hi - lo) * 0.5;
    bool drawn = sparkStrength > 0.0 && cursorDrawn(lo, cur, res);
    float tick = mod(floor(iTime * FLICKER_RATE), 1000.0);
    if (drawn && all(lessThan(abs(p - center), hs + vec2(2.3 * cellH)))) {
        float count = idleNow && sparkE <= 0.0 ? 2.0 : SPARKS;
        if (SUBTLE) count = min(count, 2.0);  // subtle: two short sparks
        for (float k = 0.0; k < SPARKS; k += 1.0) {
            if (k >= count) break;
            if (hash11(tick * 7.0 + k * 1.3) > 0.75 * sparkStrength + 0.1) continue;
            float ang = hash11(tick * 3.1 + k * 9.7) * 6.2832;
            vec2 dir = vec2(cos(ang), sin(ang));
            vec2 start = center + dir * min(hs.x / max(abs(dir.x), 1e-3), hs.y / max(abs(dir.y), 1e-3));
            vec2 end = start + dir * cellH * (0.35 + 0.5 * hash11(tick + k * 4.1)) * (SUBTLE ? 0.55 : 1.0);
            float sd = boltDist(p, start, end, 0.25 * distance(start, end), tick + k * 17.0, 4.0);
            light += boltLight(sd, BOLT_WIDTH * cellH * 0.5, glowPx * 0.4, sparkStrength);
        }
    }

    // Enter: the surge along the input box lines (or, in a shell with no box at
    // all, just under the line that was sent).
    if (send && p.y - center.y < (4.0 + LINE_REACH) * cellH && center.y - p.y < (1.6 + LINE_REACH) * cellH) {
        float lineY = boxLineY(p, center, cur, res, LINE_REACH * cellH);
        if (lineY < 0.0) {
            float under = sentRowY(cur, cellW, res) - 0.5 * cur.w + 2.0;
            if (abs(p.y - under) < LINE_REACH * cellH
                    && boxLineY(center + vec2(0.0, 0.5 * cellH), center, cur, res, 0.9 * cellH) < 0.0
                    && boxLineY(center - vec2(0.0, 0.5 * cellH), center, cur, res, 0.9 * cellH) < 0.0) lineY = under;
        }
        if (lineY >= 0.0) light += surge(p, lineY, center.x, sinceMove, res, cellH, cellW, done);
    }

    // Optional: while typing, one spark jumps from the cursor to the box line
    // above or below it and the line crackles where it lands.
    if (TYPING_LINE_SPARK && drawn && sparkE > 0.0
            && abs(p.x - center.x) < (LINE_CRACKLE + 1.5) * cellW && abs(p.y - center.y) < 2.0 * cellH) {
        float up = hash11(tick * 2.3 + 0.7) < 0.5 ? 1.0 : -1.0;  // which line the spark jumps to
        float lineY = boxLineY(p, center, cur, res, 1.6 * cellH);
        if (lineY >= 0.0 && sign(lineY - center.y) == up) {
            float foot = center.x + (hash11(tick * 5.1 + 2.2) - 0.5) * 1.5 * cellW;
            vec2 start = vec2(center.x + (hash11(tick * 1.9 + 3.3) - 0.5) * hs.x, up > 0.0 ? hi.y : lo.y);
            float sd = boltDist(p, start, vec2(foot, lineY), 0.3 * cellH, tick * 1.3 + 5.0, 6.0);
            light += boltLight(sd, BOLT_WIDTH * cellH * 0.5, glowPx * 0.4, sparkE);
            float along = exp(-abs(p.x - foot) / (LINE_CRACKLE * cellW));
            light += boltLight(abs(p.y - lineY), BOLT_WIDTH * cellH * 0.5, glowPx * 0.5, sparkE * along * 0.8);
        }
    }

    fragColor = vec4(min(fragColor.rgb + light, vec3(1.0)), fragColor.a);
}

// A pane's edge drawn by a terminal multiplexer: herdr's sidebar separator, a herdr or tmux pane
// border. Its cell (left edge `left`, `w` wide) is ink without a break from the bottom of the
// cursor's row, across the gap above that row that letters never reach, into the lower half of the
// row above (where a pane's top corner already runs down). A box-drawing line or a colored cell is.
// Ghostty draws a vertical line one to three pixels wide in the cell's middle, always over pixel
// (w - 1) / 2, so one column of samples does. The gap first: a cell of text is done after one sample.
bool paneWall(float left, float w, vec4 cur, vec2 res) {
    // The background as the texture holds it (the window's corner): a dark border can be within
    // colorDist()'s reach of the background's color in the other color space.
    vec3 bgT = screenAt(vec2(1.5) / res).rgb;
    float x = floor(left) + floor(0.5 * (w - 1.0)) + 0.5, stepY = max(1.0, floor(cur.w / 24.0));
    if (distance(screenAt(vec2(x, cur.y) / res).rgb, bgT) < 0.03) return false;
    for (float y = cur.y + 0.4 * cur.w; y >= cur.y - cur.w; y -= stepY) {
        if (y < 0.0 || y > res.y) continue;
        if (distance(screenAt(vec2(x, y) / res).rgb, bgT) < 0.03) return false;
    }
    return true;
}

// --- The typed text's color (TEXT_COLOR) ---

vec3 linearToSRGB(vec3 c) {
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

// Relative luminance of a linear color.
float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// A line across the whole window (with PANES: through the cursor's column, see
// onBoxLine()) at height y (Claude Code's input box border): one
// color, not the background, at twelve points along it, and background four pixels
// above and below. A long row of text can have ink at a few points along one pixel
// row, but never the same color all the way across.
bool fullLine(float y, vec2 res) {
    if (PANES) return onBoxLine(y, res);
    vec3 first = screenAt(vec2(0.05 * res.x, y) / res).rgb;
    if (colorDist(first, iBackgroundColor) < 0.03) return false;
    for (int i = 1; i < 12; i++)
        if (distance(screenAt(vec2((0.05 + 0.08 * float(i)) * res.x, y) / res).rgb, first) > 0.03) return false;
    return colorDist(screenAt(vec2(0.45 * res.x, y + 4.0) / res).rgb, iBackgroundColor) < 0.03
        && colorDist(screenAt(vec2(0.45 * res.x, y - 4.0) / res).rgb, iBackgroundColor) < 0.03;
}

// Such a line between heights y0 and y1, searched from y0 upward (or from y1 downward
// with `down`), so the edge nearer the cursor is found: one pixel read per step, near
// the window's right edge where text rarely reaches, in steps finer than the line is
// thick; the whole line is checked only where that pixel isn't background. Its
// height, or -1.
float lineIn(float y0, float y1, bool down, float h, vec2 res) {
    float st = max(1.0, floor(h / 19.0)), x = PANES ? boxColumnX() : 0.97 * res.x;
    for (int i = 0; i < 80; i++) {
        float at = down ? y1 - float(i) * st : y0 + float(i) * st;
        if (at < y0 || at > y1) break;  // compared before rounding: a rounded first step can fall just outside
        float y = floor(at) + 0.5;
        if (colorDist(screenAt(vec2(x, y) / res).rgb, iBackgroundColor) < 0.03) continue;
        if (fullLine(y, res)) return y;
    }
    return -1.0;
}

// Claude Code's input box around the cursor: its top and bottom lines (-1 when there
// is no box, as in a shell). The line on one side is looked for one row away, then
// two, then three (the cursor inside a prompt of many rows); from it the row height
// is known, so the other line is looked for a whole number of rows away on the other
// side. Rows can be taller than the cursor (adjust-cell-height), so the windows
// allow rows of 0.98 to 1.47 cursor heights, and never two row counts at once.
vec2 inputBox(vec4 cur, vec2 res) {
    float h = cur.w, c = cur.y - 0.5 * h;
    float top = lineIn(c + 0.85 * h, c + 1.75 * h, false, h, res), bot = -1.0, rows = 1.0;
    if (top < 0.0) bot = lineIn(c - 1.75 * h, c - 0.85 * h, true, h, res);
    if (top < 0.0 && bot < 0.0) {
        // A shell prompt (a mark starting the cursor's row, no line beside it): no box,
        // and no need for the longer searches.
        if (clMarkLeft(cur, res) >= 0.0) return vec2(-1.0);
        for (int k = 2; k <= 3; k++) {
            rows = float(k);
            vec2 w = k == 2 ? vec2(1.85, 2.95) * h : vec2(2.95, 3.9) * h;
            top = lineIn(c + w.x, c + w.y, false, h, res);
            if (top < 0.0) bot = lineIn(c - w.y, c - w.x, true, h, res);
            if (top >= 0.0 || bot >= 0.0) break;
        }
        if (top < 0.0 && bot < 0.0) return vec2(-1.0);
    }
    float pitch = (top >= 0.0 ? top - c : c - bot) / rows;
    for (int k = 1; k <= 8; k++) {
        float at = float(k) * pitch;
        if (top < 0.0) top = lineIn(c + at - 0.3 * h, c + at + 0.3 * h, false, h, res);
        else if (bot < 0.0) bot = lineIn(c - at - 0.3 * h, c - at + 0.3 * h, true, h, res);
        else break;
    }
    return top >= 0.0 && bot >= 0.0 ? vec2(top, bot) : vec2(-1.0);
}

// How far color c sits along the way from background `back` to text color `ink`, 0..1.
float inkAmount(vec3 c, vec3 back, vec3 ink) {
    vec3 d = ink - back;
    return clamp(dot(c - back, d) / max(dot(d, d), 1e-6), 0.0, 1.0);
}

// Ink in the cell (w wide) whose left edge is at x, on the row whose top is y (h the cursor's height).
bool cellHasInk(float x, float w, float y, float h, vec2 res) {
    return colorDist(screenAt(vec2(x + 0.3 * w, y - 0.5 * h) / res).rgb, iBackgroundColor) > 0.08
        || colorDist(screenAt(vec2(x + 0.5 * w, y - 0.36 * h) / res).rgb, iBackgroundColor) > 0.08
        || colorDist(screenAt(vec2(x + 0.72 * w, y - 0.5 * h) / res).rgb, iBackgroundColor) > 0.08
        || colorDist(screenAt(vec2(x + 0.5 * w, y - 0.64 * h) / res).rgb, iBackgroundColor) > 0.08;
}

// The cursor on a later row of a prompt: Claude Code indents every row after the first by two cells.
// The first column's x (two cells left of the row's first glyph, or of the cursor on an empty row), or
// -1 when the row starts with a mark and a space (a one-row prompt, a shell's prompt). The window's
// padding can be wider than a cell, so the glyph is looked for from the grid's first cell.
float tallRow(vec4 cur, vec2 res) {
    float w = cellWOf(cur), h = cur.w, first = -1.0;
    if (w < 2.0) return -1.0;
    // four cells a read round (the padding is rarely wider than two); the cell after the first glyph
    // comes with it when it is one of the four
    float next = -1.0;
    for (float x = mod(cur.x, w); x < cur.x + 0.5 * w && first < 0.0; x += 4.0 * w) {
        bvec4 n = bvec4(cellHasInk(x, w, cur.y, h, res), cellHasInk(x + w, w, cur.y, h, res),
                        cellHasInk(x + 2.0 * w, w, cur.y, h, res), cellHasInk(x + 3.0 * w, w, cur.y, h, res));
        for (int k = 0; k < 4; k++) {
            float xk = x + float(k) * w;
            if (first < 0.0 && (xk > cur.x - 0.5 || n[k])) { first = xk; next = k < 3 ? (n[k + 1] ? 1.0 : 0.0) : -1.0; }
        }
    }
    if (first < 0.0) return -1.0;
    if (first < cur.x - 0.5 && (next < 0.0 ? !cellHasInk(first + w, w, cur.y, h, res) : next < 0.5)) return -1.0;
    return first - 2.0 * w >= mod(cur.x, w) - 0.5 ? first - 2.0 * w : -1.0;
}

bool inkAt(vec2 q, vec2 res) {  // a glyph's ink
    return colorDist(screenAt(q / res).rgb, iBackgroundColor) > 0.08;
}
bool offBg(vec2 q, vec2 res) {  // anything but background (a box line is a dim grey)
    return colorDist(screenAt(q / res).rgb, iBackgroundColor) >= 0.03;
}

// Claude Code's box line below the cursor (one to three rows down) that starts at x0: the height of
// its middle, or -1. Four steps a read round, two pixels a step on a sharp screen (the line is thicker than that).
float boxBelow(vec4 cur, float x0, vec2 res) {
    float w = cellWOf(cur), h = cur.w, c = cur.y - 0.5 * h;
    float st2 = h >= 24.0 ? 2.0 : 1.0, x9 = PANES ? boxColumnX() : 0.97 * res.x, bot = -1.0;
    // a row down; two or three only when the row below the cursor holds more of the prompt (ink in
    // its first two text cells, looked for down the whole height that row can have)
    bool more = false;
    for (int i = 0; i < 6; i++) {
        float y = cur.y - (1.15 + 0.25 * float(i)) * h;
        more = more || inkAt(vec2(x0 + 2.3 * w, y), res) || inkAt(vec2(x0 + 2.7 * w, y), res) || inkAt(vec2(x0 + 3.5 * w, y), res);
    }
    float reach = more ? 3.9 : 1.75;
    for (float y = floor(c - 0.85 * h) + 0.5; y > c - reach * h && y > 0.0; y -= 4.0 * st2) {
        bvec4 n = bvec4(offBg(vec2(x9, y), res), offBg(vec2(x9, y - st2), res), offBg(vec2(x9, y - 2.0 * st2), res), offBg(vec2(x9, y - 3.0 * st2), res));
        if (!any(n)) continue;
        for (int k = 0; k < 4; k++) {
            float yk = y - float(k) * st2;
            if (n[k] && fullLine(yk, res)) { bot = yk; break; }
        }
        if (bot >= 0.0) break;
    }
    if (bot < 0.0 || !offBg(vec2(x0 + 0.5 * w, bot), res) || (x0 > 0.5 * w && offBg(vec2(x0 - 0.5 * w, bot), res))) return -1.0;
    float t = 1.0;  // its thickness: the height returned is its middle
    for (int i = 0; i < 6; i++) if (t == float(i) + 1.0 && offBg(vec2(x9, bot - t), res)) t += 1.0;
    return bot - 0.5 * (t - 1.0);
}

// From tallRow()'s column x0, for the pixel at height `above`: the input box however tall (a long
// prompt), going up that column (Claude Code leaves it blank below the prompt mark) to the mark on the
// box's first row, or to the box's top line, or past the pixel. Four steps a read round. Returns the
// box's top, the line below the cursor, x0 and a height on the mark (-1 when none was reached); .x -2
// when the box's first row is below the pixel (outside), all -1 when it isn't Claude Code's box.
vec4 tallBox(vec4 cur, float x0, float above, vec2 res) {
    float w = cellWOf(cur), h = cur.w;
    float hit = -1.0, bot = -2.0, st = max(1.0, floor(h / 3.0));
    for (float y = cur.y + 0.1 * h; y <= min(res.y, above + 1.5 * h); y += 8.0 * st) {
        // past the first few rows: first make sure this is Claude Code's box (a shell stops here)
        if (bot == -2.0 && y > cur.y + 2.5 * h) { bot = boxBelow(cur, x0, res); if (bot < 0.0) return vec4(-1.0); }
        for (int k = 0; k < 8; k++) {  // eight steps a read round
            float yk = y + float(k) * st;
            if (hit < 0.0 && (inkAt(vec2(x0 + 0.3 * w, yk), res) || inkAt(vec2(x0 + 0.5 * w, yk), res) || inkAt(vec2(x0 + 0.72 * w, yk), res))) hit = yk;
        }
        if (hit >= 0.0) break;
    }
    if (bot == -2.0) bot = boxBelow(cur, x0, res);
    if (bot < 0.0) return vec4(-1.0);
    if (hit >= 0.0 && above > hit + 1.2 * h) return vec4(-2.0);  // the pixel is above the box's first row
    if (hit < 0.0) return vec4(res.y + h, bot, x0, -1.0);  // no mark up to the pixel: its row is in the box
    // The top line itself (a thin line across the window) or the mark: its top, a pixel at a time.
    if (fullLine(floor(hit) + 0.5, res)) return vec4(hit, bot, x0, -1.0);
    float top = hit;
    for (float y = floor(hit) + 1.5; y <= hit + h; y += 1.0) {
        if (!inkAt(vec2(x0 + 0.3 * w, y), res) && !inkAt(vec2(x0 + 0.5 * w, y), res) && !inkAt(vec2(x0 + 0.72 * w, y), res)) break;
        top = y;
    }
    return vec4(top + 0.3 * h + 2.0, bot, x0, hit);
}

// The text you type and the prompts you sent, in the cursor's color: inside Claude
// Code's input box (between its two lines across the window), on the grey bars
// Claude Code draws your sent prompts on, and in a shell on the cursor's row right of
// the prompt mark (❯). Only text drawn at full strength in the terminal's text color
// or in white (Claude Code's color for your text) changes; dim text (a placeholder,
// zsh's grey suggestion) and colored text (syntax highlighting, links) stay. Its
// contrast against the background behind it matches the terminal's own text. TEXT_TYPING and
// TEXT_SENT pick which of the two (what you type, what you sent) changes.
vec3 textTint(vec2 p, vec3 col, vec2 res) {
    vec3 s = screenAt(p / res).rgb;
    if (colorDist(s, iBackgroundColor) < 0.03) return col;
    // Worked out in sRGB, whatever the screen texture holds (told by the window's
    // corner, which is background).
    vec3 corner = screenAt(vec2(1.5) / res).rgb;
    bool linear = distance(corner, sRGBToLinear(iBackgroundColor)) < distance(corner, iBackgroundColor);
    vec3 bg = iBackgroundColor;
    // A sent prompt's bar: the darkest of six points along this row (spaces and the
    // row's end show the bar; letters don't) is exactly the background Claude Code's
    // dark theme gives your own messages: rgb(55, 55, 55) for a prompt, rgb(65, 60, 65)
    // for a `!` shell command. Other greys stay out: a message you click open gets
    // rgb(70, 70, 70) behind Claude's output too.
    vec3 back = vec3(1.0);
    bool bar = false;
    if (TEXT_SENT && PANES) {
        // With PANES the bar spans only the cursor's pane: the first pixel column of the six cells
        // around this one (letters rarely reach it); four must show the bar's grey (two cells can
        // be past the pane's edge; a short grey highlight isn't a sent prompt).
        vec4 cg = upCursor(iCurrentCursor);
        float cw = max(cellWOf(cg), 1.0), e = cg.x + floor((p.x - cg.x) / cw) * cw + 0.5, seen = 0.0;
        for (int i = 0; i < 6; i++) {
            vec3 b = screenAt(vec2(e + float(i - 2) * cw, p.y) / res).rgb;
            b = linear ? linearToSRGB(b) : b;
            if (all(lessThan(abs(b - vec3(55.0) / 255.0), vec3(4.0 / 255.0)))
                    || all(lessThan(abs(b - vec3(65.0, 60.0, 65.0) / 255.0), vec3(4.0 / 255.0)))) { back = b; seen += 1.0; }
        }
        if (seen < 4.0) back = vec3(1.0);
    } else if (TEXT_SENT) {
        for (int i = 0; i < 6; i++) {
            vec3 b = screenAt(vec2((0.12 + 0.165 * float(i)) * res.x, p.y) / res).rgb;
            b = linear ? linearToSRGB(b) : b;
            if (dot(b, vec3(1.0)) < dot(back, vec3(1.0))) back = b;
        }
    }
    if (TEXT_SENT) {
        bar = all(lessThan(abs(back - vec3(55.0) / 255.0), vec3(4.0 / 255.0)))
           || (all(lessThan(abs(back - vec3(65.0, 60.0, 65.0) / 255.0), vec3(4.0 / 255.0)))
               && min(back.r, back.b) - back.g > 2.5 / 255.0);  // that one's faint pink, not a plain grey
    }
    if (!bar) {
        if (!TEXT_TYPING) return col;  // only the sent prompts
        back = bg;
    }
    vec4 cur = upCursor(iCurrentCursor);
    float h = cur.w, c = cur.y - 0.5 * h;
    if (!bar && (iCursorVisible == 0 || abs(p.y - c) > 10.0 * h)) return col;
    // the cursor's own block (a steel cursor color can pass for white text): nearer its color than
    // the background's and the text's (a see-through cursor too; a letter in a hollow one stays text)
    if (!bar && p.x >= cur.x && p.x <= cur.x + cur.z && p.y <= cur.y && p.y >= cur.y - h
            && colorDist(s, iCurrentCursorColor.rgb) <= min(colorDist(s, iBackgroundColor), colorDist(s, iForegroundColor))) return col;
    // Which text color it is (the terminal's or white), how much of it this pixel has,
    // and whether the glyph reaches it at full strength within a stroke's width. Told from
    // the screen as it is where the effects only added light (a cursor's glow, sparks over a
    // letter), so the letter keeps its color under them and the change adds to their light;
    // where an effect moved or darkened the pixel, from the pixel as drawn.
    vec3 cs = linear ? linearToSRGB(col) : col, ss = linear ? linearToSRGB(s) : s;
    vec3 ts = all(greaterThanEqual(col, s - 0.004)) ? ss : cs;
    vec3 fg = iForegroundColor;
    float df = distance(ts, back + inkAmount(ts, back, fg) * (fg - back));
    float dw = distance(ts, back + inkAmount(ts, back, vec3(1.0)) * (vec3(1.0) - back));
    vec3 ink = df <= dw ? fg : vec3(1.0);
    float a = inkAmount(ts, back, ink);
    float gate = 1.0 - smoothstep(0.04, 0.09, min(df, dw));
    if (a <= 0.0 || gate <= 0.0) return col;
    float r = max(1.0, 0.04 * h), core = inkAmount(ss, back, ink);
    for (int i = 0; i < 4; i++) {
        vec3 n = screenAt((p + r * vec2(i % 2 == 0 ? -1.0 : 1.0, i < 2 ? -1.0 : 1.0)) / res).rgb;
        core = max(core, inkAmount(linear ? linearToSRGB(n) : n, back, ink));
    }
    gate *= smoothstep(0.55, 0.8, core);
    if (gate <= 0.0) return col;
    if (!bar) {
        // The cursor on a later row of a prompt: the box from its mark up to this pixel, however tall
        // the prompt (rows within ten cursor heights; see above). Otherwise (a one-row prompt, a
        // shell) the box near the cursor as before.
        float tallX = tallRow(cur, res);
        vec4 tall = tallX >= 0.0 ? tallBox(cur, tallX, p.y, res) : vec4(-1.0);
        if (tall.x == -2.0) return col;
        if (tall.x >= 0.0) {
            // Whole rows only, as many as lie within ten cursor heights (the limit above): this pixel's
            // row counted from the cursor's (rows 0.98 to 1.47 cursor heights tall, so the line's
            // distance tells how many rows down it is).
            float d = c - tall.y, pitch = d / (d < 1.72 * h ? 1.0 : d < 2.95 * h ? 2.0 : 3.0);  // the line is one to three rows down
            float k = floor((p.y - c) / pitch + 0.5);
            if (k > floor(10.0 * h / pitch - 0.5)) return col;
        }
        vec2 box = tall.x >= 0.0 ? tall.xy : inputBox(cur, res);
        if (box.x >= 0.0) {
            if (p.y > box.x - 2.0 || p.y < box.y + 2.0) return col;
            float w = cellWOf(cur);
            if (tall.x >= 0.0) {
                // the mark's cell, on the box's first row (the first column is blank below it)
                if (tall.w >= 0.0 && p.x >= tall.z - 1.0 && p.x <= tall.z + w + 1.0 && p.y >= tall.w - 0.7 * h) return col;
            } else if (p.x < mod(cur.x, w) + 7.0 * w) {
                float x0 = clMarkLeft(cur, res);
                vec2 m = x0 >= 0.0 ? vec2(x0, cur.y) : clMarkAbove(cur, res);
                if (m.x >= 0.0 && p.x >= m.x - 1.0 && p.x <= m.x + w + 1.0 && p.y <= m.y + 1.0 && p.y >= m.y - h - 1.0
                        && clChevron(m.x, w, vec4(cur.x, m.y, cur.zw), res)) return col;
            }
        } else {
            // A shell: the command you're typing, after the prompt mark.
            if (p.y < cur.y - 1.1 * h || p.y > cur.y + 0.1 * h) return col;
            float m = clMarkLeft(cur, res), w = cellWOf(cur);
            if (m < 0.0 || p.x < m + 1.5 * w || !clChevron(m, w, cur, res)) return col;
        }
    }
    // The cursor's color at the brightness that gives the terminal text's contrast on
    // this background (the bar is lighter, so the green is too there).
    vec3 k = sRGBToLinear(iCurrentCursorColor.rgb);
    float lb = luma(sRGBToLinear(bg)), want = (luma(sRGBToLinear(fg)) + 0.05) / (lb + 0.05) * (luma(sRGBToLinear(back)) + 0.05) - 0.05;
    vec3 green = linearToSRGB(min(k * want / max(luma(k), 1e-3), vec3(1.0)));
    cs += a * gate * TEXT_TINT * (green - ink);
    return linear ? sRGBToLinear(max(cs, 0.0)) : cs;
}

// With PANES the effects stay in the cursor's pane. With the input box in sight, a pixel counts
// when the box line under the cursor runs unbroken from the cursor's column to it. With none (a
// shell), when no pane edge lies between them. Only pixels an effect changed get here.
bool inCursorPane(float x, vec2 res) {
    vec4 cur = upCursor(iCurrentCursor);
    float y = clLineNear(cur.y - 1.7 * cur.w, 0.7 * cur.w, res);
    float from = boxColumnX(), step1 = cellWOf(cur), dir = x < from ? -1.0 : 1.0;
    if (y < 0.0) {
        for (int i = 1; i < 400; i++) {
            float at = from + dir * float(i) * step1;
            if (dir * (at - x) > 0.5 * step1) return true;  // past the pixel's own cell
            if (paneWall(at - 0.5 * step1, step1, cur, res)) return false;
        }
        return true;
    }
    vec3 ink = screenAt(vec2(from, y) / res).rgb;
    for (int i = 1; i < 400; i++) {
        float at = from + dir * float(i) * step1;
        if (dir * (at - x) >= 0.0) at = x;
        if (distance(screenAt(vec2(at, y) / res).rgb, ink) > 0.03) return false;
        if (at == x) return true;
    }
    return true;
}

void paneEffects(inout vec4 fragColor, vec2 fragCoord) {
    vec3 before = fragColor.rgb;
    effects(fragColor, fragCoord);
    if (PANES && fragColor.rgb != before && !inCursorPane(fragCoord.x, iResolution.xy)) fragColor.rgb = before;
}

void effectImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    if (Y_DOWN) fragCoord.y = res.y - fragCoord.y;
    fragColor = screenAt(fragCoord / res);
    vec3 under = fragColor.rgb;  // the screen before the moments (the subtle version mixes back to it)
    paneEffects(fragColor, fragCoord);
    if (SUBTLE) fragColor.rgb = mix(under, fragColor.rgb, 0.55);
    // Your text's color stays when the window loses focus, like the line color.
    if (TEXT_COLOR && !lightTheme() && iCurrentCursorStyle == CURSORSTYLE_BLOCK) {
        vec3 tinted = clamp(textTint(fragCoord, fragColor.rgb, res), 0.0, 1.0);
        if (!PANES || (tinted != fragColor.rgb && inCursorPane(fragCoord.x, res))) fragColor.rgb = tinted;  // with PANES, not another pane's text
    }
    // The line color stays when the window loses focus; the moving looks don't.
    if (((LINE_EFFECT && iFocus != 0) || (LINE_TINT && LINE_COLOR > 0.0)) && iCursorVisible != 0 && iCurrentCursorStyle == CURSORSTYLE_BLOCK) fragColor.rgb = min(linesLook(fragCoord, fragColor.rgb), vec3(1.0));
    if (iCursorVisible == 0) return;
    if (iFocus != 0 && CURSOR_EFFECT && iCurrentCursorStyle == CURSORSTYLE_BLOCK) { vec3 lit = min(cursorLook(fragCoord, fragColor.rgb), vec3(1.0)); fragColor.rgb = SUBTLE ? mix(fragColor.rgb, lit, 0.45) : lit; }
    if (PROMPT_EFFECT && iCurrentCursorStyle == CURSORSTYLE_BLOCK) { vec3 lit = min(promptLook(fragCoord, fragColor.rgb), vec3(1.0)); fragColor.rgb = SUBTLE ? mix(fragColor.rgb, lit, 0.6) : lit; }
}

// Everything above works on the screen without a translucent window's transparency (see
// screenAt()); the window wants it back.
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    if (lightTheme()) {
        vec4 t = texture(iChannel0, vec2(0.001));
        vec3 corner = t.rgb / max(t.a, 0.01), bg = 1.0 - iBackgroundColor;
        screenLinear = distance(corner, sRGBToLinear(bg)) < distance(corner, bg);
    }
    effectImage(fragColor, fragCoord);
    if (lightTheme()) fragColor.rgb = themeFlip(fragColor.rgb);
    if (SEE_THROUGH && fragColor.a < 1.0) fragColor.rgb *= fragColor.a;
}
