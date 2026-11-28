.pragma library
// The launcher's particle effects: each preset's settings, and which one Auto picks for a game. Used by
// GameParticles.qml (which moves and draws them, or hands them to Ninomae.Particles) and CustomizePanel.qml.
// shapeSize / shapeAlpha / shapeGlow override the defaults per shape (shape numbers: GameParticles.qml);
// tint + tintAmt pull the art's colours toward a theme colour.

var presets = {

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

    // Dust hanging in a failing light that stutters now and then, a little fog low down (flicker: with the plugin)
    "horror": {
        n: 40, szMin: 1, szMax: 2.6, spdMin: 2, spdMax: 7,
        dir: "float", fadeIn: 0.5, fadeOut: 0.02, aMin: 0.35, aMax: 0.8,
        glow: 1.6, drift: 10, noise: true,
        shapes: [0, 0, 0, 9], shapeSize: { 9: [90, 170] }, shapeAlpha: { 9: [0.04, 0.09] }, shapeGlow: { 9: 0 },
        flicker: 5,
        tint: "#cfc8bc", tintAmt: 0.7
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
};

// Old preset names still saved as per-game overrides ("energy" became the sci-fi "arcs")
var aliases = { "energy": "arcs", "voidStorm": "arcs", "synthwave": "neon", "parasitic": "ash", "pixelDust": "pixel" };
function resolve(key) { return aliases[key] || key; }

// Name rules: the first that matches wins, so specific titles go first
var rules = [
    // Snowy worlds (before the generic Elder Scrolls → magic rule)
    [/skyrim|valheim|frostpunk|the\s*long\s*dark|never\s*alone|far\s*cry\s*4|northgard|icarus|below\s*zero|horizon\s*(zero|forbidden)|lost\s*planet|project\s*winter|whiteout/, "snow"],
    // Underwater
    [/subnautica|abzu|dave\s*the\s*diver|bioshock|\bsoma\b|barotrauma|beyond\s*blue|in\s*other\s*waters|maneater|depth/, "bubbles"],
    // Horror and survival in the murk: dust in a failing light
    [/silent\s*hill|phasmophobia|dayz|lethal\s*company|devour|outlast|amnesia|layers\s*of\s*fear|visage|alan\s*wake|sons\s*of\s*the\s*forest|the\s*forest|dead\s*by\s*daylight|until\s*dawn|resident\s*evil|evil\s*within|alien\s*isolation|darkwood|madison|fatal\s*frame|content\s*warning|the\s*medium|little\s*nightmares|^limbo|^inside$|s\.?t\.?a\.?l\.?k\.?e\.?r|metro\s*(2033|last|exodus)|\bscum\b|just\s*survive|cry\s*of\s*fear|f\.e\.a\.r|condemned|observer|distraint/, "horror"],
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
];

// Steam's store tags (their ids) → an effect, for games no name rule knows. A game's tags come most voted first
// (steam_store_tags.py), and its first one here picks. Kept to tags that say what a game looks like
var tagRules = {
    4115: "neon", 699: "neon", 1752: "neon", // Cyberpunk, Racing, Rhythm
    16598: "warp", // Space Sim
    1755: "stars", // Space
    3942: "arcs", 4821: "arcs", // Sci-fi, Mechs
    5752: "circuit", 255534: "circuit", 5432: "circuit", 5502: "circuit", // Robots, Automation, Programming, Hacking
    3835: "wasteland", // Post-apocalyptic
    1659: "ash", // Zombies
    1667: "horror", 1721: "horror", 3978: "horror", 7432: "horror", // Horror, Psychological Horror, Survival Horror, Lovecraftian
    5716: "fog", 4342: "fog", // Mystery, Dark
    4604: "embers", 29482: "embers", 1646: "embers", 9541: "embers", 4172: "embers", // Dark Fantasy, Souls-like, Hack and Slash, Demons, Medieval
    1684: "magic", 4057: "magic", 16094: "magic", 1718: "magic", 620519: "magic", // Fantasy, Magic, Mythology, MOBA, Hero Shooter
    4168: "tracers", 1678: "tracers", 1663: "tracers", // Military, War, FPS
    3964: "pixel", 1732: "pixel", 4004: "pixel", // Pixel Graphics, Voxel, Retro
    9157: "bubbles", // Underwater
    9803: "snow", // Snow
    30358: "leaves", 87918: "leaves", 22602: "leaves", // Nature, Farming Sim, Agriculture
    97376: "fireflies", 4726: "fireflies", 1654: "fireflies", // Cozy, Cute, Relaxing
    4085: "sakura", // Anime
    5981: "cavern", 21006: "cavern", 1720: "cavern", // Mining, Underground, Dungeon Crawler
};

// What Auto picks: a name rule, else the game's first Steam tag that has an effect, else Ambient
function pick(name, tags) {
    const n = (name || "").toLowerCase();
    for (let i = 0; n && i < rules.length; i++) {
        if (rules[i][0].test(n)) return rules[i][1];
    }
    for (const tag of tags || []) {
        if (tagRules[tag]) return tagRules[tag];
    }
    return "ambient";
}
