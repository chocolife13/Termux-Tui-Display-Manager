#!/data/data/com.termux/files/usr/bin/bash

trap 'clear; exit 0' INT TERM

# ================== PALETTE ==================
C_RESET=$'\e[0m'
C_DIM=$'\e[2m'
C_BOLD=$'\e[1m'
C_BG_SEL=$'\e[48;5;236m'
C_ACCENT=$'\e[38;5;39m'
C_ACCENT2=$'\e[38;5;213m'
C_TITLE=$'\e[38;5;45m'
C_OK=$'\e[38;5;46m'
C_WARN=$'\e[38;5;220m'
C_GREY=$'\e[38;5;245m'
C_ARROW=$'\e[38;5;207m'
C_RED=$'\e[1;38;5;196m'      # rouge gras pour quitter
# =============================================

# --- 1. Nettoyage anciennes sessions X11 ---
kill -9 $(pgrep -f "termux.x11") 2>/dev/null

# --- 2. PulseAudio ---
if ! pgrep -x pulseaudio >/dev/null; then
    pulseaudio --start \
        --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
        --exit-idle-time=-1
fi

# --- 3. Découverte des sessions ---
NATIVE_XSESSIONS="${PREFIX}/share/xsessions"
CONTAINERS_DIR="${PREFIX}/var/lib/proot-distro/containers"

declare -a LABELS
declare -a CMDS
declare -a SRC

scan_xsessions() {
    local dir="$1" source="$2"
    [ -d "$dir" ] || return 0
    for desktop in "$dir"/*.desktop; do
        [ -f "$desktop" ] || continue
        grep -q '^NoDisplay=true' "$desktop" && continue
        grep -q '^Hidden=true'    "$desktop" && continue

        local name exec_cmd tryexec
        name=$(awk -F=    '/^Name=/{sub(/^Name=/,""); print; exit}'     "$desktop")
        exec_cmd=$(awk -F= '/^Exec=/{sub(/^Exec=/,""); print; exit}'    "$desktop")
        tryexec=$(awk -F=  '/^TryExec=/{sub(/^TryExec=/,""); print; exit}' "$desktop")

        [ -z "$name" ]     && continue
        [ -z "$exec_cmd" ] && continue

        if [ "$source" = "native" ] && [ -n "$tryexec" ] \
           && ! command -v "$tryexec" >/dev/null 2>&1; then
            continue
        fi

        LABELS+=("$name")
        CMDS+=("$exec_cmd")
        SRC+=("$source")
    done
}

scan_xsessions "$NATIVE_XSESSIONS" "native"
if [ -d "$CONTAINERS_DIR" ]; then
    for croot in "$CONTAINERS_DIR"/*/rootfs; do
        [ -d "$croot" ] || continue
        container=$(basename "$(dirname "$croot")")
        scan_xsessions "$croot/usr/share/xsessions" "$container"
    done
fi

N=${#LABELS[@]}
if [ "$N" -eq 0 ]; then
    clear
    echo "${C_WARN}⚠ Aucune session trouvée.${C_RESET}"
    exit 1
fi

# --- 4. Menu coloré adaptatif ---
sel=0
CHOIX=-1

# helpers
term_w() { tput cols  2>/dev/null || echo 80; }
term_h() { tput lines 2>/dev/null || echo 24; }

draw_menu() {
    local W H margin avail
    W=$(term_w); H=$(term_h)
    margin=2
    avail=$(( W - margin * 2 ))
    [ "$avail" -lt 20 ] && avail=20

    clear

    # --- En-tête (compacte si l'écran est petit) ---
    if [ "$H" -ge $(( N + 8 )) ] && [ "$W" -ge 40 ]; then
        printf "\n"
        printf "  ${C_TITLE}${C_BOLD}╔═ Termux Display Manager ═╗${C_RESET}\n\n"
    else
        printf "${C_TITLE}${C_BOLD}Termux DM${C_RESET} ${C_GREY}(%d sessions)${C_RESET}\n\n" "$N"
    fi

    # --- Lignes de sessions ---
    local i name src tag tagcol tag_len fixed name_max pad spaces
    for i in "${!LABELS[@]}"; do
        name="${LABELS[$i]}"
        src="${SRC[$i]}"

        if [ "$src" = "native" ]; then
            tag="native"; tagcol="$C_OK"
        else
            tag="$src";   tagcol="$C_ACCENT2"
        fi

        tag_len=$(( ${#tag} + 2 ))          # [tag]
        fixed=$(( 4 + tag_len + 2 ))        # ▶ + espaces + [tag]
        name_max=$(( avail - fixed ))
        [ "$name_max" -lt 4 ] && name_max=4

        # troncature propre du nom
        if [ "${#name}" -gt "$name_max" ]; then
            name="${name:0:$((name_max - 1))}…"
        fi

        pad=$(( avail - ${#name} - tag_len - 4 ))
        [ "$pad" -lt 1 ] && pad=1
        spaces=$(printf "%${pad}s" "")

        if [ "$i" -eq "$sel" ]; then
            printf "  ${C_ARROW}${C_BOLD}▶${C_RESET} ${C_BG_SEL}${C_BOLD} %s${C_RESET}${C_BG_SEL}%s${tagcol}%s${C_RESET}${C_BG_SEL} ${C_RESET}\n" \
                "$name" "$spaces" "[$tag]"
        else
            printf "  ${C_GREY} ${C_RESET} ${C_BOLD}%s${C_RESET}${C_GREY}%s${tagcol}%s${C_RESET}\n" \
                "$name" "$spaces" "[$tag]"
        fi
    done

    # --- Séparateur adaptatif ---
    local sep_len sep
    sep_len=$(( avail < 40 ? avail : 40 ))
    [ "$sep_len" -lt 10 ] && sep_len=10
    sep=$(printf "%${sep_len}s" "" | tr ' ' '─')

    # --- Barre d'instructions adaptative ---
    printf "\n"
    printf "  ${C_GREY}%s${C_RESET}\n" "$sep"

    if [ "$avail" -ge 44 ]; then
        printf "  ${C_OK}↑↓${C_RESET} ${C_GREY}naviguer${C_RESET}   ${C_OK}→${C_RESET} ${C_GREY}lancer${C_RESET}   ${C_RED}←${C_RESET} ${C_GREY}quitter${C_RESET}\n"
    elif [ "$avail" -ge 24 ]; then
        printf "  ${C_OK}↑↓${C_RESET} ${C_GREY}nav${C_RESET}  ${C_OK}→${C_RESET} ${C_GREY}go${C_RESET}  ${C_RED}←${C_RESET} ${C_GREY}exit${C_RESET}\n"
    else
        printf "  ${C_OK}↑↓ →${C_RESET}  ${C_RED}←${C_RESET}\n"
    fi
}

while true; do
    draw_menu
    IFS= read -rsn1 key || { clear; exit 0; }

    if [[ "$key" == $'\e' ]]; then
        IFS= read -rsn2 -t 0.1 rest || rest=""
        key="$key$rest"
    fi

    case "$key" in
        $'\e[A') sel=$(( (sel - 1 + N) % N )) ;;
        $'\e[B') sel=$(( (sel + 1) % N )) ;;
        $'\e[C') CHOIX=$sel; break ;;              # → lancer
        $'\e[D') clear; exit 0 ;;                  # ← quitter
        $'\e')   clear; exit 0 ;;
        '')      CHOIX=$sel; break ;;
    esac
done

clear
[ "$CHOIX" -lt 0 ] && exit 0

# --- 5. Préparation ---
CMD="${CMDS[$CHOIX]}"
SOURCE="${SRC[$CHOIX]}"
CMD=$(echo "$CMD" | sed -E 's/[[:space:]]*%[a-zA-Z]//g')

# --- 6. Lancement Termux:X11 ---
export XDG_RUNTIME_DIR=${TMPDIR}
termux-x11 :0 >/dev/null &
printf "  ${C_ACCENT}◆ démarrage Termux:X11…${C_RESET}\n"
sleep 3

am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1
sleep 1

# --- 7. Environnement + lancement session ---
export PULSE_SERVER=127.0.0.1
export DISPLAY=:0

if [ "$SOURCE" = "native" ]; then
    printf "  ${C_OK}▸ ${C_BOLD}%s${C_RESET} ${C_GREY}(natif)${C_RESET}\n" "$CMD"
    dbus-launch --exit-with-session $CMD >/dev/null 2>&1 &
else
    printf "  ${C_ACCENT2}▸ ${C_BOLD}%s${C_RESET} ${C_GREY}(conteneur ${SOURCE})${C_RESET}\n" "$CMD"
    proot-distro login "$SOURCE" --shared-tmp -- \
        env DISPLAY=:0 PULSE_SERVER=127.0.0.1 XDG_RUNTIME_DIR=/tmp \
        dbus-launch --exit-with-session $CMD >/dev/null 2>&1 &
fi

exit 0