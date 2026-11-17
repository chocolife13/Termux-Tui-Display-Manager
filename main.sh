#!/data/data/com.termux/files/usr/bin/sh
# ============================================================
# Termux TUI Display Manager (POSIX sh)
# ------------------------------------------------------------
# - Scanne les sessions X11 (native, proot-distro, chroot-distro)
# - Menu TUI fléché
# - Pour les sessions chroot : écran de connexion SDDM-like
#   (utilisateur + mot de passe) AVANT de basculer Termux:X11
# ============================================================

# ---------- Palette ANSI ----------
ESC=$(printf '\033')
C_RESET="${ESC}[0m"
C_DIM="${ESC}[2m"
C_BOLD="${ESC}[1m"
C_BG_SEL="${ESC}[48;5;236m"
C_ACCENT="${ESC}[38;5;39m"
C_ACCENT2="${ESC}[38;5;213m"
C_TITLE="${ESC}[38;5;45m"
C_OK="${ESC}[38;5;46m"
C_WARN="${ESC}[38;5;220m"
C_GREY="${ESC}[38;5;245m"
C_ARROW="${ESC}[38;5;207m"
C_RED="${ESC}[1;38;5;196m"
TAB=$(printf '\t')
NL=$(printf '\n')

SESS_FILE="${TMPDIR:-/tmp}/tdm-sessions.$$"
: > "$SESS_FILE"

trap 'stty sane 2>/dev/null; clear; rm -f "$SESS_FILE"; exit 0' INT TERM

# ---------- 1. Clean anciennes sessions Termux:X11 ----------
_pids=$(ps -ef 2>/dev/null | awk '/[t]ermux\.x11/ {print $2}')
[ -n "$_pids" ] && kill -9 $_pids 2>/dev/null

# ---------- 2. PulseAudio ----------
_pa_pid=$(ps -ef 2>/dev/null | awk '/[p]ulseaudio/ {print $2; exit}')
if [ -z "$_pa_pid" ]; then
    pulseaudio --start \
        --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
        --exit-idle-time=-1
fi

# ---------- 3. Scan des sessions ----------
scan_xsessions() {
    _dir="$1"; _src="$2"
    [ -d "$_dir" ] || return 0
    for _desktop in "$_dir"/*.desktop; do
        [ -f "$_desktop" ] || continue
        grep -q '^NoDisplay=true' "$_desktop" && continue
        grep -q '^Hidden=true'    "$_desktop" && continue
        _name=$(awk -F= '/^Name=/    {sub(/^Name=/,"");    print; exit}' "$_desktop")
        _exec=$(awk -F= '/^Exec=/    {sub(/^Exec=/,"");    print; exit}' "$_desktop")
        _try=$(awk  -F= '/^TryExec=/ {sub(/^TryExec=/,""); print; exit}' "$_desktop")
        [ -z "$_name" ] && continue
        [ -z "$_exec" ] && continue
        if [ "$_src" = "native" ] && [ -n "$_try" ]; then
            command -v "$_try" >/dev/null 2>&1 || continue
        fi
        printf '%s\t%s\t%s\n' "$_name" "$_src" "$_exec" >> "$SESS_FILE"
    done
}

scan_xsessions "${PREFIX}/share/xsessions" "native"

for _pd_root in \
    "${PREFIX}/var/lib/proot-distro/installed-rootfs" \
    "${PREFIX}/var/lib/proot-distro/containers"
do
    [ -d "$_pd_root" ] || continue
    for _croot in "$_pd_root"/*/ ; do
        [ -d "$_croot" ] || continue
        _cname=$(basename "$_croot")
        if [ -d "${_croot}rootfs" ]; then
            scan_xsessions "${_croot}rootfs/usr/share/xsessions" "proot:${_cname}"
        else
            scan_xsessions "${_croot}usr/share/xsessions" "proot:${_cname}"
        fi
    done
done

_CD_ROOT="/data/local/chroot-distro"
_CHROOT_SCAN="${TMPDIR:-/tmp}/tdm-chroot-scan.$$.sh"
cat > "$_CHROOT_SCAN" <<'EOF'
CD=/data/local/chroot-distro
[ -d "$CD" ] || exit 0
for d in "$CD"/*/ ; do
    n=$(basename "$d")
    case "$n" in .*) continue ;; esac
    [ -d "$d/usr/share/xsessions" ] || continue
    for f in "$d/usr/share/xsessions"/*.desktop ; do
        [ -f "$f" ] || continue
        grep -q '^NoDisplay=true' "$f" && continue
        grep -q '^Hidden=true'    "$f" && continue
        name=$(awk -F= '/^Name=/ {sub(/^Name=/,""); print; exit}' "$f")
        exec=$(awk -F= '/^Exec=/ {sub(/^Exec=/,""); print; exit}' "$f")
        [ -z "$name" ] && continue
        [ -z "$exec" ] && continue
        printf '%s\t%s\t%s\n' "$name" "chroot:$n" "$exec"
    done
done
EOF
chmod 700 "$_CHROOT_SCAN" 2>/dev/null

if command -v su >/dev/null 2>&1; then
    su -c "sh $_CHROOT_SCAN" 2>/dev/null >> "$SESS_FILE"
fi
rm -f "$_CHROOT_SCAN"

# ---------- 4. Garde-fou ----------
N=$(wc -l < "$SESS_FILE" | tr -d ' ')
if [ "$N" -eq 0 ]; then
    clear
    printf '%s⚠ Aucune session trouvée.%s\n' "$C_WARN" "$C_RESET"
    exit 1
fi

# ---------- 5. Menu TUI ----------
truncate_name() {
    _n="$1"; _max="$2"
    if [ "${#_n}" -gt "$_max" ]; then
        _n=$(printf '%s' "$_n" | cut -c1-$(( _max - 2 )))
        _n="${_n}.."
    fi
    printf '%s' "$_n"
}

draw_menu() {
    _W=$(tput cols  2>/dev/null || echo 80)
    _H=$(tput lines 2>/dev/null || echo 24)
    _avail=$(( _W - 4 ))
    [ "$_avail" -lt 20 ] && _avail=20

    clear

    if [ "$_H" -ge $(( N + 8 )) ] && [ "$_W" -ge 40 ]; then
        printf '\n  %s%s╔═ Termux Display Manager ═╗%s\n\n' \
            "$C_TITLE" "$C_BOLD" "$C_RESET"
    else
        printf '%s%sTermux DM%s %s(%d sessions)%s\n\n' \
            "$C_TITLE" "$C_BOLD" "$C_RESET" "$C_GREY" "$N" "$C_RESET"
    fi

    _i=0
    while IFS="$TAB" read -r _name _src _cmd <&3; do
        case "$_src" in
            native)   _tag="native";              _tagcol="$C_OK"      ;;
            proot:*)  _tag="${_src#proot:}";      _tagcol="$C_ACCENT2" ;;
            chroot:*) _tag="${_src#chroot:}";     _tagcol="$C_ACCENT"  ;;
            *)        _tag="$_src";               _tagcol="$C_GREY"    ;;
        esac

        _tag_len=$(( ${#_tag} + 2 ))
        _fixed=$(( 4 + _tag_len + 2 ))
        _name_max=$(( _avail - _fixed ))
        [ "$_name_max" -lt 4 ] && _name_max=4
        _name=$(truncate_name "$_name" "$_name_max")

        _pad=$(( _avail - ${#_name} - _tag_len - 4 ))
        [ "$_pad" -lt 1 ] && _pad=1
        _spaces=$(printf "%${_pad}s" "")

        if [ "$_i" -eq "$sel" ]; then
            printf '  %s%s▶%s %s%s %s%s%s%s%s%s%s%s %s\n' \
                "$C_ARROW" "$C_BOLD" "$C_RESET" \
                "$C_BG_SEL" "$C_BOLD" "$_name" "$C_RESET" \
                "$C_BG_SEL" "$_spaces" "$_tagcol" "[$_tag]" "$C_RESET" \
                "$C_BG_SEL" "$C_RESET"
        else
            printf '  %s %s %s%s%s%s%s%s%s%s\n' \
                "$C_GREY" "$C_RESET" "$C_BOLD" "$_name" "$C_RESET" \
                "$C_GREY" "$_spaces" "$_tagcol" "[$_tag]" "$C_RESET"
        fi
        _i=$(( _i + 1 ))
    done 3< "$SESS_FILE"

    _sep_len=$(( _avail < 40 ? _avail : 40 ))
    [ "$_sep_len" -lt 10 ] && _sep_len=10
    _sep=$(printf "%${_sep_len}s" "" | tr ' ' '─')

    printf '\n  %s%s%s\n' "$C_GREY" "$_sep" "$C_RESET"

    if [ "$_avail" -ge 44 ]; then
        printf '  %s↑↓%s %snaviguer%s   %s→%s %slancer%s   %s←%s %squitter%s\n' \
            "$C_OK" "$C_RESET" "$C_GREY" "$C_RESET" \
            "$C_OK" "$C_RESET" "$C_GREY" "$C_RESET" \
            "$C_RED" "$C_RESET" "$C_GREY" "$C_RESET"
    elif [ "$_avail" -ge 24 ]; then
        printf '  %s↑↓%s %snav%s  %s→%s %sgo%s  %s←%s %sexit%s\n' \
            "$C_OK" "$C_RESET" "$C_GREY" "$C_RESET" \
            "$C_OK" "$C_RESET" "$C_GREY" "$C_RESET" \
            "$C_RED" "$C_RESET" "$C_GREY" "$C_RESET"
    else
        printf '  %s↑↓ →%s  %s←%s\n' "$C_OK" "$C_RESET" "$C_RED" "$C_RESET"
    fi
}

# ---------- 6. Lecture clavier ----------
read_key() {
    _old=$(stty -g 2>/dev/null) || _old=""
    stty -echo -icanon min 1 time 0 2>/dev/null
    _k=$(dd bs=1 count=1 2>/dev/null)
    if [ "$_k" = "$ESC" ]; then
        stty -echo -icanon min 0 time 1 2>/dev/null
        _k1=$(dd bs=1 count=1 2>/dev/null)
        _k2=$(dd bs=1 count=1 2>/dev/null)
        _k="${_k}${_k1}${_k2}"
    fi
    [ -n "$_old" ] && stty "$_old" 2>/dev/null
    printf '%s' "$_k"
}

sel=0
CHOIX=-1
while :; do
    draw_menu
    key=$(read_key)
    case "$key" in
        "${ESC}[A")     sel=$(( (sel - 1 + N) % N )) ;;
        "${ESC}[B")     sel=$(( (sel + 1) % N ))     ;;
        "${ESC}[C")     CHOIX=$sel; break            ;;
        "${ESC}[D")     clear; exit 0                ;;
        "$ESC"|"")      clear; exit 0                ;;
        "$NL"|" ")      CHOIX=$sel; break            ;;
    esac
done

clear
[ "$CHOIX" -lt 0 ] && exit 0

# ---------- 7. Récupération ----------
_line=$(sed -n "$(( CHOIX + 1 ))p" "$SESS_FILE")
CMD=$(printf '%s' "$_line" | cut -f3)
SOURCE=$(printf '%s' "$_line" | cut -f2)
CMD=$(printf '%s' "$CMD" | sed 's/[[:space:]]*%[a-zA-Z]//g')

# ---------- 8. Démarrage serveur Termux:X11 (sans basculer l'UI) ----------
export XDG_RUNTIME_DIR="${TMPDIR}"
termux-x11 :0 >/dev/null &
printf '  %s◆ démarrage Termux:X11…%s\n' "$C_ACCENT" "$C_RESET"
sleep 3

chmod 777 "${TMPDIR}/.X11-unix" 2>/dev/null
[ -S "${TMPDIR}/.X11-unix/X0" ] && chmod 666 "${TMPDIR}/.X11-unix/X0" 2>/dev/null

export PULSE_SERVER=127.0.0.1
export DISPLAY=:0

# ---------- 9. Lancement ----------
case "$SOURCE" in
    native)
        # Basculer sur Termux:X11 AVANT (pas de prompt)
        am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1
        sleep 1
        printf '  %s▸ %s%s%s %s(natif)%s\n' \
            "$C_OK" "$C_BOLD" "$CMD" "$C_RESET" "$C_GREY" "$C_RESET"
        dbus-launch --exit-with-session $CMD >/dev/null 2>&1 &
        ;;

    proot:*)
        _distro="${SOURCE#proot:}"
        am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1
        sleep 1
        printf '  %s▸ %s%s%s %s(proot: %s)%s\n' \
            "$C_ACCENT2" "$C_BOLD" "$CMD" "$C_RESET" \
            "$C_GREY" "$_distro" "$C_RESET"
        proot-distro login "$_distro" --shared-tmp -- \
            env DISPLAY=:0 PULSE_SERVER=127.0.0.1 XDG_RUNTIME_DIR=/tmp \
            dbus-launch --exit-with-session $CMD >/dev/null 2>&1 &
        ;;

    chroot:*)
        # ============================================================
        # Écran de connexion SDDM-like :
        #   1. Prompt utilisateur + mot de passe DANS TERMUX (visible)
        #   2. su root (Magisk) demande son mot de passe DANS TERMUX
        #   3. Le wrapper valide les credentials AVANT de basculer sur X11
        #   4. am start (bascule Termux:X11) seulement après succès
        #   5. Session graphique lancée, puis nettoyage
        # ============================================================
        _distro="${SOURCE#chroot:}"
        _ROOTFS="/data/local/chroot-distro/${_distro}"
        _TMPHOST="${TMPDIR:-/tmp}"

        if ! command -v su >/dev/null 2>&1; then
            printf '  %s⚠ root requis%s\n' "$C_WARN" "$C_RESET"
            exit 1
        fi
        if [ ! -d "$_ROOTFS" ]; then
            printf '  %s⚠ rootfs introuvable: %s%s\n' \
                "$C_WARN" "$_ROOTFS" "$C_RESET"
            exit 1
        fi

        # ---- Écran de connexion (Termux visible) ----
        clear
        printf '\n  %s╭──────────────────────────────────────╮%s\n' \
            "$C_ACCENT" "$C_RESET"
        printf '  %s│%s  %sSession :%s %s%s%s\n' \
            "$C_ACCENT" "$C_RESET" "$C_GREY" "$C_RESET" \
            "$C_BOLD" "$CMD" "$C_RESET"
        printf '  %s│%s  %sDistro  :%s %s%s%s\n' \
            "$C_ACCENT" "$C_RESET" "$C_GREY" "$C_RESET" \
            "$C_ACCENT" "$_distro" "$C_RESET"
        printf '  %s╰──────────────────────────────────────╯%s\n\n' \
            "$C_ACCENT" "$C_RESET"

        printf '  %s→%s %sUtilisateur :%s ' "$C_OK" "$C_RESET" "$C_GREY" "$C_RESET"
        IFS= read -r _user
        [ -z "$_user" ] && _user="root"

        printf '  %s→%s %sMot de passe :%s ' "$C_OK" "$C_RESET" "$C_GREY" "$C_RESET"
        stty -echo 2>/dev/null
        IFS= read -r _pass
        stty sane 2>/dev/null
        printf '\n\n'

        # Mot de passe stocké dans $TMPDIR (accessible Termux + root)
        _PW_FILE="${_TMPHOST}/.tdm-pw.$$"
        printf '%s' "$_pass" > "$_PW_FILE"
        chmod 600 "$_PW_FILE" 2>/dev/null
        unset _pass

        _WRAPPER="${_TMPHOST}/tdm-chroot-launch.$$.sh"

        # ---- Wrapper root ----
        cat > "$_WRAPPER" <<WRAPEOF
#!/system/bin/sh
ROOTFS="$_ROOTFS"
TMPHOST="$_TMPHOST"
USER_CHROOT="$_user"
DISTRO="$_distro"
PWFILE="$_PW_FILE"
CMDFILE="/tmp/tdm-cmd.\$\$.sh"

echo "[tdm] Étape 1/4 : vérification utilisateur '\$USER_CHROOT'…"
if ! chroot-distro login "\$DISTRO" -- id "\$USER_CHROOT" >/dev/null 2>&1; then
    echo "[tdm] ✗ Utilisateur '\$USER_CHROOT' introuvable" >&2
    rm -f "\$PWFILE"
    exit 1
fi

echo "[tdm] Étape 2/4 : préparation du chroot…"
mkdir -p "\$ROOTFS/tmp/.X11-unix"
chmod 1777 "\$ROOTFS/tmp" 2>/dev/null
mount --bind "\$TMPHOST/.X11-unix" "\$ROOTFS/tmp/.X11-unix" 2>/dev/null
[ -d "\$ROOTFS/dev/shm" ] && mount -t tmpfs -o size=256M tmpfs "\$ROOTFS/dev/shm" 2>/dev/null

cat > "\$ROOTFS\$CMDFILE" <<'CMDFILE_EOF'
#!/bin/sh
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
export XDG_RUNTIME_DIR=/tmp
if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- CMD_PLACEHOLDER
fi
exec CMD_PLACEHOLDER
CMDFILE_EOF
sed -i "s|CMD_PLACEHOLDER|$CMD|g" "\$ROOTFS\$CMDFILE"
chmod 755 "\$ROOTFS\$CMDFILE"

echo "[tdm] Étape 3/4 : authentification de '\$USER_CHROOT'…"
PW=\$(cat "\$PWFILE" 2>/dev/null)
rm -f "\$PWFILE"

# Validation : on appelle `id -u` via su pour tester le mot de passe
# sans lancer la session graphique. Une sortie numérique = OK.
if [ -n "\$PW" ] && [ "\$USER_CHROOT" != "root" ]; then
    if command -v script >/dev/null 2>&1; then
        RES=\$(printf "%s\n" "\$PW" | script -qec "su - \$USER_CHROOT -c 'id -u'" /dev/null 2>&1 | tr -d '\r')
        # Garder uniquement la dernière ligne numérique (au cas où su affiche des choses)
        UID_OUT=\$(printf '%s\n' "\$RES" | grep -E '^[0-9]+\$' | tail -1)
        if [ -z "\$UID_OUT" ]; then
            echo "[tdm] ✗ Authentification échouée pour '\$USER_CHROOT'" >&2
            echo "[tdm]   sortie: \$RES" >&2
            unset PW
            umount "\$ROOTFS/tmp/.X11-unix" 2>/dev/null
            umount "\$ROOTFS/dev/shm" 2>/dev/null
            rm -f "\$ROOTFS\$CMDFILE"
            exit 1
        fi
    fi
fi

echo "[tdm] Étape 4/4 : authentifié — bascule Termux:X11 + session…"
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1
sleep 2

# Lancement bloquant de la session
if [ -z "\$PW" ] && [ "\$USER_CHROOT" = "root" ]; then
    chroot-distro login "\$DISTRO" -- sh "\$CMDFILE"
    RC=\$?
elif command -v script >/dev/null 2>&1; then
    printf "%s\n" "\$PW" | script -qec "su - \$USER_CHROOT -c sh \$CMDFILE" /dev/null
    RC=\$?
else
    chroot-distro login "\$DISTRO" -- su - "\$USER_CHROOT" -c "sh \$CMDFILE"
    RC=\$?
fi
unset PW

# Nettoyage
umount "\$ROOTFS/tmp/.X11-unix" 2>/dev/null
umount "\$ROOTFS/dev/shm"       2>/dev/null
rm -f "\$ROOTFS\$CMDFILE"

if [ \$RC -ne 0 ]; then
    echo "[tdm] ✗ Session terminée (code \$RC)" >&2
fi
exit \$RC
WRAPEOF
        chmod 700 "$_WRAPPER"

        # `su` demande le mdp root/Magisk ici, dans Termux visible
        printf '  %s▸ autorisation root (mot de passe Magisk)…%s\n\n' \
            "$C_GREY" "$C_RESET"
        su -c "/system/bin/sh $_WRAPPER"
        _rc=$?

        if [ "$_rc" -ne 0 ]; then
            printf '\n  %s✗ Échec (code %d).%s\n' "$C_RED" "$_rc" "$C_RESET"
            printf '  %sVérifie :%s\n' "$C_GREY" "$C_RESET"
            printf '  %s - mdp lenny : chroot-distro login %s -- passwd -S lenny (doit finir par P)%s\n' \
                "$C_GREY" "$_distro" "$C_RESET"
            printf '  %s - shell de lenny : chroot-distro login %s -- grep ^lenny /etc/passwd%s\n' \
                "$C_GREY" "$_distro" "$C_RESET"
        fi

        rm -f "$_WRAPPER" 2>/dev/null
        ;;
esac

exit 0
