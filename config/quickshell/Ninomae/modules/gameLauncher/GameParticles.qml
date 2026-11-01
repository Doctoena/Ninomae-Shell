import QtQuick
import Quickshell
import qs.services

// GameParticles v6 — SoA particle engine behind the game details banner
// Each preset is one clear idea (rain, fog, warp, tracers…) rather than a stack of every effect.
// Colours come from the hero art, pulled toward a per-preset tint so snow stays white, embers stay warm, etc.
Item {
    id: root

    // ─── Public API ───────────────────────────────────────
    property string gameId: ""
    property string gameName: ""
    property string imageSource: ""
    property bool active: true
    property real particleOpacity: 0.85
    // How many and how strong, as picked on the Customize panel's Effect tab (1 = the preset's own)
    property real densityScale: 1
    property real opacityScale: 1
    property string forcePreset: ""

    // ─── Particle SoA buffers (fixed capacity) ───────────
    readonly property int _cap: 96
    property var _px: null   // x
    property var _py: null   // y
    property var _vx: null   // x velocity
    property var _vy: null   // y velocity
    property var _sz: null   // size
    property var _al: null   // alpha
    property var _mx: null   // max alpha
    property var _fr: null   // fade-out rate
    property var _dp: null   // depth (0.3-1)
    property var _ag: null   // age
    property var _ph: null   // phase offset
    property var _sp: null   // spin speed
    property var _rt: null   // rotation
    property var _gy: null   // ground line (rain splashes)
    property var _gw: null   // glow strength
    property var _ci: null   // palette index
    property var _cr: null; property var _cg: null; property var _cb: null
    property var _sh: null   // shape
    property var _tm: null   // twinkle/blink multiplier
    property int _count: 0

    // ─── Effects ─────────────────────────────────────────
    property var _fadeOut: []     // crossfade remnants of the previous preset
    property var _bolts: []       // lightning (storm) and short arcs (arcs)
    property var _sparkBursts: [] // pops (embers, magic)
    property var _ripples: []     // flattened splash ellipses
    property var _drips: []       // falling water drops (cavern)
    property var _tracers: []     // fast light streaks crossing the frame (tracers, neon)
    property var _packets: []     // data pulses travelling along links (circuit)
    property var _links: []       // links drawn last frame, as flat [x1,y1,x2,y2,...]
    property var _shooting: null
    property real _flashAlpha: 0
    property real _boltTimer: 0
    property real _arcTimer: 0
    property real _popTimer: 0
    property real _dripTimer: 0
    property real _tracerTimer: 0
    property real _packetTimer: 0
    property real _shootT: 0

    // ─── Engine state ────────────────────────────────────
    property var _rawColors: []   // straight from the art (or name hash)
    property var _colors: []      // tinted for the current preset
    property bool _ready: false
    property string _preset: "ambient"
    property var _cfg: ({})
    property real _time: 0
    property real _lastMs: 0
    property int _target: 0
    // Sizes are tuned for a ~300px tall banner; scale up on bigger ones so nothing turns to specks
    readonly property real _sizeK: Math.max(1, Math.min(2, (_mainCanvas.height || height) / 300))
    property real _wph: 0; property real _wx: 0; property real _wy: 0       // wind
    property real _gTimer: 0; property real _gx: 0; property real _gyF: 0; property real _gStr: 0 // gusts
    property var _connGrid: null

    opacity: (_ready && active) ? Math.min(1, particleOpacity * opacityScale) : 0
    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

    // ═════════════════════════════════════════════════════════
    //  SHAPES
    // ═════════════════════════════════════════════════════════
    readonly property int _sCircle: 0
    readonly property int _sDiamond: 1
    readonly property int _sPetal: 2
    readonly property int _sHex: 3
    readonly property int _sStar: 4
    readonly property int _sSnowflake: 5
    readonly property int _sSpark: 6
    readonly property int _sCross: 7
    readonly property int _sRing: 8      // bubble
    readonly property int _sSoft: 9      // glow sprite only (fog, dust clouds)
    readonly property int _sSquare: 10   // axis-aligned pixel
    readonly property int _sLeaf: 11
    readonly property int _sBokeh: 12    // out-of-focus disc

    // ═════════════════════════════════════════════════════════
    //  PRESETS
    //  shapeSize / shapeAlpha / shapeGlow override the defaults per shape;
    //  tint + tintAmt pull the art colours toward a theme colour
    // ═════════════════════════════════════════════════════════
    readonly property var _presets: ({

        // ── Atmosphere ───────────────────────────────────

        // Slow glowing motes with a few large out-of-focus discs
        "ambient": {
            n: 36, szMin: 1.5, szMax: 4, spdMin: 3, spdMax: 12,
            dir: "float", fadeIn: 0.6, fadeOut: 0.04,
            glow: 2.6, drift: 18, noise: true, twinkle: true,
            shapes: [0, 0, 0, 12],
            shapeSize: { 12: [12, 30] }, shapeAlpha: { 12: [0.18, 0.4] }, shapeGlow: { 12: 0 }
        },

        // Thin mist hanging low and rolling sideways, a little dust caught in it
        "fog": {
            n: 14, szMin: 1, szMax: 2.5, spdMin: 6, spdMax: 16,
            dir: "side", fadeIn: 0.3, fadeOut: 0.014, anywhere: true, yMin: 0.35,
            glow: 1.5, drift: 6, noise: true,
            shapes: [9, 0],
            shapeSize: { 9: [80, 170] }, shapeAlpha: { 9: [0.04, 0.1] }, shapeGlow: { 9: 0 },
            tint: "#d8dde6", tintAmt: 0.55
        },

        // Grey ash drifting down, now and then a still-glowing flake
        "ash": {
            n: 48, szMin: 1.5, szMax: 4, spdMin: 6, spdMax: 18,
            dir: "fall", fadeIn: 0.6, fadeOut: 0.03, aMin: 0.5,
            glow: 0, drift: 30, noise: true,
            shapes: [1, 1, 0], spin: true, spinRange: [0.4, 2.0], flip: true,
            gust: 4.0, gustForce: 30,
            tint: "#d2ccc6", tintAmt: 0.75,
            hot: { chance: 0.12, color: "#ff8a3c", glow: 3.0 }
        },

        // ── Weather ──────────────────────────────────────

        "snow": {
            n: 50, szMin: 1.5, szMax: 4, spdMin: 10, spdMax: 30,
            dir: "fall", fadeIn: 0.8, fadeOut: 0.03,
            glow: 0, drift: 34, noise: true,
            shapes: [0, 0, 0, 5], spin: true, spinRange: [0.3, 1.4],
            shapeSize: { 5: [5, 10] },
            gust: 4.0, gustForce: 40,
            tint: "#f4f8ff", tintAmt: 0.8
        },

        // Slanted rain with splashes on a perspective ground line
        "rain": {
            n: 60, szMin: 1, szMax: 1.8, spdMin: 420, spdMax: 680,
            dir: "fall", fadeIn: 3.0, fadeOut: 0.3, slant: 0.2,
            streak: true, streakLen: 28, splash: true, fast: true,
            aMin: 0.35, aMax: 0.8,
            tint: "#d6e4f6", tintAmt: 0.65
        },

        // Heavier rain plus the odd lightning strike and a faint flash
        "storm": {
            n: 78, szMin: 1, szMax: 2, spdMin: 520, spdMax: 820,
            dir: "fall", fadeIn: 3.0, fadeOut: 0.3, slant: 0.26,
            streak: true, streakLen: 34, splash: true, fast: true,
            aMin: 0.35, aMax: 0.85,
            gust: 3.0, gustForce: 60,
            bolt: true, boltRate: 4.5, boltJitter: 60, flash: 0.07,
            tint: "#b4c4e0", tintAmt: 0.6
        },

        // ── Nature ───────────────────────────────────────

        "sakura": {
            n: 30, szMin: 6, szMax: 12, spdMin: 8, spdMax: 22,
            dir: "fall", fadeIn: 0.7, fadeOut: 0.03,
            glow: 0, drift: 50, noise: true,
            shapes: [2], spin: true, spinRange: [0.5, 2.4], flip: true,
            gust: 3.0, gustForce: 60,
            tint: "#ffbcd4", tintAmt: 0.55
        },

        "leaves": {
            n: 20, szMin: 8, szMax: 16, spdMin: 12, spdMax: 30,
            dir: "fall", fadeIn: 0.6, fadeOut: 0.03,
            glow: 0, drift: 60, noise: true,
            shapes: [11], spin: true, spinRange: [0.6, 2.8], flip: true,
            gust: 2.5, gustForce: 75,
            tint: "#d98a3a", tintAmt: 0.45
        },

        // Lights that swell and fade slowly as they wander
        "fireflies": {
            n: 20, szMin: 2, szMax: 3.8, spdMin: 2, spdMax: 10,
            dir: "float", fadeIn: 0.4, fadeOut: 0.02,
            glow: 6.0, drift: 34, noise: true, blink: true, additive: true,
            shapes: [0],
            tint: "#dcff86", tintAmt: 0.5
        },

        // Rising bubbles that wobble, bigger ones faster
        "bubbles": {
            n: 30, szMin: 2, szMax: 9, spdMin: 14, spdMax: 46,
            dir: "rise", fadeIn: 0.8, fadeOut: 0.03, aMin: 0.5,
            glow: 0, drift: 14, wobble: 22, sizeSpeed: true,
            shapes: [8, 8, 8, 0], shapeSize: { 0: [1, 2] },
            tint: "#c4ecff", tintAmt: 0.6
        },

        // ── Fire & combat ────────────────────────────────

        // Flickering sparks climbing faster as they go, the odd one popping
        "embers": {
            n: 56, szMin: 1.2, szMax: 3.6, spdMin: 16, spdMax: 46,
            dir: "rise", fadeIn: 2.5, fadeOut: 0.12, aMin: 0.5,
            glow: 2.6, drift: 26, noise: true, twinkle: true, additive: true,
            shapes: [0, 0, 6], gravity: -18,
            gust: 3.5, gustForce: 30,
            pops: true, popRate: 2.6,
            tint: "#ff8a3c", tintAmt: 0.6
        },

        // Distant tracer fire crossing the frame over drifting smoke
        "tracers": {
            n: 30, szMin: 1, szMax: 2.5, spdMin: 10, spdMax: 26,
            dir: "side", fadeIn: 0.5, fadeOut: 0.05, anywhere: true,
            glow: 0, drift: 10, noise: true,
            shapes: [0, 1, 9], shapeSize: { 9: [60, 140] }, shapeAlpha: { 9: [0.06, 0.14] }, shapeGlow: { 9: 0 },
            tint: "#9c9890", tintAmt: 0.6,
            tracers: true, tracerRate: 0.8, tracerAngle: -0.22, tracerSpread: 0.18, tracerBoth: true,
            tracerSpd: [1600, 2300], tracerLen: [90, 170], tracerW: 1.6, tracerColor: "#ffd27a", fast: true
        },

        // Blowing grit and dust clouds
        "wasteland": {
            n: 42, szMin: 1, szMax: 3.5, spdMin: 30, spdMax: 80,
            dir: "side", fadeIn: 0.7, fadeOut: 0.08,
            glow: 0, drift: 26, noise: true,
            shapes: [0, 1, 1, 9], spin: true, spinRange: [0.2, 1.0],
            shapeSize: { 9: [60, 150] }, shapeAlpha: { 9: [0.08, 0.18] },
            gust: 2.0, gustForce: 80,
            tint: "#d8b98a", tintAmt: 0.5
        },

        // ── Fantasy ──────────────────────────────────────

        // Glitter rising and twinkling, with the odd sparkle pop
        "magic": {
            n: 38, szMin: 1.5, szMax: 6, spdMin: 4, spdMax: 14,
            dir: "rise", fadeIn: 0.7, fadeOut: 0.05,
            glow: 3.2, drift: 22, noise: true, twinkle: true, additive: true,
            shapes: [6, 6, 4, 0], spin: true, spinRange: [0.1, 0.6],
            pops: true, popRate: 3.5
        },

        // Glowing spores drifting up, water dripping from above
        "cavern": {
            n: 34, szMin: 1.5, szMax: 4.5, spdMin: 3, spdMax: 12,
            dir: "rise", fadeIn: 0.7, fadeOut: 0.04,
            glow: 3.8, drift: 20, noise: true, twinkle: true, additive: true,
            shapes: [0, 0, 0, 9], shapeSize: { 9: [30, 60] }, shapeAlpha: { 9: [0.08, 0.18] }, shapeGlow: { 9: 0 },
            drips: true, dripRate: 1.3
        },

        // ── Sci-fi ───────────────────────────────────────

        "stars": {
            n: 64, szMin: 1, szMax: 3, spdMin: 0.3, spdMax: 2,
            dir: "float", fadeIn: 0.8, fadeOut: 0.015, aMin: 0.5,
            glow: 3.5, drift: 3, twinkle: true,
            shapes: [0, 0, 0, 6], shapeSize: { 6: [3, 5] },
            shootingStar: true, shootingRate: 3.5,
            tint: "#eef2ff", tintAmt: 0.45
        },

        // Hyperspace: streaks accelerating out from the centre
        "warp": {
            n: 70, szMin: 0.8, szMax: 2, spdMin: 30, spdMax: 70,
            dir: "radial", fadeIn: 1.6, fadeOut: 0.05, accel: 2.0,
            streak: true, streakK: 0.07, streakMax: 140, fast: true, additive: true,
            shapes: [0],
            tint: "#e6eeff", tintAmt: 0.55
        },

        // Charged motes, with short arcs jumping between close neighbours
        "arcs": {
            n: 30, szMin: 1.5, szMax: 4, spdMin: 3, spdMax: 12,
            dir: "float", fadeIn: 0.6, fadeOut: 0.04,
            glow: 3.6, drift: 16, noise: true, twinkle: true, additive: true,
            shapes: [0, 0, 6],
            arcs: true, arcRate: 0.7, arcDist: 220
        },

        // City-light bokeh rising, light trails sliding past
        "neon": {
            n: 26, szMin: 1.5, szMax: 3, spdMin: 4, spdMax: 12,
            dir: "rise", fadeIn: 0.5, fadeOut: 0.04,
            glow: 3.0, drift: 16, noise: true, twinkle: true, additive: true, satBoost: 0.35,
            shapes: [12, 12, 0], shapeSize: { 12: [10, 34] }, shapeAlpha: { 12: [0.18, 0.4] }, shapeGlow: { 12: 0 },
            tracers: true, tracerRate: 1.4, tracerAngle: 0, tracerSpread: 0.02, tracerBoth: true,
            tracerSpd: [500, 900], tracerLen: [140, 280], tracerW: 2.0
        },

        // Node lattice with data pulses running along the links
        "circuit": {
            n: 30, szMin: 2.5, szMax: 5, spdMin: 2, spdMax: 8,
            dir: "float", fadeIn: 0.7, fadeOut: 0.025, aMin: 0.55,
            glow: 2.2, drift: 8, noise: true,
            shapes: [3, 1, 0], spin: true, spinRange: [0.03, 0.15],
            connections: true, connDist: 170,
            packets: true, packetRate: 0.35
        },

        // Chunky pixels on a grid, twinkling in steps
        "pixel": {
            n: 38, szMin: 3, szMax: 9, spdMin: 6, spdMax: 18,
            dir: "rise", fadeIn: 0.8, fadeOut: 0.05,
            glow: 0, drift: 18, twinkle: true, pixelSnap: 3,
            shapes: [10],
            gust: 3.0, gustForce: 24
        }
    })

    // Old preset keys (saved overrides) → their replacements
    // Old preset names still saved as per-game overrides ("energy" became the sci-fi "arcs")
    readonly property var _aliases: ({ "energy": "arcs", "voidStorm": "arcs", "synthwave": "neon", "parasitic": "ash", "pixelDust": "pixel" })

    // ═════════════════════════════════════════════════════════
    //  DETECTION — first matching rule wins, so specific titles go first
    // ═════════════════════════════════════════════════════════
    readonly property var _rules: [
        // Snowy worlds (before the generic Elder Scrolls → magic rule)
        [/skyrim|valheim|frostpunk|the\s*long\s*dark|never\s*alone|far\s*cry\s*4|northgard|icarus|below\s*zero|horizon\s*(zero|forbidden)|lost\s*planet|project\s*winter|whiteout/, "snow"],
        // Underwater
        [/subnautica|abzu|dave\s*the\s*diver|bioshock|\bsoma\b|barotrauma|beyond\s*blue|in\s*other\s*waters|maneater|depth/, "bubbles"],
        // Horror and survival in the murk
        [/silent\s*hill|phasmophobia|dayz|lethal\s*company|devour|outlast|amnesia|layers\s*of\s*fear|visage|alan\s*wake|sons\s*of\s*the\s*forest|the\s*forest|dead\s*by\s*daylight|until\s*dawn|resident\s*evil|evil\s*within|alien\s*isolation|darkwood|madison|fatal\s*frame|content\s*warning|the\s*medium|little\s*nightmares|^limbo|^inside$|s\.?t\.?a\.?l\.?k\.?e\.?r|metro\s*(2033|last|exodus)|\bscum\b|just\s*survive|cry\s*of\s*fear|f\.e\.a\.r|condemned|observer|distraint/, "fog"],
        // Zombies and the end of the world
        [/zomboid|walking\s*dead|left\s*4\s*dead|back\s*4\s*blood|world\s*war\s*z|dead\s*island|dying\s*light|state\s*of\s*decay|days\s*gone|last\s*of\s*us|z1\s*battle|h1z1|7\s*days\s*to\s*die|dead\s*rising|dead\s*space|zombie|undead|black\s*ops.*zombies/, "ash"],
        // Military and competitive shooters
        [/apex\s*legends|counter[\s-]*strike|call\s*of\s*duty|battlefield|rainbow\s*six|\barma\b|\bsquad\b|insurgency|hell\s*let\s*loose|ready\s*or\s*not|tarkov|pubg|battlegrounds|warzone|payday|war\s*thunder|world\s*of\s*(tanks|warships)|heroes\s*&\s*generals|blacklight|warface|soldier\s*front|blockade|farlight|super\s*people|hunt:\s*showdown|helldivers|ghost\s*recon|the\s*division|ravenfield|pavlov|fragpunk|delta\s*force|rising\s*storm|foxhole|enlisted/, "tracers"],
        // Neon, cities at night, aim trainers
        [/cyberpunk|deus\s*ex|hotline\s*miami|outdrive|ghostrunner|katana\s*zero|the\s*finals|valorant|rocket\s*league|saints\s*row|grand\s*theft|\bgta\b|watch\s*dogs|sleeping\s*dogs|need\s*for\s*speed|kovaak|aim\s*labs?|\bosu\b|mcosu|beat\s*saber|pistol\s*whip|synthwave|neon|mirror'?s\s*edge|\bapb\b|cyber\s*hunter|trackmania|\btron\b/, "neon"],
        // Starships and hyperspace
        [/no\s*man'?s\s*sky|elite\s*dangerous|star\s*citizen|everspace|starfield|\bftl\b|homeworld|eve\s*online|\bx4\b|rebel\s*galaxy|star\s*wars|mass\s*effect/, "warp"],
        // Quiet space
        [/space\s*engineers|stellaris|outer\s*wilds|kerbal|starbound|astroneer|risk\s*of\s*rain|surviving\s*mars|orion/, "stars"],
        // Energy weapons and sci-fi tech
        [/warframe|half[\s-]*life|black\s*mesa|destiny|\bhalo\b|first\s*descendant|control(?!ler)|returnal|prey(?!.*wild)|quake|unreal\s*tournament|titanfall|robocraft|mecha|mechwarrior|armored\s*core|vanquish/, "arcs"],
        // Building, logistics, puzzles
        [/portal|factorio|satisfactory|dyson\s*sphere|shapez|system\s*shock|hacknet|uplink|cities|sim\s*city|openttd|transport\s*(tycoon|fever)|prison\s*architect|two\s*point/, "circuit"],
        // Fire and steel
        [/doom|diablo|hades|dark\s*souls|elden\s*ring|sekiro|bloodborne|nioh|lies\s*of\s*p|remnant|god\s*of\s*war|devil\s*may\s*cry|darksiders|bayonetta|killing\s*floor|code\s*vein|hellblade|dragon\s*ball|monster\s*hunter|mordhau|chivalry|for\s*honor|bannerlord|mount\s*&\s*blade|kingdom\s*come|vermintide|darktide|path\s*of\s*exile|wolfenstein|shadow\s*of\s*(mordor|war)|metal\s*gear\s*rising/, "embers"],
        // Dust and ruins
        [/fallout|mad\s*max|wasteland|rage\s*2|borderlands|rust(?!le)|unturned|arc\s*raiders|metal\s*gear\s*solid\s*v|phantom\s*pain|death\s*stranding|kenshi|\bdune\b|conan\s*exiles/, "wasteland"],
        // Cherry blossom
        [/ghost\s*of\s*tsushima|okami|sakura|everlasting\s*summer|highway\s*blossoms/, "sakura"],
        // Glowing wanderers
        [/hollow\s*knight|ori\s*and|firewatch|celeste|\bgris\b|spiritfarer|stray|don'?t\s*starve|tunic|kena|unravel|night\s*in\s*the\s*woods|darkside\s*detective|journey|sea\s*of\s*thieves/, "fireflies"],
        // Farms, jungles, the outdoors
        [/stardew|animal\s*crossing|harvest\s*moon|my\s*time\s*at|sun\s*haven|stranded\s*deep|\bark\b|palworld|far\s*cry\s*3|green\s*hell|red\s*dead|grounded|fae\s*farm|story\s*of\s*seasons|slime\s*rancher/, "leaves"],
        // Blocks
        [/minecraft|roblox|\blego\b|teardown|cube\s*world|vintage\s*story/, "pixel"],
        // Underground and dungeon crawls
        [/terraria|core\s*keeper|deep\s*rock|stoneshard|spelunky|dead\s*cells|enter\s*the\s*gungeon|binding\s*of\s*isaac|slay\s*the\s*spire|dome\s*keeper|darkest\s*dungeon|noita/, "cavern"],
        // Fantasy, MMOs, hero shooters
        [/elder\s*scrolls|oblivion|witcher|final\s*fantasy|baldur|divinity|pathfinder|pillars\s*of\s*eternity|tyranny|magicka|zelda|hogwarts|dishonored|bastion|transistor|nier|overwatch|deadlock|marvel|dota|league\s*of\s*legends|smite|brawlhalla|^tera$|black\s*desert|trove|guild\s*wars|warcraft|lost\s*ark|gorgon|two\s*worlds|x-blades|dragon\s*age|dragon'?s\s*dogma|torment|wizard|genshin/, "magic"]
    ]

    function _resolve(key) { return _aliases[key] || key; }

    function _detect(name, id) {
        if (id) {
            const _ = GameLauncherService.particleOverridesRevision;
            const ov = GameLauncherService.getParticleOverride(id);
            if (ov && ov !== "auto") return _resolve(ov);
        }
        if (!name) return "ambient";
        const n = name.toLowerCase();
        for (let i = 0; i < _rules.length; i++) {
            if (_rules[i][0].test(n)) return _rules[i][1];
        }
        return "ambient";
    }

    // ═════════════════════════════════════════════════════════
    //  COLOUR UTILITIES
    // ═════════════════════════════════════════════════════════
    function _hash(s) {
        let h = 0;
        for (let i = 0; i < s.length; i++) { h = ((h << 5) - h) + s.charCodeAt(i); h |= 0; }
        return Math.abs(h);
    }
    function _hsl(h, s, l) {
        s /= 100; l /= 100;
        const c = (1 - Math.abs(2 * l - 1)) * s;
        const x = c * (1 - Math.abs((h / 60) % 2 - 1));
        const m = l - c / 2;
        let r, g, b;
        if (h < 60) { r=c; g=x; b=0; } else if (h < 120) { r=x; g=c; b=0; }
        else if (h < 180) { r=0; g=c; b=x; } else if (h < 240) { r=0; g=x; b=c; }
        else if (h < 300) { r=x; g=0; b=c; } else { r=c; g=0; b=x; }
        return "#" + ((1<<24)+(Math.round((r+m)*255)<<16)+(Math.round((g+m)*255)<<8)+Math.round((b+m)*255)).toString(16).slice(1);
    }
    function _genColors(name) {
        const h = _hash(name || "game"), hue = h % 360, out = [];
        for (let i = 0; i < 5; i++) out.push(_hsl((hue + i * 25) % 360, 45 + ((h >> (i*3)) % 35), 55 + ((h >> (i*4+2)) % 30)));
        return out;
    }
    function _hex2rgb(hex) {
        if (!hex || hex.length < 7) return { r: 200, g: 200, b: 255 };
        return { r: parseInt(hex.substr(1,2),16), g: parseInt(hex.substr(3,2),16), b: parseInt(hex.substr(5,2),16) };
    }
    function _rgba(rgb, a) { return "rgba(" + rgb.r + "," + rgb.g + "," + rgb.b + "," + a + ")"; }
    function _rgb(c) { return "rgb(" + c.r + "," + c.g + "," + c.b + ")"; }

    // ═════════════════════════════════════════════════════════
    //  NOISE — layered sines for organic movement
    // ═════════════════════════════════════════════════════════
    function _noise2d(x, y) {
        return _fsin(x * 0.7 + y * 0.3) * 0.3
             + _fsin(x * 0.3 - y * 0.7 + 1.5) * 0.3
             + _fsin(x * 1.1 + y * 0.9 + 3.0) * 0.15
             + _fsin(x * 0.5 - y * 1.3 + 5.0) * 0.1;
    }

    // ═════════════════════════════════════════════════════════
    //  TRIG LUT (256 entries)
    // ═════════════════════════════════════════════════════════
    property var _sL: []
    property var _cL: []
    function _initLut() {
        const N = 256, s = new Array(N), c = new Array(N), k = Math.PI * 2 / N;
        for (let i = 0; i < N; i++) { const a = i * k; s[i] = Math.sin(a); c[i] = Math.cos(a); }
        _sL = s; _cL = c;
    }
    function _fsin(a) { return _sL[Math.round(((a % 6.2832) + 6.2832) % 6.2832 * 40.7437) % 256]; }
    function _fcos(a) { return _cL[Math.round(((a % 6.2832) + 6.2832) % 6.2832 * 40.7437) % 256]; }

    // ═════════════════════════════════════════════════════════
    //  COLOURS FROM HERO ART
    // ═════════════════════════════════════════════════════════
    property string _imgSrc: {
        const s = root.imageSource;
        if (!s) return "";
        const str = s.toString();
        if (str.startsWith("file://")) return str;
        if (str.startsWith("/")) return "file://" + str;
        return str;
    }
    ColorQuantizer {
        id: _cq
        source: root._imgSrc
        depth: 3
        rescaleSize: 20
        onColorsChanged: root._applyQuantizerColors()
    }
    function _applyQuantizerColors() {
        const qc = _cq.colors;
        if (!qc || qc.length === 0) return;
        const hexArr = [];
        for (let i = 0; i < qc.length && hexArr.length < 6; i++) {
            const hex = qc[i].toString();
            if (hex.length < 7) continue;
            const r = parseInt(hex.substr(1,2),16), g = parseInt(hex.substr(3,2),16), b = parseInt(hex.substr(5,2),16);
            // To HSL, then lift lightness and saturation so particles read against the art
            const mx = Math.max(r,g,b), mn = Math.min(r,g,b), d = mx - mn;
            let h = 0, s = 0, l = (mx + mn) / 510;
            if (d > 0) {
                s = l > 0.5 ? d / (510 - mx - mn) : d / (mx + mn);
                if (mx === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
                else if (mx === g) h = ((b - r) / d + 2) / 6;
                else h = ((r - g) / d + 4) / 6;
            }
            if (s < 0.08 && hexArr.length > 0) continue; // near-grey adds nothing after the first
            if (l < 0.45) l = 0.45 + (l / 0.45) * 0.15;
            if (s > 0.05 && s < 0.35) s = 0.35;
            const hue2rgb = function(p, q, t) {
                if (t < 0) t += 1; if (t > 1) t -= 1;
                if (t < 1/6) return p + (q - p) * 6 * t;
                if (t < 1/2) return q;
                if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
                return p;
            };
            let nr, ng, nb;
            if (s === 0) { nr = ng = nb = l; }
            else {
                const q2 = l < 0.5 ? l * (1 + s) : l + s - l * s, p2 = 2 * l - q2;
                nr = hue2rgb(p2, q2, h + 1/3); ng = hue2rgb(p2, q2, h); nb = hue2rgb(p2, q2, h - 1/3);
            }
            const ri = Math.round(nr * 255), gi = Math.round(ng * 255), bi = Math.round(nb * 255);
            hexArr.push("#" + ((1<<24)+(ri<<16)+(gi<<8)+bi).toString(16).slice(1));
        }
        if (hexArr.length > 0) _setColors(hexArr);
    }
    // Raw palette → preset palette (tint toward the theme colour, optional saturation boost),
    // then recolour live particles so the switch from name-hash to art colours isn't visible
    function _setColors(hexArr) {
        _rawColors = hexArr.map(_hex2rgb);
        _retint();
    }
    function _retint() {
        const cfg = _cfg;
        const tint = cfg.tint ? _hex2rgb(cfg.tint) : null;
        const amt = tint ? (cfg.tintAmt || 0.5) : 0;
        const boost = cfg.satBoost || 0;
        const out = [];
        for (let i = 0; i < _rawColors.length; i++) {
            let c = _rawColors[i];
            let r = c.r, g = c.g, b = c.b;
            if (boost > 0) {
                const avg = (r + g + b) / 3;
                r = avg + (r - avg) * (1 + boost); g = avg + (g - avg) * (1 + boost); b = avg + (b - avg) * (1 + boost);
            }
            if (tint) { r = r + (tint.r - r) * amt; g = g + (tint.g - g) * amt; b = b + (tint.b - b) * amt; }
            out.push({ r: Math.max(0, Math.min(255, Math.round(r))), g: Math.max(0, Math.min(255, Math.round(g))), b: Math.max(0, Math.min(255, Math.round(b))) });
        }
        _colors = out;
        if (_ci && out.length > 0) {
            for (let i = 0; i < _count; i++) {
                if (_ci[i] === 255) continue; // fixed colour (hot ash)
                const c = out[_ci[i] % out.length];
                _cr[i] = c.r; _cg[i] = c.g; _cb[i] = c.b;
            }
        }
    }

    // ═════════════════════════════════════════════════════════
    //  GLOW — a radial gradient per halo. (A pre-rendered sprite can't be tinted, and drawImage
    //  from a data URL re-resolves the whole URL string on every call, which cost 2-3x the CPU)
    // ═════════════════════════════════════════════════════════
    function _glow(ctx, x, y, r, cr, cg, cb) {
        const c = "rgba(" + cr + "," + cg + "," + cb + ",";
        const g = ctx.createRadialGradient(x, y, 0, x, y, r);
        g.addColorStop(0, "rgba(" + ((cr + 255) >> 1) + "," + ((cg + 255) >> 1) + "," + ((cb + 255) >> 1) + ",0.9)");
        g.addColorStop(0.15, c + "0.6)");
        g.addColorStop(0.45, c + "0.18)");
        g.addColorStop(1, c + "0)");
        ctx.fillStyle = g;
        ctx.fillRect(x - r, y - r, r * 2, r * 2);
    }

    // ═════════════════════════════════════════════════════════
    //  LIGHTNING
    // ═════════════════════════════════════════════════════════
    function _genBolt(x1, y1, x2, y2, depth, jitter) {
        if (depth <= 0) return [{x: x1, y: y1}, {x: x2, y: y2}];
        const mx = (x1 + x2) / 2 + (Math.random() - 0.5) * jitter;
        const my = (y1 + y2) / 2 + (Math.random() - 0.5) * jitter;
        const left = _genBolt(x1, y1, mx, my, depth - 1, jitter * 0.55);
        const right = _genBolt(mx, my, x2, y2, depth - 1, jitter * 0.55);
        return left.concat(right.slice(1));
    }
    // Sky-to-ground strike (storm)
    function _spawnBolt(w, h) {
        const jitter = _cfg.boltJitter || 40;
        const x1 = w * 0.15 + Math.random() * w * 0.7;
        const y1 = -10;
        const x2 = x1 + (Math.random() - 0.5) * w * 0.3;
        const y2 = h * 0.6 + Math.random() * h * 0.35;
        const pts = _genBolt(x1, y1, x2, y2, 5, jitter);
        const branch = [];
        if (Math.random() < 0.7 && pts.length > 4) {
            const bp = pts[2 + Math.floor(Math.random() * (pts.length - 4))];
            const bPts = _genBolt(bp.x, bp.y, bp.x + (Math.random() - 0.5) * jitter * 3, bp.y + h * (0.1 + Math.random() * 0.2), 3, jitter * 0.5);
            for (let i = 0; i < bPts.length; i++) branch.push(bPts[i]);
        }
        _bolts.push({ pts: pts, branch: branch, life: 0.45, maxLife: 0.45, w: 2.2 });
        if (_cfg.flash) _flashAlpha = _cfg.flash;
    }
    // Short arc between two nearby particles (arcs)
    function _spawnArc() {
        if (_count < 2) return;
        const i = Math.floor(Math.random() * _count);
        const maxD = _cfg.arcDist || 200;
        let best = -1, bestD = maxD * maxD;
        for (let j = 0; j < _count; j++) {
            if (j === i || _al[j] < 0.2) continue;
            const dx = _px[j] - _px[i], dy = _py[j] - _py[i], d = dx*dx + dy*dy;
            if (d < bestD && d > 400) { bestD = d; best = j; }
        }
        if (best < 0) return;
        const dist = Math.sqrt(bestD);
        const pts = _genBolt(_px[i], _py[i], _px[best], _py[best], 4, dist * 0.35);
        _bolts.push({ pts: pts, branch: [], life: 0.22, maxLife: 0.22, w: 1.3 });
        if (_bolts.length > 6) _bolts.splice(0, _bolts.length - 6);
        _tm[i] = 1; _tm[best] = 1;
    }

    // ═════════════════════════════════════════════════════════
    //  SMALL EFFECT SPAWNERS
    // ═════════════════════════════════════════════════════════
    function _spawnSparkBurst(x, y, c) {
        const num = 5 + Math.floor(Math.random() * 5);
        const sparks = [];
        for (let i = 0; i < num; i++) {
            const a = Math.random() * 6.2832;
            const spd = 25 + Math.random() * 55;
            sparks.push({ x: x, y: y, vx: Math.cos(a) * spd, vy: Math.sin(a) * spd - 15,
                          al: 0.8 + Math.random() * 0.2, life: 0.3 + Math.random() * 0.35, sz: 0.8 + Math.random() * 1.4,
                          r: c.r, g: c.g, b: c.b });
        }
        _sparkBursts.push({ sparks: sparks });
        if (_sparkBursts.length > 6) _sparkBursts.splice(0, _sparkBursts.length - 6);
    }
    function _spawnRipple(x, y, maxR) {
        _ripples.push({ x: x, y: y, r: 0, maxR: maxR, life: 0.45, maxLife: 0.45 });
        if (_ripples.length > 24) _ripples.splice(0, _ripples.length - 24);
    }
    function _spawnTracer(w, h) {
        const cfg = _cfg;
        let a = (cfg.tracerAngle || 0) + (Math.random() - 0.5) * 2 * (cfg.tracerSpread || 0);
        if (cfg.tracerBoth && Math.random() < 0.5) a += Math.PI;
        const dx = Math.cos(a), dy = Math.sin(a);
        // Pick a point the tracer passes through, then back up to just outside the frame
        const px = w * (0.1 + Math.random() * 0.8), py = h * (0.15 + Math.random() * 0.7);
        const back = Math.abs(dx) > 0.01 ? (dx > 0 ? px : w - px) / Math.abs(dx) : h;
        const sr = cfg.tracerSpd || [1500, 2000], lr = cfg.tracerLen || [100, 160];
        const spd = sr[0] + Math.random() * (sr[1] - sr[0]);
        const len = lr[0] + Math.random() * (lr[1] - lr[0]);
        const c = cfg.tracerColor ? _hex2rgb(cfg.tracerColor) : (_colors[Math.floor(Math.random() * _colors.length)] || { r: 255, g: 255, b: 255 });
        const travel = back + w + len;
        _tracers.push({ x: px - dx * (back + 20), y: py - dy * (back + 20), dx: dx, dy: dy, spd: spd, len: len,
                        life: travel / spd, c: c, w: (cfg.tracerW || 1.5) * (0.7 + Math.random() * 0.6) });
        if (_tracers.length > 6) _tracers.splice(0, 1);
    }

    // ═════════════════════════════════════════════════════════
    //  SoA BUFFER ALLOCATION
    // ═════════════════════════════════════════════════════════
    function _allocBuffers() {
        const n = _cap;
        _px = new Float64Array(n); _py = new Float64Array(n);
        _vx = new Float64Array(n); _vy = new Float64Array(n);
        _sz = new Float64Array(n); _al = new Float64Array(n);
        _mx = new Float64Array(n); _fr = new Float64Array(n);
        _dp = new Float64Array(n); _ag = new Float64Array(n);
        _ph = new Float64Array(n); _sp = new Float64Array(n);
        _rt = new Float64Array(n); _gy = new Float64Array(n);
        _gw = new Float64Array(n); _ci = new Uint8Array(n);
        _cr = new Uint8Array(n); _cg = new Uint8Array(n); _cb = new Uint8Array(n);
        _sh = new Uint8Array(n);
        _tm = new Float64Array(n);
        for (let i = 0; i < n; i++) _tm[i] = 1.0;
        _count = 0;
    }

    // ═════════════════════════════════════════════════════════
    //  INITIALISATION
    // ═════════════════════════════════════════════════════════
    Component.onCompleted: { _initLut(); _allocBuffers(); _init(); }
    Timer { id: _initDelay; interval: 10; onTriggered: root._init() }
    onGameIdChanged: _initDelay.restart()
    onGameNameChanged: _initDelay.restart()
    onImageSourceChanged: _initDelay.restart()
    onForcePresetChanged: _initDelay.restart()
    // Density changes live: the spawner fills up to the new count, or the extra ones go
    property real _areaScale: 1
    function _retarget() {
        _target = Math.min(_cap, Math.round((_cfg?.n || 0) * _areaScale * densityScale));
        if (_count > _target) _count = _target;
    }
    onDensityScaleChanged: _retarget()
    Connections {
        target: GameLauncherService
        function onParticleOverridesRevisionChanged() {
            if (root.active && root.gameId) _initDelay.restart();
        }
    }
    onActiveChanged: {
        if (active) _init();
        else { _clearEffects(); _count = 0; _fadeOut = []; _ready = false; }
    }
    function _clearEffects() {
        _bolts = []; _sparkBursts = []; _ripples = []; _drips = []; _tracers = []; _packets = []; _links = [];
        _shooting = null; _flashAlpha = 0;
        _boltTimer = 0; _arcTimer = 0; _popTimer = 0; _dripTimer = 0; _tracerTimer = 0; _packetTimer = 0; _shootT = 0;
    }

    function _init() {
        // Crossfade the old particles out as simple dots
        if (_ready && _count > 0) {
            const fo = [];
            for (let i = 0; i < _count; i++) {
                if (_sh[i] === _sSoft || _sz[i] > 20) continue;
                fo.push({ x: _px[i], y: _py[i], sz: Math.min(_sz[i], 6), al: _al[i] * _tm[i], r: _cr[i], g: _cg[i], b: _cb[i], fr: 1.5 });
            }
            _fadeOut = fo.length > 40 ? fo.slice(-40) : fo;
        } else { _fadeOut = []; }

        _count = 0; _clearEffects();
        _time = 0; _lastMs = 0;
        _ready = false;
        _wph = 0; _wx = 0; _wy = 0;
        _gTimer = 0; _gStr = 0;

        if (!active) return;
        _preset = _resolve(forcePreset) || _detect(gameName, gameId);
        _cfg = _presets[_preset] || _presets["ambient"];

        // Name-hash palette straight away, replaced by the art's colours once the quantizer has them
        _setColors(_genColors(gameName));
        _applyQuantizerColors();

        // Scale the count with the canvas area
        const cw = _mainCanvas.width || width, ch = _mainCanvas.height || height;
        const scale = (cw > 0 && ch > 0) ? Math.sqrt((cw * ch) / 240000) : 1;
        _areaScale = Math.max(0.5, Math.min(1.8, scale));
        _retarget();

        if (cw > 0 && ch > 0) {
            for (let i = 0; i < _target; i++) _spawnAt(i, true);
            _count = _target;
        }
        _ready = true;
    }

    // ═════════════════════════════════════════════════════════
    //  PARTICLE SPAWN (writes into SoA at index i)
    // ═════════════════════════════════════════════════════════
    function _spawnAt(i, scatter) {
        const cfg = _cfg;
        const w = _mainCanvas.width || width, h = _mainCanvas.height || height;
        if (w <= 0 || h <= 0) return;
        const cols = _colors.length > 0 ? _colors : [{r:200,g:200,b:255}];

        const shapes = cfg.shapes || [0];
        const shape = shapes[Math.floor(Math.random() * shapes.length)];
        _sh[i] = shape;

        const depth = 0.3 + Math.random() * 0.7;
        _dp[i] = depth;
        const sr = (cfg.shapeSize && cfg.shapeSize[shape]) || [cfg.szMin, cfg.szMax];
        const sizeT = Math.random();
        _sz[i] = (sr[0] + sizeT * (sr[1] - sr[0])) * (0.5 + depth * 0.5) * _sizeK;
        if (cfg.pixelSnap) _sz[i] = Math.max(1, Math.round(_sz[i] / cfg.pixelSnap)) * cfg.pixelSnap;
        // Bigger bubbles rise faster; otherwise nearer particles move faster
        let spd = (cfg.spdMin + (cfg.sizeSpeed ? sizeT : Math.random()) * (cfg.spdMax - cfg.spdMin)) * (0.4 + depth * 0.6);
        if (shape === _sSoft) spd *= 0.6; // clouds lag behind the grit

        _ph[i] = Math.random() * 6.2832;
        _ag[i] = scatter && !cfg.anywhere ? Math.random() * 2 : 0;
        const ar = (cfg.shapeAlpha && cfg.shapeAlpha[shape]) || [cfg.aMin || 0.4, cfg.aMax || 1.0];
        _mx[i] = ar[0] + Math.random() * (ar[1] - ar[0]);
        _al[i] = scatter && !(cfg.anywhere && _ready) ? _mx[i] * (0.3 + Math.random() * 0.7) : 0;
        _fr[i] = cfg.fadeOut * (1 + Math.random());
        _rt[i] = Math.random() * 6.2832;
        _tm[i] = 1.0;
        _gw[i] = (cfg.shapeGlow && cfg.shapeGlow[shape] !== undefined) ? cfg.shapeGlow[shape] : (cfg.glow || 0);

        // Colour: palette, or the preset's fixed "hot" colour for a few
        if (cfg.hot && Math.random() < cfg.hot.chance) {
            const hc = _hex2rgb(cfg.hot.color);
            _ci[i] = 255; _cr[i] = hc.r; _cg[i] = hc.g; _cb[i] = hc.b;
            _gw[i] = cfg.hot.glow || 2;
        } else {
            const ci = Math.floor(Math.random() * cols.length);
            _ci[i] = ci; _cr[i] = cols[ci].r; _cg[i] = cols[ci].g; _cb[i] = cols[ci].b;
        }

        if (cfg.spin) {
            const spr = cfg.spinRange || [0.1, 0.5];
            _sp[i] = (spr[0] + Math.random() * (spr[1] - spr[0])) * (Math.random() < 0.5 ? -1 : 1);
        } else { _sp[i] = 0; }

        const pad = _sz[i] * 2 + 4;
        // Slow drifters respawn anywhere and fade in; from the edge they'd take minutes to arrive
        if (cfg.anywhere) scatter = true;
        switch (cfg.dir) {
        case "rise":
            _px[i] = Math.random() * w;
            _py[i] = scatter ? Math.random() * h : h + pad;
            _vx[i] = 0; _vy[i] = -spd;
            break;
        case "fall": {
            const slant = cfg.slant || 0;
            // Slanted rain drifts sideways while falling, so start it further upwind
            _px[i] = Math.random() * (w + h * slant) - h * slant;
            _py[i] = scatter ? Math.random() * h : -pad - Math.random() * 40;
            _vx[i] = spd * slant; _vy[i] = spd;
            break;
        }
        case "side": {
            const yMin = cfg.yMin || 0; // keeps low-lying effects (fog) off the top of the art
            _px[i] = scatter ? Math.random() * w : -pad;
            _py[i] = h * (yMin + Math.random() * (1 - yMin));
            _vx[i] = spd; _vy[i] = 0;
            break;
        }
        case "radial": {
            const a = Math.random() * 6.2832, r0 = 8 + Math.random() * Math.min(w, h) * (scatter ? 0.5 : 0.08);
            _px[i] = w / 2 + Math.cos(a) * r0;
            _py[i] = h / 2 + Math.sin(a) * r0;
            const sp2 = scatter ? spd * (1 + r0 / 40) : spd;
            _vx[i] = Math.cos(a) * sp2; _vy[i] = Math.sin(a) * sp2;
            break;
        }
        default: // float
            _px[i] = Math.random() * w;
            _py[i] = Math.random() * h;
            _vx[i] = 0; _vy[i] = 0;
        }
        // Where rain lands: lower in the frame for nearer drops
        _gy[i] = h * (0.62 + depth * 0.36);
    }

    // ═════════════════════════════════════════════════════════
    //  FRAME RATE — only fast effects need 60 fps; drifters look the same at 30 for half the CPU
    // ═════════════════════════════════════════════════════════
    property int _fint: 33
    onWidthChanged: { const a = width * height; _fint = a < 40000 ? 50 : a > 300000 ? 16 : 33; }
    onHeightChanged: { const a = width * height; _fint = a < 40000 ? 50 : a > 300000 ? 16 : 33; }
    readonly property bool _fastPreset: !!_cfg.fast || !!_cfg.bolt || !!_cfg.arcs
    readonly property int _frameInterval: _fastPreset ? _fint : Math.max(_fint, 33)

    Timer {
        id: _timer
        interval: root._frameInterval; repeat: true
        running: root.active && root._ready && root.visible && root.width > 0
        onTriggered: {
            const now = Date.now();
            if (root._lastMs === 0) root._lastMs = now;
            const dt = Math.min((now - root._lastMs) / 1000.0, 0.1);
            root._lastMs = now;
            root._time += dt;
            root._update(dt);
            _softCanvas.requestPaint();
            _mainCanvas.requestPaint();
        }
    }

    // ═════════════════════════════════════════════════════════
    //  UPDATE
    // ═════════════════════════════════════════════════════════
    function _every(timerName, rate, dt) {
        // Jittered interval timer: true roughly once per `rate` seconds
        root[timerName] += dt;
        if (root[timerName] >= rate) { root[timerName] = -rate * (Math.random() * 0.6 - 0.3); return true; }
        return false;
    }

    function _update(dt) {
        const cfg = _cfg;
        const w = _mainCanvas.width, h = _mainCanvas.height;
        const t = _time;
        const px = _px, py = _py, vx = _vx, vy = _vy;
        const al = _al, mx = _mx, fr = _fr, sz = _sz, dp = _dp, ag = _ag, ph = _ph;
        const sp = _sp, rt = _rt;
        const cnt = _count;

        // ── Wind and gusts ───────────────────────────────
        _wph += dt * 0.3;
        _wx = _fsin(_wph * 0.7) * 6;
        _wy = _fcos(_wph * 0.5) * 2;
        if (cfg.gust > 0) {
            _gTimer += dt;
            if (_gTimer >= cfg.gust) {
                _gTimer -= cfg.gust * (0.7 + Math.random() * 0.6);
                const ga = Math.random() * 6.2832;
                _gx = Math.cos(ga) * (cfg.gustForce || 30);
                _gyF = Math.sin(ga) * (cfg.gustForce || 30) * 0.3;
                _gStr = 1.0;
            }
            if (_gStr > 0) { _gStr -= dt * 1.2; if (_gStr < 0) _gStr = 0; }
        }
        // Gusts ease in and out instead of snapping on
        const gs = _gStr * _gStr * (3 - 2 * _gStr);
        const gx = _gx * gs, gy = _gyF * gs;

        // ── Timed effects ────────────────────────────────
        if (cfg.shootingStar) {
            if (_every("_shootT", cfg.shootingRate || 4, dt) && !_shooting) {
                const life = 0.6 + Math.random() * 0.4;
                _shooting = { x: Math.random() * w * 0.7, y: Math.random() * h * 0.35, a: 0.25 + Math.random() * 0.4,
                              spd: 380 + Math.random() * 220, life: life, max: life, len: 40 + Math.random() * 50,
                              c: _colors[0] || { r: 255, g: 255, b: 255 } };
            }
        }
        if (_shooting) {
            _shooting.life -= dt;
            _shooting.x += Math.cos(_shooting.a) * _shooting.spd * dt;
            _shooting.y += Math.sin(_shooting.a) * _shooting.spd * dt;
            if (_shooting.life <= 0) _shooting = null;
        }
        if (cfg.bolt && _every("_boltTimer", cfg.boltRate || 5, dt) && _bolts.length < 2) _spawnBolt(w, h);
        if (cfg.arcs && _every("_arcTimer", cfg.arcRate || 0.8, dt)) _spawnArc();
        if (cfg.pops && cnt > 0 && _every("_popTimer", cfg.popRate || 3, dt)) {
            const si = Math.floor(Math.random() * cnt);
            if (al[si] > 0.3) _spawnSparkBurst(px[si], py[si], { r: _cr[si], g: _cg[si], b: _cb[si] });
        }
        if (cfg.tracers && _every("_tracerTimer", cfg.tracerRate || 1, dt)) {
            _spawnTracer(w, h);
            // Fire comes in short bursts
            if (cfg.tracerColor && Math.random() < 0.5) { const last = _tracers[_tracers.length - 1]; _spawnTracer(w, h); const nt = _tracers[_tracers.length - 1];
                nt.x = last.x - last.dx * 60; nt.y = last.y - last.dy * 60 + (Math.random() - 0.5) * 20; nt.dx = last.dx; nt.dy = last.dy; nt.life = last.life + 60 / nt.spd; }
        }
        if (cfg.drips && _every("_dripTimer", cfg.dripRate || 1.5, dt) && _drips.length < 4) {
            const d = 0.4 + Math.random() * 0.6;
            _drips.push({ x: w * (0.1 + Math.random() * 0.8), y: -6, vy: 0, d: d, ground: h * (0.65 + d * 0.33),
                          c: _colors[Math.floor(Math.random() * _colors.length)] || { r: 200, g: 220, b: 255 } });
        }
        if (cfg.packets && _links.length >= 4 && _every("_packetTimer", cfg.packetRate || 0.4, dt) && _packets.length < 8) {
            const li = Math.floor(Math.random() * (_links.length / 4)) * 4;
            const fwd = Math.random() < 0.5;
            _packets.push({ x1: fwd ? _links[li] : _links[li+2], y1: fwd ? _links[li+1] : _links[li+3],
                            x2: fwd ? _links[li+2] : _links[li], y2: fwd ? _links[li+3] : _links[li+1],
                            t: 0, dur: 0.5 + Math.random() * 0.5, c: _colors[Math.floor(Math.random() * _colors.length)] || { r: 255, g: 255, b: 255 } });
        }

        // ── Advance effects ──────────────────────────────
        let k = 0;
        for (let i = 0; i < _bolts.length; i++) { _bolts[i].life -= dt; if (_bolts[i].life > 0) _bolts[k++] = _bolts[i]; }
        _bolts.length = k;

        k = 0;
        for (let i = 0; i < _sparkBursts.length; i++) {
            const sb = _sparkBursts[i];
            let alive = false;
            for (let j = 0; j < sb.sparks.length; j++) {
                const s = sb.sparks[j];
                s.x += s.vx * dt; s.y += s.vy * dt; s.vy += 40 * dt; s.vx *= (1 - dt * 1.5);
                s.life -= dt; s.al = Math.max(0, s.life * 2.5);
                if (s.life > 0) alive = true;
            }
            if (alive) _sparkBursts[k++] = sb;
        }
        _sparkBursts.length = k;

        k = 0;
        for (let i = 0; i < _ripples.length; i++) {
            const r = _ripples[i];
            r.life -= dt; r.r += r.maxR * dt * 2.6;
            if (r.life > 0) _ripples[k++] = r;
        }
        _ripples.length = k;

        k = 0;
        for (let i = 0; i < _drips.length; i++) {
            const d = _drips[i];
            d.vy += 700 * dt; d.y += d.vy * dt;
            if (d.y >= d.ground) { _spawnRipple(d.x, d.ground, 10 + d.d * 14); _spawnSparkBurst(d.x, d.ground, d.c); continue; }
            _drips[k++] = d;
        }
        _drips.length = k;

        k = 0;
        for (let i = 0; i < _tracers.length; i++) {
            const tr = _tracers[i];
            tr.x += tr.dx * tr.spd * dt; tr.y += tr.dy * tr.spd * dt; tr.life -= dt;
            if (tr.life > 0) _tracers[k++] = tr;
        }
        _tracers.length = k;

        k = 0;
        for (let i = 0; i < _packets.length; i++) { _packets[i].t += dt / _packets[i].dur; if (_packets[i].t < 1) _packets[k++] = _packets[i]; }
        _packets.length = k;

        if (_flashAlpha > 0) { _flashAlpha -= dt * 0.9; if (_flashAlpha < 0) _flashAlpha = 0; }

        // ── Particles ────────────────────────────────────
        const gravity = cfg.gravity || 0;
        const drift = cfg.drift || 0;
        const dir = cfg.dir;
        const fadeInRate = cfg.fadeIn || 0.5;
        const hasNoise = !!cfg.noise;
        const wobble = cfg.wobble || 0;
        const accel = cfg.accel || 0;
        const splash = !!cfg.splash;
        const pix = cfg.pixelSnap || 0;

        let writeI = 0;
        for (let i = 0; i < cnt; i++) {
            ag[i] += dt;
            const d = dp[i];
            const wsc = d * dt;

            if (dir === "rise" || dir === "fall") {
                px[i] += vx[i] * dt + _wx * wsc + gx * wsc;
                py[i] += vy[i] * dt + _wy * wsc * 0.3 + gy * wsc;
                if (hasNoise && drift > 0) {
                    px[i] += _noise2d(px[i] * 0.01, t * 0.3 + ph[i]) * drift * dt;
                    py[i] += _noise2d(py[i] * 0.01 + 100, t * 0.35 + ph[i] * 1.3) * drift * dt * 0.4;
                } else if (drift > 0) {
                    px[i] += _fsin(ph[i] + t * 0.5) * drift * dt;
                }
                if (wobble > 0) px[i] += _fcos(ph[i] + t * (2 + d * 2)) * wobble * dt;
                if (gravity !== 0) vy[i] += gravity * dt;
            } else if (dir === "side") {
                px[i] += vx[i] * dt + gx * wsc;
                py[i] += _wy * wsc * 0.3 + gy * wsc;
                if (hasNoise && drift > 0) py[i] += _noise2d(py[i] * 0.01, t * 0.4 + ph[i]) * drift * dt;
                else if (drift > 0) py[i] += _fsin(ph[i] + t * 0.4) * drift * dt;
            } else if (dir === "radial") {
                const f = 1 + accel * dt;
                vx[i] *= f; vy[i] *= f;
                px[i] += vx[i] * dt;
                py[i] += vy[i] * dt;
            } else { // float
                if (hasNoise && drift > 0) {
                    px[i] += _noise2d(px[i] * 0.008 + ph[i], t * 0.25) * drift * dt + _wx * wsc * 0.3 + gx * wsc;
                    py[i] += _noise2d(py[i] * 0.008 + ph[i] * 1.3 + 50, t * 0.2) * drift * dt * 0.6 + _wy * wsc * 0.3 + gy * wsc;
                } else {
                    px[i] += _fsin(ph[i] + t * 0.3) * drift * dt + _wx * wsc * 0.3 + gx * wsc;
                    py[i] += _fcos(ph[i] * 1.3 + t * 0.2) * drift * dt * 0.6 + _wy * wsc * 0.3 + gy * wsc;
                }
            }

            if (sp[i] !== 0) rt[i] += sp[i] * dt * (1 + gs * 2);

            // Brightness modifiers
            let tMul = 1.0;
            if (cfg.twinkle) {
                tMul = 0.35 + 0.65 * Math.abs(_fsin(ph[i] * 2 + t * (1.2 + d)));
                if (pix) tMul = Math.round(tMul * 3) / 3 + 0.05;
            }
            if (cfg.blink) {
                // Slow swell and fade, never fully out
                const b = 0.5 + 0.5 * _fsin(ph[i] * 0.5 + t * (0.6 + d * 0.5));
                tMul = 0.12 + 0.88 * b * b;
            }
            if (cfg.arcs && _tm[i] > tMul) tMul = Math.max(tMul, _tm[i] - dt * 3); // arc endpoints flare briefly
            _tm[i] = tMul;

            // Fade in, then out
            if (al[i] < mx[i] && ag[i] < 4) {
                al[i] += fadeInRate * dt * mx[i];
                if (al[i] > mx[i]) al[i] = mx[i];
            } else {
                al[i] -= fr[i] * dt;
            }

            // Rain hits its ground line
            if (splash && py[i] >= _gy[i]) {
                if (al[i] > 0.15 && _ripples.length < 24 && Math.random() < 0.6) _spawnRipple(px[i], _gy[i], 4 + d * 10);
                continue;
            }

            const m = sz[i] * 1.5 + 60; // big soft shapes are drawn wider than their size
            if (al[i] > 0.005 && px[i] > -m - 200 && px[i] < w + m && py[i] > -m - 60 && py[i] < h + m) {
                if (writeI !== i) {
                    px[writeI]=px[i]; py[writeI]=py[i]; vx[writeI]=vx[i]; vy[writeI]=vy[i];
                    sz[writeI]=sz[i]; al[writeI]=al[i]; mx[writeI]=mx[i]; fr[writeI]=fr[i];
                    dp[writeI]=dp[i]; ag[writeI]=ag[i]; ph[writeI]=ph[i]; sp[writeI]=sp[i];
                    rt[writeI]=rt[i]; _gy[writeI]=_gy[i]; _gw[writeI]=_gw[i]; _ci[writeI]=_ci[i];
                    _cr[writeI]=_cr[i]; _cg[writeI]=_cg[i]; _cb[writeI]=_cb[i];
                    _sh[writeI]=_sh[i]; _tm[writeI]=_tm[i];
                }
                writeI++;
            }
        }
        _count = writeI;

        // Refill (a few per frame; fast effects need more to keep up)
        const perFrame = cfg.fast ? 8 : 3;
        let spawned = 0;
        while (_count < _target && spawned < perFrame) { _spawnAt(_count, false); _count++; spawned++; }

        if (_fadeOut.length > 0) {
            k = 0;
            for (let i = 0; i < _fadeOut.length; i++) { const f = _fadeOut[i]; f.al -= f.fr * dt; if (f.al > 0.01) _fadeOut[k++] = f; }
            _fadeOut.length = k;
        }
    }

    // ═════════════════════════════════════════════════════════
    //  SHAPE DRAWING (fx = horizontal scale, for petals and leaves tumbling)
    // ═════════════════════════════════════════════════════════
    function _drawShape(ctx, shape, x, y, sz, rot, fx) {
        switch (shape) {
        case 1: // diamond
            ctx.save(); ctx.translate(x,y); ctx.rotate(rot); ctx.scale(fx, 1);
            ctx.beginPath(); ctx.moveTo(0,-sz); ctx.lineTo(sz*0.6,0); ctx.lineTo(0,sz); ctx.lineTo(-sz*0.6,0);
            ctx.closePath(); ctx.fill(); ctx.restore(); break;
        case 2: // petal: notched tip
            ctx.save(); ctx.translate(x,y); ctx.rotate(rot); ctx.scale(fx, 1);
            ctx.beginPath(); ctx.moveTo(0, sz*0.55);
            ctx.bezierCurveTo(sz*0.75, sz*0.2, sz*0.55, -sz*0.45, sz*0.14, -sz*0.55);
            ctx.lineTo(0, -sz*0.4); ctx.lineTo(-sz*0.14, -sz*0.55);
            ctx.bezierCurveTo(-sz*0.55, -sz*0.45, -sz*0.75, sz*0.2, 0, sz*0.55);
            ctx.closePath(); ctx.fill(); ctx.restore(); break;
        case 3: // hex
            ctx.save(); ctx.translate(x,y); ctx.rotate(rot);
            ctx.beginPath();
            for (let j = 0; j < 6; j++) {
                const a = j * 1.0472 - 0.5236;
                if (j===0) ctx.moveTo(Math.cos(a)*sz, Math.sin(a)*sz); else ctx.lineTo(Math.cos(a)*sz, Math.sin(a)*sz);
            }
            ctx.closePath(); ctx.fill(); ctx.restore(); break;
        case 4: // 5-point star
            ctx.save(); ctx.translate(x,y); ctx.rotate(rot);
            ctx.beginPath();
            for (let j = 0; j < 10; j++) {
                const a = j * 0.6283 - 1.5708, r = (j%2===0) ? sz : sz * 0.4;
                if (j===0) ctx.moveTo(Math.cos(a)*r, Math.sin(a)*r); else ctx.lineTo(Math.cos(a)*r, Math.sin(a)*r);
            }
            ctx.closePath(); ctx.fill(); ctx.restore(); break;
        case 5: // snowflake
            ctx.save(); ctx.translate(x,y); ctx.rotate(rot);
            ctx.lineWidth = Math.max(0.6, sz*0.12); ctx.strokeStyle = ctx.fillStyle; ctx.lineCap = "round";
            ctx.beginPath();
            for (let j = 0; j < 6; j++) {
                const a = j * 1.0472, ca = Math.cos(a), sa = Math.sin(a);
                ctx.moveTo(0,0); ctx.lineTo(ca*sz, sa*sz);
                const bx = ca*sz*0.55, by = sa*sz*0.55, bl = sz*0.32;
                ctx.moveTo(bx,by); ctx.lineTo(bx+Math.cos(a+0.6)*bl, by+Math.sin(a+0.6)*bl);
                ctx.moveTo(bx,by); ctx.lineTo(bx+Math.cos(a-0.6)*bl, by+Math.sin(a-0.6)*bl);
            }
            ctx.stroke(); ctx.restore(); break;
        case 6: // 4-point sparkle
            ctx.save(); ctx.translate(x,y); ctx.rotate(rot);
            ctx.beginPath();
            for (let j = 0; j < 8; j++) {
                const a = j * 0.7854 - 1.5708, r = (j%2===0) ? sz : sz*0.22;
                if (j===0) ctx.moveTo(Math.cos(a)*r, Math.sin(a)*r); else ctx.lineTo(Math.cos(a)*r, Math.sin(a)*r);
            }
            ctx.closePath(); ctx.fill(); ctx.restore(); break;
        case 7: // cross
            ctx.save(); ctx.translate(x,y); ctx.rotate(rot);
            ctx.fillRect(-sz, -sz*0.25, sz*2, sz*0.5); ctx.fillRect(-sz*0.25, -sz, sz*0.5, sz*2);
            ctx.restore(); break;
        case 8: { // bubble: thin rim, faint fill, highlight
            const oa = ctx.globalAlpha;
            ctx.globalAlpha = oa * 0.12;
            ctx.beginPath(); ctx.arc(x, y, sz, 0, 6.2832); ctx.fill();
            ctx.globalAlpha = oa;
            ctx.strokeStyle = ctx.fillStyle; ctx.lineWidth = Math.max(0.8, sz * 0.13);
            ctx.stroke();
            ctx.globalAlpha = oa * 0.85; ctx.fillStyle = "#ffffff";
            ctx.beginPath(); ctx.arc(x - sz*0.35, y - sz*0.35, Math.max(0.7, sz * 0.2), 0, 6.2832); ctx.fill();
            ctx.globalAlpha = oa;
            break;
        }
        case 10: // pixel
            ctx.fillRect(x - sz/2, y - sz/2, sz, sz); break;
        case 11: // leaf with midrib
            ctx.save(); ctx.translate(x,y); ctx.rotate(rot); ctx.scale(fx, 1);
            ctx.beginPath(); ctx.moveTo(0, -sz);
            ctx.quadraticCurveTo(sz*0.75, -sz*0.2, 0, sz*0.8);
            ctx.quadraticCurveTo(-sz*0.75, -sz*0.2, 0, -sz);
            ctx.closePath(); ctx.fill();
            ctx.globalAlpha *= 0.45; ctx.strokeStyle = "rgba(0,0,0,0.6)"; ctx.lineWidth = Math.max(0.5, sz*0.07);
            ctx.beginPath(); ctx.moveTo(0, -sz*0.85); ctx.lineTo(0, sz*1.05); ctx.stroke();
            ctx.restore(); break;
        default: // circle
            ctx.beginPath(); ctx.arc(x, y, sz, 0, 6.2832); ctx.fill(); break;
        }
    }

    function _strokePath(ctx, pts) {
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
        ctx.stroke();
    }

    // ═════════════════════════════════════════════════════════
    //  RENDER
    // ═════════════════════════════════════════════════════════
    // Blurry layer (fog, dust clouds, glow halos) at a third of the resolution, scaled up on the GPU.
    // Soft content looks the same and fills ~9x fewer pixels, which is most of the paint cost
    Canvas {
        id: _softCanvas
        readonly property real k: 3
        width: Math.ceil(parent.width / k); height: Math.ceil(parent.height / k)
        scale: k; transformOrigin: Item.TopLeft
        smooth: true
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!root._ready) return;
            const cfg = root._cfg;
            const cnt = root._count;
            const px = root._px, py = root._py, sz = root._sz, al = root._al, dp = root._dp;
            const cr = root._cr, cg = root._cg, cb = root._cb;
            const sh = root._sh, tm = root._tm, gw = root._gw;
            const snap = cfg.pixelSnap || 0;
            ctx.save();
            ctx.scale(1 / k, 1 / k);

            // Fog banks and dust clouds, squashed so they read as banks rather than balls
            ctx.globalCompositeOperation = "source-over";
            for (let i = 0; i < cnt; i++) {
                if (sh[i] !== root._sSoft) continue;
                const a = al[i] * tm[i];
                if (a < 0.005) continue;
                const r = sz[i];
                const c = "rgba(" + cr[i] + "," + cg[i] + "," + cb[i] + ",";
                const g = ctx.createRadialGradient(0, 0, 0, 0, 0, r);
                g.addColorStop(0, c + "1)");
                g.addColorStop(0.45, c + "0.5)");
                g.addColorStop(1, c + "0)");
                ctx.globalAlpha = Math.min(1, a * 2.5);
                ctx.fillStyle = g;
                ctx.save(); ctx.translate(px[i], py[i]); ctx.scale(1.5, 0.75);
                ctx.fillRect(-r, -r, r * 2, r * 2);
                ctx.restore();
            }

            // Glow halos under the particles
            {
                ctx.globalCompositeOperation = cfg.additive ? "lighter" : "screen";
                for (let i = 0; i < cnt; i++) {
                    if (gw[i] <= 0 || sh[i] === root._sSoft) continue;
                    const a = al[i] * tm[i] * (0.5 + dp[i] * 0.5);
                    if (a < 0.1) continue;
                    let x = px[i], y = py[i];
                    if (snap) { x = Math.round(x / snap) * snap; y = Math.round(y / snap) * snap; }
                    ctx.globalAlpha = Math.min(1, a * 0.95);
                    root._glow(ctx, x, y, sz[i] * gw[i] + 2, cr[i], cg[i], cb[i]);
                }
            }
            ctx.restore();
            ctx.globalAlpha = 1;
            ctx.globalCompositeOperation = "source-over";
        }
    }

    Canvas {
        id: _mainCanvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!root._ready) return;
            const cfg = root._cfg;
            const additive = !!cfg.additive;
            const baseOp = additive ? "lighter" : "source-over";
            ctx.globalCompositeOperation = baseOp;
            ctx.lineCap = "round"; ctx.lineJoin = "round";
            const cnt = root._count;
            const px = root._px, py = root._py, sz = root._sz, al = root._al;
            const vx = root._vx, vy = root._vy;
            const dp = root._dp, rt = root._rt, ph = root._ph, sp = root._sp;
            const cr = root._cr, cg = root._cg, cb = root._cb;
            const sh = root._sh, tm = root._tm, gw = root._gw;
            const pal = root._colors;
            const t = root._time;

            // ── Crossfade remnants ───────────────────────
            const fo = root._fadeOut;
            for (let i = 0; i < fo.length; i++) {
                const f = fo[i];
                ctx.globalAlpha = f.al;
                ctx.fillStyle = "rgb(" + f.r + "," + f.g + "," + f.b + ")";
                ctx.beginPath(); ctx.arc(f.x, f.y, f.sz, 0, 6.2832); ctx.fill();
            }

            // ── Lightning / arcs ─────────────────────────
            const bolts = root._bolts;
            for (let i = 0; i < bolts.length; i++) {
                const b = bolts[i];
                const ba = b.life / b.maxLife;
                const flick = ba * (0.7 + 0.3 * Math.random());
                const rc = pal[0] || { r: 200, g: 200, b: 255 };
                ctx.globalCompositeOperation = "lighter";
                ctx.globalAlpha = flick * 0.35; ctx.strokeStyle = root._rgb(rc); ctx.lineWidth = b.w * 3.5;
                root._strokePath(ctx, b.pts);
                ctx.globalAlpha = flick; ctx.strokeStyle = "#ffffff"; ctx.lineWidth = b.w * ba + 0.4;
                root._strokePath(ctx, b.pts);
                if (b.branch.length > 1) { ctx.globalAlpha = flick * 0.55; ctx.lineWidth = b.w * 0.5; root._strokePath(ctx, b.branch); }
                ctx.globalCompositeOperation = baseOp;
            }

            // ── Splashes (flattened, so they sit on a ground plane) ──
            const ripples = root._ripples;
            if (ripples.length > 0) {
                const rc = pal[0] || { r: 190, g: 205, b: 225 };
                ctx.strokeStyle = root._rgb(rc);
                for (let i = 0; i < ripples.length; i++) {
                    const r = ripples[i];
                    const life = r.life / r.maxLife;
                    ctx.globalAlpha = life * 0.5;
                    ctx.lineWidth = 0.6 + life * 0.8;
                    ctx.save(); ctx.translate(r.x, r.y); ctx.scale(1, 0.28);
                    ctx.beginPath(); ctx.arc(0, 0, Math.max(0.5, r.r), 0, 6.2832); ctx.stroke();
                    ctx.restore();
                }
            }

            // ── Drips ────────────────────────────────────
            const drips = root._drips;
            for (let i = 0; i < drips.length; i++) {
                const d = drips[i];
                ctx.globalAlpha = 0.75; ctx.strokeStyle = root._rgb(d.c); ctx.lineWidth = 1.6 * d.d;
                ctx.beginPath(); ctx.moveTo(d.x, d.y); ctx.lineTo(d.x, d.y - Math.min(22, d.vy * 0.03)); ctx.stroke();
            }

            // ── Shooting star ────────────────────────────
            const ss = root._shooting;
            if (ss) {
                const life = ss.life / ss.max;
                const fade = Math.min(1, life * 3) * Math.min(1, (1 - life) * 6);
                const tx = ss.x - Math.cos(ss.a) * ss.len, ty = ss.y - Math.sin(ss.a) * ss.len;
                const g = ctx.createLinearGradient(ss.x, ss.y, tx, ty);
                g.addColorStop(0, "rgba(255,255,255,1)");
                g.addColorStop(0.25, root._rgba(ss.c, 0.6));
                g.addColorStop(1, root._rgba(ss.c, 0));
                ctx.globalAlpha = fade; ctx.strokeStyle = g; ctx.lineWidth = 1.8;
                ctx.beginPath(); ctx.moveTo(ss.x, ss.y); ctx.lineTo(tx, ty); ctx.stroke();
                root._glow(ctx, ss.x, ss.y, 10, ss.c.r, ss.c.g, ss.c.b);
            }

            // ── Tracers / light trails ───────────────────
            const trs = root._tracers;
            if (trs.length > 0) {
                ctx.globalCompositeOperation = "lighter";
                for (let i = 0; i < trs.length; i++) {
                    const tr = trs[i];
                    const tx = tr.x - tr.dx * tr.len, ty = tr.y - tr.dy * tr.len;
                    const g = ctx.createLinearGradient(tr.x, tr.y, tx, ty);
                    g.addColorStop(0, root._rgba({ r: 255, g: 255, b: 255 }, 0.95));
                    g.addColorStop(0.15, root._rgba(tr.c, 0.8));
                    g.addColorStop(1, root._rgba(tr.c, 0));
                    ctx.globalAlpha = 0.9; ctx.strokeStyle = g; ctx.lineWidth = tr.w;
                    ctx.beginPath(); ctx.moveTo(tr.x, tr.y); ctx.lineTo(tx, ty); ctx.stroke();
                }
                ctx.globalCompositeOperation = baseOp;
            }

            // ── Connections (spatial grid); remembers the links for data packets ──
            if (cfg.connections) {
                const cD = cfg.connDist || 120, cDSq = cD * cD;
                ctx.lineWidth = 1;
                const cols = Math.ceil(width / cD) + 1, rows = Math.ceil(height / cD) + 1, need = cols * rows;
                if (!root._connGrid || root._connGrid.length < need) {
                    root._connGrid = new Array(need);
                    for (let gi = 0; gi < need; gi++) root._connGrid[gi] = [];
                }
                const grid = root._connGrid;
                for (let gi = 0; gi < need; gi++) grid[gi].length = 0;
                for (let i = 0; i < cnt; i++) {
                    if (al[i] < 0.05) continue;
                    const gc = Math.floor(px[i] / cD), gr = Math.floor(py[i] / cD);
                    if (gc >= 0 && gc < cols && gr >= 0 && gr < rows) grid[gr * cols + gc].push(i);
                }
                const links = [];
                let drawn = 0;
                for (let cy = 0; cy < rows && drawn < 100; cy++) {
                    for (let cx = 0; cx < cols && drawn < 100; cx++) {
                        const cell = grid[cy * cols + cx];
                        if (cell.length === 0) continue;
                        for (let ni = 0; ni < 5 && drawn < 100; ni++) {
                            // Self, right, down, down-right, down-left: every neighbouring pair once
                            let nx = cx, ny = cy;
                            if (ni === 1) nx++; else if (ni === 2) ny++; else if (ni === 3) { nx++; ny++; } else if (ni === 4) { nx--; ny++; }
                            if (nx < 0 || nx >= cols || ny >= rows) continue;
                            const nb = ni === 0 ? cell : grid[ny * cols + nx];
                            for (let ai = 0; ai < cell.length && drawn < 100; ai++) {
                                const p1 = cell[ai];
                                for (let bi = ni === 0 ? ai + 1 : 0; bi < nb.length && drawn < 100; bi++) {
                                    const p2 = nb[bi];
                                    const dx = px[p1] - px[p2], dy = py[p1] - py[p2], dSq = dx*dx + dy*dy;
                                    if (dSq >= cDSq) continue;
                                    const a = (1 - Math.sqrt(dSq) / cD) * Math.min(al[p1], al[p2]) * 0.75;
                                    if (a < 0.01) continue;
                                    ctx.globalAlpha = a;
                                    ctx.strokeStyle = "rgb(" + cr[p1] + "," + cg[p1] + "," + cb[p1] + ")";
                                    ctx.beginPath(); ctx.moveTo(px[p1], py[p1]); ctx.lineTo(px[p2], py[p2]); ctx.stroke();
                                    if (a > 0.08) links.push(px[p1], py[p1], px[p2], py[p2]);
                                    drawn++;
                                }
                            }
                        }
                    }
                }
                root._links = links;
            }

            // ── Data packets ─────────────────────────────
            const pk = root._packets;
            if (pk.length > 0) {
                ctx.globalCompositeOperation = "lighter";
                for (let i = 0; i < pk.length; i++) {
                    const p = pk[i];
                    const e = p.t < 0.5 ? 2 * p.t * p.t : 1 - 2 * (1 - p.t) * (1 - p.t);
                    const x = p.x1 + (p.x2 - p.x1) * e, y = p.y1 + (p.y2 - p.y1) * e;
                    const e0 = Math.max(0, e - 0.18);
                    const x0 = p.x1 + (p.x2 - p.x1) * e0, y0 = p.y1 + (p.y2 - p.y1) * e0;
                    const a = Math.sin(p.t * Math.PI);
                    ctx.globalAlpha = a * 0.8; ctx.strokeStyle = root._rgb(p.c); ctx.lineWidth = 1.6;
                    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x, y); ctx.stroke();
                    ctx.globalAlpha = a; ctx.fillStyle = "#ffffff";
                    ctx.beginPath(); ctx.arc(x, y, 1.6, 0, 6.2832); ctx.fill();
                    ctx.globalAlpha = a * 0.8; root._glow(ctx, x, y, 9, p.c.r, p.c.g, p.c.b);
                }
                ctx.globalCompositeOperation = baseOp;
            }

            // ── Particles ────────────────────────────────
            const streak = !!cfg.streak;
            const streakLen = (cfg.streakLen || 10) * root._sizeK, streakK = cfg.streakK || 0, streakMax = cfg.streakMax || 120;
            const flip = !!cfg.flip;
            const snap = cfg.pixelSnap || 0;
            const windAng = (root._wx + root._gx * root._gStr) * 0.004;
            for (let i = 0; i < cnt; i++) {
                const shape = sh[i];
                if (shape === root._sSoft) continue;
                const a = al[i] * tm[i] * (0.5 + dp[i] * 0.5);
                if (a < 0.01) continue;
                const s = sz[i];
                let x = px[i], y = py[i];
                if (snap) { x = Math.round(x / snap) * snap; y = Math.round(y / snap) * snap; }

                ctx.globalAlpha = a;
                const col = "rgb(" + cr[i] + "," + cg[i] + "," + cb[i] + ")";
                if (shape === 12) { // Bokeh: an out-of-focus light, even in the middle and soft at the edge (no outline)
                    const c = "rgba(" + cr[i] + "," + cg[i] + "," + cb[i] + ",";
                    const g = ctx.createRadialGradient(x, y, 0, x, y, s);
                    g.addColorStop(0, c + "0.42)");
                    g.addColorStop(0.55, c + "0.34)");
                    g.addColorStop(0.85, c + "0.14)");
                    g.addColorStop(1, c + "0)");
                    ctx.fillStyle = g;
                    ctx.fillRect(x - s, y - s, s * 2, s * 2);
                    continue;
                }
                ctx.fillStyle = col;
                if (streak) {
                    // Length follows speed (warp) or is fixed and leans with the wind (rain)
                    const spd = Math.sqrt(vx[i]*vx[i] + vy[i]*vy[i]);
                    if (spd < 0.01) continue;
                    const len = streakK > 0 ? Math.min(streakMax, spd * streakK + 1) : streakLen * (0.4 + dp[i] * 0.6);
                    let ang = Math.atan2(vy[i], vx[i]);
                    if (!streakK) ang -= windAng * dp[i];
                    ctx.strokeStyle = col;
                    ctx.lineWidth = Math.max(0.8, s * (streakK ? 0.9 : 0.7));
                    ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x - Math.cos(ang) * len, y - Math.sin(ang) * len); ctx.stroke();
                } else {
                    const fx = flip ? root._fcos(rt[i] * 1.3 + ph[i]) * 0.85 + (rt[i] >= 0 ? 0.15 : -0.15) : 1;
                    root._drawShape(ctx, shape, x, y, s, snap ? 0 : rt[i], fx);
                }
            }

            // ── Pops ─────────────────────────────────────
            const sbs = root._sparkBursts;
            if (sbs.length > 0) {
                ctx.globalCompositeOperation = "lighter";
                for (let i = 0; i < sbs.length; i++) {
                    const sb = sbs[i];
                    for (let j = 0; j < sb.sparks.length; j++) {
                        const s = sb.sparks[j];
                        if (s.al < 0.01) continue;
                        ctx.globalAlpha = s.al;
                        ctx.strokeStyle = "rgb(" + s.r + "," + s.g + "," + s.b + ")";
                        ctx.lineWidth = s.sz;
                        ctx.beginPath(); ctx.moveTo(s.x, s.y); ctx.lineTo(s.x - s.vx * 0.04, s.y - s.vy * 0.04); ctx.stroke();
                    }
                }
                ctx.globalCompositeOperation = baseOp;
            }

            // ── Lightning flash ──────────────────────────
            if (root._flashAlpha > 0.003) {
                ctx.globalCompositeOperation = "source-over";
                ctx.globalAlpha = root._flashAlpha;
                ctx.fillStyle = "#dfe8ff";
                ctx.fillRect(0, 0, width, height);
            }

            ctx.globalAlpha = 1;
            ctx.globalCompositeOperation = "source-over";
        }
    }
}
