const MILLENNIUM_IS_CLIENT_MODULE=!0,pluginName="ninomae";function InitializePlugins(){var e,n;let t;(e=window.PLUGIN_LIST||(window.PLUGIN_LIST={})).ninomae||(e.ninomae={}),(n=window.MILLENNIUM_PLUGIN_SETTINGS_STORE||(window.MILLENNIUM_PLUGIN_SETTINGS_STORE={})).ninomae||(n.ninomae={}),window.MILLENNIUM_SIDEBAR_NAVIGATION_PANELS||(window.MILLENNIUM_SIDEBAR_NAVIGATION_PANELS={}),function(e){e[e.CallServerMethod=0]="CallServerMethod"}(t||(t={}));let o=window.MILLENNIUM_PLUGIN_SETTINGS_STORE.ninomae,r="Millennium.Internal.IPC.[ninomae]";const i={DropDown:["string","number","boolean"],NumberTextInput:["number"],StringTextInput:["string"],FloatTextInput:["number"],CheckBox:["boolean"],NumberSlider:["number"],FloatSlider:["number"]};function a(e,n,o){return MILLENNIUM_BACKEND_IPC.postMessage(t.CallServerMethod,{pluginName:e,methodName:"__builtins__.__update_settings_value__",argumentList:{name:n,value:o}})}o.ignoreProxyFlag=!1,async function(){for(;"undefined"==typeof MainWindowBrowserManager;)await new Promise(e=>setTimeout(e,0));MainWindowBrowserManager?.m_browser?.on("message",(e,n)=>{if(e!==r)return;const{name:t,value:i}=JSON.parse(n);o.ignoreProxyFlag=!0,o.settingsStore[t]=i,a("ninomae",t,i),o.ignoreProxyFlag=!1})}();const l=e=>new Proxy(e,{set(e,n,t){if(!(n in e))throw new TypeError(`Property ${String(n)} does not exist on plugin settings`);const l=i[e[n].type],_=e[n]?.range;if(l.includes("number")&&"number"==typeof t&&(_&&(t=function(e,n,t){return Math.max(n,Math.min(t,e))}(t,_[0],_[1])),t||(t=0)),!l.includes(typeof t))throw new TypeError(`Expected ${l.join(" or ")}, got ${typeof t}`);return e[n].value=t,((e,n)=>{o.ignoreProxyFlag||(a("ninomae",e,n),"undefined"!=typeof MainWindowBrowserManager&&MainWindowBrowserManager?.m_browser?.PostMessage(r,JSON.stringify({name:e,value:n})))})(String(n),t),!0},get:(e,n)=>"__raw_get_internals__"===n?e:n in e?e[n].value:void 0});o.DefinePluginSetting=l,o.settingsStore=l({})}InitializePlugins();const __call_server_method__=(e,n)=>Millennium.callServerMethod("ninomae",e,n);function __wrapped_callable__(e){return e.startsWith("webkit:")?MILLENNIUM_API.callable((e,n)=>MILLENNIUM_API.__INTERNAL_CALL_WEBKIT_METHOD__("ninomae",e,n),e.replace(/^webkit:/,"")):MILLENNIUM_API.callable(__call_server_method__,e)}let PluginEntryPointMain = function () { return function (exports, api) { "use strict";
// ── Ninomae: the launcher's commands, run in Steam's main page ─────────────────────────────────────────
// Everything above and below this part is Millennium's loader (as its build tool writes it). Requests come
// from the shell's mailbox (backend/main.lua, scripts/game-launcher/steam_control.py). Only the commands
// below run, with their arguments checked, through the same SteamClient calls as Steam's own buttons.
const poll = __wrapped_callable__("poll"), reply = __wrapped_callable__("reply");
const LOCAL = "0"; // Steam's id for this PC (its Downloads page can also show another PC's)
const appid = a => { const id = Number(a.appid); if (!Number.isInteger(id) || id <= 0) throw new Error("bad appid"); return id; };
const text = v => { if (typeof v !== "string") throw new Error("bad text"); return v; };
// A game's launch options, Proton choice ("" for Steam's default: priority 250 is one picked for the
// game) and update mode, as Steam has them now
const details = id => new Promise(res => {
    let done = false;
    const h = SteamClient.Apps.RegisterForAppDetails(id, d => {
        if (done) return;
        done = true;
        setTimeout(() => h?.unregister?.(), 0); // Not from inside its own callback
        res({ options: d.strLaunchOptions ?? "", proton: d.nCompatToolPriority >= 250 ? d.strCompatToolName : "", autoUpdate: d.eAutoUpdateValue });
    });
    setTimeout(() => { if (!done) { done = true; h?.unregister?.(); res(null); } }, 2000);
});
const D = () => SteamClient.Downloads;
const commands = {
    ping: async () => true,
    // Steam's "Move to top": starts it now, the rest after it (also the retry after an error)
    resume: async a => { await D().ResumeAppUpdate(appid(a), LOCAL); return true; },
    // Steam's ✕, and for the paused one at the queue's head, the rest going again
    remove: async a => { await D().RemoveFromDownloadList(appid(a), LOCAL); if (a.resumeAll) await D().EnableAllDownloads(true, LOCAL); return true; },
    // The whole queue: the pause button on the one downloading
    enableAll: async a => { await D().EnableAllDownloads(!!a.on, LOCAL); return true; },
    details: async a => details(appid(a)),
    setApp: async a => {
        const id = appid(a), apps = SteamClient.Apps;
        apps.SetAppLaunchOptions(id, text(a.options));
        apps.SpecifyCompatTool(id, text(a.proton));
        if ([0, 1, 2].includes(a.autoUpdate)) apps.SetAppAutoUpdateBehavior(id, a.autoUpdate);
        return true;
    },
    // Steam's Uninstall after you confirm (the true): no dialog
    uninstall: async a => { await SteamClient.Installs.OpenUninstallWizard([appid(a)], LOCAL, true); return true; },
};
async function run(body) {
    try {
        const req = JSON.parse(body);
        if (!Object.hasOwn(commands, req?.cmd)) throw new Error("unknown command");
        return { ok: true, value: await commands[req.cmd](req.args ?? {}) };
    } catch (err) {
        return { ok: false, error: String(err?.message ?? err) };
    }
}
// Checks one after another (a slow command, details waits up to 2 s, holds the next): quickly while the
// launcher is open (the backend says so), else every 2 s, which is enough to notice it opening
async function check() {
    let fast = false;
    try {
        const r = JSON.parse(await poll() || "{}");
        fast = r.fast === true;
        for (const q of r.requests ?? [])
            await reply({ a_id: q.id, b_result: JSON.stringify(await run(q.body)) });
    } catch (err) {
        console.warn("[Ninomae]", err);
    }
    setTimeout(check, fast ? 150 : 2000);
}
check();
// Steam's own screenshot key (Settings → In game → Screenshot shortcut) set to "Not bound" each time Steam starts,
// as its Clear button does: F12 is the shell's in every game (services/GameClips.qml), so Steam saving one too
// would make two. It's screenshot_key, field 4003 of Steam's settings message: a hotkey of key code 0, no
// modifiers, written out by hand as Steam's settings page encodes it
(function unbindScreenshotKey() {
    const name = [...new TextEncoder().encode("Not bound")];
    const key = [0x08, 0, 0x10, 0, 0x18, 0, 0x20, 0, 0x28, 0, 0x32, name.length, ...name];
    const bytes = [0x9a, 0xfa, 0x01, key.length, ...key];
    try {
        Promise.resolve(SteamClient.Settings.SetSetting(btoa(String.fromCharCode(...bytes))))
            .catch(err => console.warn("[Ninomae] screenshot key", err));
    } catch (err) {
        console.warn("[Ninomae] screenshot key", err);
    }
})();
// Millennium's plugin list shows this page
const Page = () => window.SP_REACT.createElement(api.Field, { label: "Ninomae launcher", description: "Lets the Ninomae launcher pause, resume and order downloads, and save launch options and Proton without restarting Steam. Turns off Steam's screenshot key: F12 is the shell's. Nothing to set here.", icon: window.SP_REACT.createElement(api.IconsModule.Settings, null), bottomSeparator: "none", focusable: false });
exports.default = api.definePlugin(() => ({ title: "Ninomae Shell", icon: window.SP_REACT.createElement(api.IconsModule.Settings, null), content: window.SP_REACT.createElement(Page, null) }));
Object.defineProperty(exports, "__esModule", { value: true });
return exports;
// ───────────────────────────────────────────────────────────────────────────────────────────────────────
}({}, window.MILLENNIUM_API); };
function ExecutePluginModule(){let e=window.MILLENNIUM_PLUGIN_SETTINGS_STORE.ninomae;e.OnPluginConfigChange=function(n,t,o){n in e.settingsStore&&(e.ignoreProxyFlag=!0,e.settingsStore[n]=o,e.ignoreProxyFlag=!1)},MILLENNIUM_BACKEND_IPC.postMessage(0,{pluginName:"ninomae",methodName:"__builtins__.__millennium_plugin_settings_parser__"}).then(async n=>{"string"==typeof n.returnValue&&(e.ignoreProxyFlag=!0,e.settingsStore=e.DefinePluginSetting(Object.fromEntries(JSON.parse(atob(n.returnValue)).map(e=>[e.functionName,e]))),e.ignoreProxyFlag=!1);let t=PluginEntryPointMain();Object.assign(window.PLUGIN_LIST.ninomae,{...t,__millennium_internal_plugin_name_do_not_use_or_change__:"ninomae"});let o=await t.default();var r;o&&(r=o)&&void 0!==r.title&&void 0!==r.icon&&void 0!==r.content?(window.MILLENNIUM_SIDEBAR_NAVIGATION_PANELS.ninomae=o,MILLENNIUM_BACKEND_IPC.postMessage(1,{pluginName:"ninomae"})):console.warn("Plugin ninomae does not contain proper SidebarNavigation props and therefor can't be mounted by Millennium. Please ensure it has a title, icon, and content.")})}ExecutePluginModule();