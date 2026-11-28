
/**
 * A Material symbol for a notification without an icon, so they don't all look alike: from the app's
 * name first (the shell's own notifications and command-line tools rarely send an icon), then words in
 * the title, then in the text. "chat" when nothing matches.
 * @param { string } summary
 * @param { string } appName
 * @param { string } body
 * @returns { string }
 */
function findSuitableMaterialSymbol(summary = "", appName = "", body = "") {
    const defaultType = 'chat';

    // App names (lower case, matched as a whole or at the start)
    const apps = {
        'clips': 'movie',
        'immich': 'cloud_upload',
        'battery': 'battery_alert',
        'power': 'power',
        'networkmanager': 'wifi',
        'network': 'wifi',
        'bluetooth': 'bluetooth',
        'blueman': 'bluetooth',
        'steam': 'sports_esports',
        'game launcher': 'sports_esports',
        'screenshot': 'screenshot_monitor',
        'screen snip': 'screenshot_monitor',
        'color picker': 'colorize',
        'hyprpicker': 'colorize',
        'wallpaper': 'wallpaper',
        'volume': 'volume_up',
        'audio': 'volume_up',
        'brightness': 'brightness_6',
        'night light': 'nightlight',
        'clipboard': 'content_paste',
        'dnf': 'deployed_code_update',
        'packagekit': 'deployed_code_update',
        'flatpak': 'deployed_code_update',
        'updates': 'update',
        'keyring': 'key',
        'polkit': 'admin_panel_settings',
        'timer': 'timer',
        'weather': 'partly_cloudy_day',
        'notify-send': 'notifications',
    };
    const app = appName.toLowerCase().trim();
    for (const [name, type] of Object.entries(apps)) {
        if (app === name || app.startsWith(name + ' ')) return type;
    }

    // Words in the title, then the text (first match wins, so specific ones go first). A keyword matches at
    // the start of a word ("upload" in "Uploaded", not "clip" in "eclipse"); "word:" ones only as a whole word
    const keywordsToTypes = {
        'reboot': 'restart_alt',
        'restart': 'restart_alt',
        'clipboard': 'content_paste',
        'clip': 'movie',
        'record': 'screen_record',
        'battery': 'battery_alert',
        'charging': 'battery_charging_full',
        'plugged': 'power',
        'power': 'power',
        'screenshot': 'screenshot_monitor',
        'upload': 'cloud_upload',
        'backed up': 'cloud_done',
        'download': 'download',
        'copied': 'content_copy',
        'saved': 'save',
        'deleted': 'delete',
        'trash': 'delete',
        'connected': 'wifi',
        'disconnected': 'wifi_off',
        'wi-fi': 'wifi',
        'bluetooth': 'bluetooth',
        'welcome': 'waving_hand',
        'reminder': 'alarm',
        'word:time': 'schedule',
        'installed': 'download',
        'configuration reloaded': 'reset_wrench',
        'failed': 'error',
        'error': 'error',
        'unable': 'error',
        "couldn't": 'error',
        'config': 'reset_wrench',
        'available': 'update',
        'update': 'update',
        'ai response': 'neurology',
        'control': 'settings',
        'upsca': 'compare',
        'playing': 'music_note',
        'music': 'queue_music',
        'install': 'deployed_code_update',
        'input': 'keyboard_alt',
        'preedit': 'keyboard_alt',
        'message': 'mail',
        'mention': 'alternate_email',
        'startswith:file': 'folder_copy', // Declarative startsWith check
    };
    const escape = w => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const find = text => {
        const lower = text.toLowerCase();
        if (lower.length === 0) return '';
        for (const [keyword, type] of Object.entries(keywordsToTypes)) {
            if (keyword.startsWith('startswith:')) {
                if (lower.startsWith(keyword.substring(11))) return type;
                continue;
            }
            const whole = keyword.startsWith('word:');
            const word = escape(whole ? keyword.substring(5) : keyword);
            if (new RegExp(`(^|[^a-z0-9])${word}${whole ? '($|[^a-z0-9])' : ''}`).test(lower)) return type;
        }
        return '';
    };
    return find(summary) || find(body) || defaultType;
}

/**
 * @param { number | string | Date } timestamp 
 * @returns { string }
 */
const getFriendlyNotifTimeString = (timestamp) => {
    if (!timestamp) return '';
    const messageTime = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - messageTime.getTime();

    // Less than 1 minute
    if (diffMs < 60000) 
        return 'Now';
    
    // Same day - show relative time
    if (messageTime.toDateString() === now.toDateString()) {
        const diffMinutes = Math.floor(diffMs / 60000);
        const diffHours = Math.floor(diffMs / 3600000);
        
        if (diffHours > 0) {
            return `${diffHours}h`;
        } else {
            return `${diffMinutes}m`;
        }
    }
    
    // Yesterday
    if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString()) 
        return 'Yesterday';
    
    // Older dates
    return Qt.formatDateTime(messageTime, "MMMM dd");
};