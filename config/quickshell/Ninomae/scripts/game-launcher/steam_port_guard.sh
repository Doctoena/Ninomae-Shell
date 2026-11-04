#!/usr/bin/env bash
# Lets only your desktop session reach Steam's debugging port (localhost:8080, open while Settings →
# Games → "Pause and resume from the launcher" is on), so Flatpak apps and other sandboxed programs can't
# drive Steam through it.
#
#   sudo steam_port_guard.sh install     the firewall rule, applied now and at every login
#   sudo steam_port_guard.sh remove      takes it away
#   steam_port_guard.sh status           on, off, or uwsm (the guard can't work there, see below)
#
# How: Hyprland starts the shell, its helpers and Steam in your login session (session-N.scope). Flatpak
# apps, and anything started through systemd, run under user@UID.service instead. An nftables rule refuses
# connections to port 8080 on localhost from there. That group only exists while you're logged in, and the
# rule can only name it once it exists, so a small system service loads the rule at each login (it's tied
# to user@UID.service). A dev server of your own on port 8080 would be refused from those apps too.
set -euo pipefail

uid="${SUDO_UID:-$(id -u)}"
port=8080
table="ninomae_steam_port"
rules="/etc/ninomae/steam-port-guard.nft.in" # USERID is filled in by the service
unit="ninomae-steam-port-guard@.service"
instance="ninomae-steam-port-guard@${uid}.service"

# Under uwsm the desktop itself runs inside user@UID.service, so the rule would shut out the shell too
under_uwsm() {
    local pid
    for pid in $(pgrep -u "$uid" -x Hyprland); do
        grep -q "/user@$uid\.service/" "/proc/$pid/cgroup" 2>/dev/null && return 0
    done
    return 1
}

case "${1:-status}" in
install)
    [[ $EUID -eq 0 ]] || { echo "Run it with sudo: sudo $0 install"; exit 1; }
    [[ "$uid" -ne 0 ]] || { echo "Run it with sudo from your own account (not as root), so it knows whose session to guard"; exit 1; }
    if under_uwsm; then
        echo "Not installed: your desktop runs as a systemd service (uwsm), so the rule would block the shell as well"
        exit 1
    fi
    mkdir -p /etc/ninomae
    # destroy first, in the same load: the old rule is swapped for the new one at once (and it's no error if
    # there isn't one)
    cat > "$rules" <<NFT
destroy table inet $table
table inet $table {
    chain output {
        type filter hook output priority filter; policy accept;
        # Steam's debugging port, from programs outside the desktop session (Flatpaks, systemd-started apps)
        ip daddr 127.0.0.1 tcp dport $port socket cgroupv2 level 3 "user.slice/user-USERID.slice/user@USERID.service" reject with tcp reset
        ip6 daddr ::1 tcp dport $port socket cgroupv2 level 3 "user.slice/user-USERID.slice/user@USERID.service" reject with tcp reset
    }
}
NFT
    cat > "/etc/systemd/system/$unit" <<UNIT
[Unit]
Description=Ninomae: only the desktop session of user %i reaches Steam's debugging port
# The user manager's group has to exist before the rule can name it, and the rule goes with it at logout
After=user@%i.service
BindsTo=user@%i.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'sed "s/USERID/%i/g" $rules | /usr/sbin/nft -f -'
ExecStop=/usr/sbin/nft destroy table inet $table

[Install]
WantedBy=user@%i.service
UNIT
    systemctl daemon-reload
    systemctl enable "$instance"
    systemctl restart "$instance" # Loads the rule now, and a reinstall's new one over the old
    echo "On: only your desktop session can reach Steam's debugging port (applied again at every login)"
    ;;
remove)
    [[ $EUID -eq 0 ]] || { echo "Run it with sudo: sudo $0 remove"; exit 1; }
    systemctl disable --now "$instance" 2>/dev/null || true
    rm -f "/etc/systemd/system/$unit" "$rules"
    rmdir /etc/ninomae 2>/dev/null || true
    systemctl daemon-reload
    nft destroy table inet "$table"
    echo "Off: any program on this PC can reach Steam's debugging port again while it's open"
    ;;
status)
    if systemctl is-active --quiet "$instance" 2>/dev/null; then echo on
    elif under_uwsm; then echo uwsm
    else echo off; fi
    ;;
*)
    sed -n '2,8p' "$0"; exit 1 ;;
esac
