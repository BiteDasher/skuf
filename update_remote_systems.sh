#!/usr/bin/env bash
version=7.0.1

use_tmux="?"
post_script=
pre_script=
pacman_cache_dir="/var/cache/pacman/pkg"
store_pacman_cache=1
exec_binary=
exec_arguments=()
do_report=0
stdout_report=0
report_dest=
ignore_fails=0
ignore_user_wish=0
mount_dir="/mnt"
all_mount_opts="rw"
pacman_packages=()
install_on_sync=0
copy_resolvconf=1
sync_packages=()
update_systems=1
high_repo_priority=0

remote_systems=()
temporary=
temporary_location=
remove_temporary=1
tmux_socket_name=

umask 0077

out() { echo "$@"; }
error() { out "==> ERROR:" "$@" >&2; }
warning() { out "==> WARNING:" "$@" >&2; }
msg() { out "==>" "$@"; }
die() { error "$@"; exit 1; }

usage() {
    echo "update_remote_systems.sh (SKUF) v${version}

usage: ${0##*/} [OPTIONS] [REMOTE SYSTEMS]::[MOUNT OPTS]

    Options:
      -a <SCRIPT>     Path to the script on host that will be copied to remote
                        system and executed after update inside chroot
      -b <SCRIPT>     Path to the script on host that will be copied to remote
                        system and executed before update inside chroot
                        (Remote system location is passed to '-a' and '-b'
                         scripts via SYSTEM_PATH environment variable)
      -c <CACHE_DIR>  Path to directory on the host where the pacman package
                        cache shared by remote systems will be stored
                        (default: /var/cache/pacman/pkg)
      -C              Do not use shared pacman package cache
      -D              Do not remove temporary directory on host after update
      -e <BINARY>     Execute <BINARY> instead of 'pacman' on update
      -E <ARGUMENTS>  Provide additional <ARGUMENTS> for 'pacman' command
                        (Should be quoted string;
                         Can be specified multiple times)
      -g              Generate the result of updates in CSV format and write it
                        to stdout
      -G <DEST>       Same as '-g', but write the result to a <DEST>
      -i              Ignore all errors during the update
      -I              Ignore /etc/skuf_disable_external_update on remote systems
      -m <MOUNT_DIR>  Path to directory where remote systems will be mounted
                        (default: /mnt)
      -o <MOUNT_OPTS> Mount options for all remote systems
                        (default: rw)
      -p <PKG>        Path to local pacman package file
                        (Can be specified multiple times)
      -P              Provide 'pacman -Syu' with a list of packages specified in
                        '-p' for explicit (re)installation
      -r              Do not copy /etc/resolv.conf from host to remote system
                        during update
      -S <PKG1,PKG2>  Comma-separated list of additional packages that should be
                        installed when updating via 'pacman -Syu'
                        (Can be specified multiple times)
      -t              Use tmux with graph drawing script to monitor update
                        status of remote systems
      -T              Do not use tmux
      -U              Do not update remote systems via 'pacman -Syu', only
                        update package file(s) specified in '-p' via
                        'pacman -U'
      -w              Prioritize packages specified in '-p' over packages from
                        repositories when updating via 'pacman -Syu'
                        (applies '-P')

      -h              Print this help message

This script allows you to update multiple remote Arch Linux systems."
}

case "$1" in
    "")       usage; exit 1 ;;
    "-h")     usage; exit 0 ;;
    "--help") usage; exit 0 ;;
esac

(( EUID == 0 )) || die 'This script must be run with root privileges'

exit_if_empty() {
    local empty="$1"; shift
    if [[ -z "$empty" ]]; then
        die "$@"
    fi
}

while getopts ':ha:b:c:CDe:E:gG:iIm:o:p:PrS:tTUw' __opt; do
    case $__opt in
        h) usage
           exit 0
           ;;
        a) exit_if_empty "$OPTARG" "Path to post-install script cannot be empty"
           post_script="$OPTARG"
           ;;
        b) exit_if_empty "$OPTARG" "Path to pre-install script cannot be empty"
           pre_script="$OPTARG"
           ;;
        c) exit_if_empty "$OPTARG" "Path to pacman package cache directory cannot be empty"
           store_pacman_cache=1
           pacman_cache_dir="$OPTARG"
           ;;
        C) store_pacman_cache=0
           ;;
        D) remove_temporary=0
           ;;
        e) exit_if_empty "$OPTARG" "Name of executable binary cannot be empty"
           exec_binary="$OPTARG"
           ;;
        E) exec_arguments+=("$OPTARG")
           ;;
        g) do_report=1
           stdout_report=1
           ;;
        G) exit_if_empty "$OPTARG" "Path to report destination cannot be empty"
           do_report=1
           report_dest="$OPTARG"
           ;;
        i) ignore_fails=1
           ;;
        I) ignore_user_wish=1
           ;;
        m) exit_if_empty "$OPTARG" "Path to mount directory cannot be empty"
           mount_dir="$OPTARG"
           ;;
        o) all_mount_opts="$OPTARG"
           ;;
        p) exit_if_empty "$OPTARG" "Path to local pacman package file cannot be empty"
           pacman_packages+=("$OPTARG")
           ;;
        P) install_on_sync=1
           ;;
        r) copy_resolvconf=0
           ;;
        S) exit_if_empty "${OPTARG//,/}" "Names of pacman packages cannot be empty"
           sync_packages+=("$OPTARG")
           ;;
        t) use_tmux=1
           ;;
        T) use_tmux=0
           ;;
        U) update_systems=0
           ;;
        w) install_on_sync=1
           high_repo_priority=1
           ;;
        :) die "option requires an argument -- '$OPTARG'"
           ;;
        ?) die "invalid option -- '$OPTARG'"
           ;;
    esac
done

check_binaries() {
    local text1 text2 binary binaries=(realpath install rm mv cat sed chmod mount umount chroot) notfound=()

    if (( update_systems && ${#pacman_packages[@]} && store_pacman_cache )); then
        binaries+=(ln)
    fi

    if [[ -n "$EPOCHSECONDS" ]]; then
        :
    elif printf "%(%s)T" -1 &>/dev/null; then
        :
    else
        binaries+=(date)
    fi

    if [[ "$use_tmux" == "?" ]]; then
        if command -v tmux &>/dev/null &&
           command -v stty &>/dev/null &&
           command -v kill &>/dev/null; then
            use_tmux=1
        else
            use_tmux=0
        fi
    elif (( use_tmux )); then
        binaries+=(tmux stty kill)
    fi

    for binary in "${binaries[@]}"; do
        command -v "$binary" &>/dev/null || notfound+=("$binary")
    done

    if (( ${#notfound[@]} )); then
        if (( ${#notfound[@]} == 1 )); then
            text1="binary"
            text2="was"
        else
            text1="binaries"
            text2="were"
        fi
        die "The following ${text1} required for execution ${text2} not found: ${notfound[*]}"
    fi
}

check_is_term() {
    if (( use_tmux )) && [[ ! -t 0 ]]; then
        die "Script running in tmux mode should not be executed through a pipe or with stdin closed!"
    fi
}

crtemp() {
    local _umask fallback=0

    while :; do
    ###########
    ((fallback++))

    if [[ -n "${TMPDIR%/}" && "${TMPDIR%/}" != "/" ]]; then
        [[ "${TMPDIR%/}" == /* ]] || TMPDIR="$(realpath "$TMPDIR")" || continue
        temporary="${TMPDIR%/}/skuf_update.${RANDOM:-$fallback}"
        temporary_location="${TMPDIR%/}/skuf_update_tmpdir"
    else
        temporary="/tmp/skuf_update.${RANDOM:-$fallback}"
        temporary_location="/tmp/skuf_update_tmpdir"
    fi

    [[ -d "$temporary" ]] && continue

    install -d -m 700 "$temporary" || die "Unable to create temporary directory"
    _umask="$(umask)"; umask 0022
    echo "$temporary" >> "$temporary_location" || die "Unable to write the location of temporary directory to '$temporary_location'"
    umask "$_umask"
    return 0
    ###########
    done
}

save_report() {
    local error=0

    if [[ ! -f "$temporary/report" ]]; then
        die "'$temporary/report' file does not exists, although it should"
    fi

    if (( stdout_report )); then
        cat "$temporary/report" || {
            error "Unable to read report file -- '$temporary/report'"
            error=1
        }
    fi

    if [[ -n "$report_dest" ]]; then
        [[ "$report_dest" == /* ]] || report_dest="$curdir/$report_dest"
        install -D -m 644 "$temporary/report" "$report_dest" || {
            error "Unable to write report to destination -- '$report_dest'"
            error=1
        }
    fi

    if (( error )); then
        exit 1
    fi
}

clean_up() {
    if (( remove_temporary )); then
        rm -r -f "$temporary"
        rm -f "$temporary_location"
    fi
}

tmux_config() {
    cat <<EOF
unbind-key d
set -g mouse on
set -g history-limit 100000
set -g status on
set -g status-style bg=green,fg=black
set -g status-position bottom
set -g status-left-length 20
set -g pane-border-status top
set -g pane-border-format " #{pane_title} "
set -g pane-border-style bg=default,fg=gray
set -g pane-active-border-style bg=default,fg=green
EOF
}

tmux_setup_socket() {
    local tmux_socket_prefix="skuf_tmux" tmux_socket_nummin=0 tmux_socket_nummax=1000 tmux_socket_number
    tmux_socket_number="$tmux_socket_nummin"

    while tmux -L "${tmux_socket_prefix}${tmux_socket_number}" has-session -t skuf_update &>/dev/null; do
        if (( tmux_socket_number >= tmux_socket_nummax )); then
            die "tmux sockets '${tmux_socket_prefix}${tmux_socket_nummin}' to '${tmux_socket_prefix}${tmux_socket_nummax}' with session 'skuf_update' are busy! Check them. (use 'tmux -L' to specify socket)"
        fi
        ((tmux_socket_number++))
    done
    tmux_socket_name="${tmux_socket_prefix}${tmux_socket_number}"
}

tmux_kill() {
    tmux -L "$tmux_socket_name" kill-session -t skuf_update &>/dev/null
}

stty_size() {
    tty_size="$(stty size)" || return 1
    tty_x="${tty_size##* }"; tty_x="${tty_x:-0}"
    tty_y="${tty_size%% *}"; tty_y="${tty_y:-0}"
    tty_y="$(( tty_y - 2 ))"
    (( tty_y > 0 )) || tty_y=0
}

tmux_setup() {
    tmux -L "$tmux_socket_name" -f <(tmux_config) new-session -x "$tty_x" -y "$tty_y" -s skuf_update -d "$temporary/status" &&
    tmux -L "$tmux_socket_name" -f <(tmux_config) split-window -t skuf_update -h "$temporary/update" &&
    tmux -L "$tmux_socket_name" resize-pane -t skuf_update:0.0 -x 14 &&
    tmux -L "$tmux_socket_name" select-pane -t skuf_update:0.0 -d &&
    tmux -L "$tmux_socket_name" select-pane -t skuf_update:0.1 -e
}

tmux_attach() {
    if (( do_report )) && [[ -z "$report_dest" ]]; then
        tmux -L "$tmux_socket_name" attach-session -t skuf_update >/dev/null
    else
        tmux -L "$tmux_socket_name" attach-session -t skuf_update
    fi
}

mutate_sync_packages() {
    local IFS="," parse

    for pkg in "${sync_packages[@]}"; do
        for parse in $pkg; do
            mutation2+=("$parse")
        done
    done
    sync_packages=("${mutation2[@]}")
}

mutate_opts() {
    local _pkg pkg _resolvconf mutation=() mutation2=()
    # -a
    if [[ -n "$post_script" ]]; then
        post_script="$(echo "$post_script" | sed 's|/*$||')"
        post_script="$(realpath "$post_script")" ||
            die "realpath failed for post-install script"
        [[ -f "$post_script" ]] ||
            die "Unable to find post-install script -- '$post_script'"
    fi
    # -b
    if [[ -n "$pre_script" ]]; then
        pre_script="$(echo "$pre_script" | sed 's|/*$||')"
        pre_script="$(realpath "$pre_script")" ||
            die "realpath failed for pre-install script"
        [[ -f "$pre_script" ]] ||
            die "Unable to find pre-install script -- '$pre_script'"
    fi
    # -p
    for pkg in "${pacman_packages[@]}"; do
        pkg="$(echo "$pkg" | sed 's|/*$||')"
        _pkg="$(realpath "$pkg")" ||
            die "realpath failed for pacman package -- '$pkg'"
        pkg="$_pkg"
        [[ -f "$pkg" ]] ||
            die "Unable to find pacman package -- '$pkg'"
        mutation+=("$pkg")
    done
    pacman_packages=("${mutation[@]}")
    # -S
    mutate_sync_packages
    # -r
    if (( copy_resolvconf )); then
        [[ -e "/etc/resolv.conf" ]] || die "Unable to find /etc/resolv.conf"
        _resolvconf="$(realpath /etc/resolv.conf)" ||
            die "realpath failed for /etc/resolv.conf"
        [[ -f "$_resolvconf" ]] || die "Unable to find origin of /etc/resolv.conf"
    fi
    # -U
    if (( ! update_systems )); then
        (( ${#pacman_packages[@]} )) ||
            die "'-U' flag was specified to update using only local packages, but local packages are not provided"
        (( ! ${#sync_packages[@]} )) ||
            die "'-U' flag was specified to update using only local packages, installing packages from remote repositories via '-S' is not supported in this mode"
    fi
}

do_action_opts() {
    # -c
    if (( store_pacman_cache )); then
        if [[ -d "$pacman_cache_dir" ]]; then
            pacman_cache_dir="$(realpath "$pacman_cache_dir")" ||
                die "realpath failed for shared pacman package cache directory"
        else
            install -d -m 755 "$pacman_cache_dir" ||
                die "Unable to create directory for shared pacman package cache -- '$pacman_cache_dir'"
            pacman_cache_dir="$(realpath "$pacman_cache_dir")" ||
                die "realpath failed for shared pacman package cache directory"
        fi
    fi
    # -m
    if [[ -d "$mount_dir" ]]; then
        mount_dir="$(realpath "$mount_dir")" ||
            die "realpath failed for mount directory"
    else
        install -d -m 755 "$mount_dir" ||
            die "Unable to create mount directory -- '$mount_dir'"
        mount_dir="$(realpath "$mount_dir")" ||
            die "realpath failed for mount directory"
    fi  
}

check_opts_conflicts() {
    local pkg
    # -c, -m
    if (( store_pacman_cache )) && [[ "$pacman_cache_dir" == "$mount_dir" ]]; then
        die "Pacman package cache directory and mount directory cannot be the same"
    fi
    # -p
    for pkg in "${pacman_packages[@]}"; do
        if [[ "${pkg}" == "${mount_dir%/}/"* ]]; then
            die "Pacman packages cannot be located in the mount directory -- '$mount_dir'"
        fi
    done
}

#####################################################################
generate_status() {
cat <<'EOF' > "$temporary/status"
#!/usr/bin/env bash

EOF

declare -p remote_systems temporary tmux_socket_name >> "$temporary/status"

cat <<'EOF' >> "$temporary/status"

rst=$'\033[0m'

get_operation() {
    operation="$(<"$temporary/system.$1")"
    # idle, pre_script, update, post_script, done, problem, skipped
    case "$operation" in
        skipped)
            symcolor=$'\033[0;35m'
            op_symbol='>'
            startsym=$'\033[1;35m[\033[0m'
            endsym=$'\033[1;35m]\033[0m'
            ;;
        pre_script)
            symcolor=$'\033[0;34m'
            op_symbol='-'
            startsym=$'\033[1;34m[\033[0m'
            endsym=$'\033[1;34m]\033[0m'
            ;;
        update)
            symcolor=$'\033[0m'
            op_symbol='.'
            startsym=$'\033[1m[\033[0m'
            endsym=$'\033[1m]\033[0m'
            ;;
        post_script)
            symcolor=$'\033[0;36m'
            op_symbol='+'
            startsym=$'\033[1;36m[\033[0m'
            endsym=$'\033[1;36m]\033[0m'
            ;;
        done)
            symcolor=$'\033[0;32m'
            op_symbol='='
            startsym=$'\033[1;32m[\033[0m'
            endsym=$'\033[1;32m]\033[0m'
            ;;
        problem)
            symcolor=$'\033[0;33m'
            op_symbol='?'
            startsym=$'\033[1;33m[\033[0m'
            endsym=$'\033[1;33m]\033[0m'
            ;;
        fail)
            symcolor=$'\033[0;31m'
            op_symbol='X'
            startsym=$'\033[1;31m[\033[0m'
            endsym=$'\033[1;31m]\033[0m'
            ;;
        idle|*)
            symcolor=$'\033[0m'
            op_symbol=' '
            startsym=$'\033[1m[\033[0m'
            endsym=$'\033[1m]\033[0m'
            ;;
    esac
}

get_current_system() {
    if (( FIRST_DRAW )); then
        current_system=1
    else
        current_system="$(<"$temporary/system.current")"
    fi
}

draw_params() {
    tty_size="$(stty size)"
    tty_x="${tty_size##* }"; tty_x="${tty_x:-0}"
    tty_y="${tty_size%% *}"; tty_y="${tty_y:-0}"

    if (( tty_x >= 14 )); then
        DRAW=1
    else
        DRAW=0
    fi

    get_current_system

    if (( current_system > tty_y )); then
        DRAW_LATEST=1
    else
        DRAW_LATEST=0
    fi
}

draw_bars() {
    echo -ne "\e[H\e[2J\e[3J"

    (( DRAW )) || return 1

    local index

    for index in "${!remote_systems[@]}"; do
        if (( DRAW_LATEST )); then
            (( index > current_system )) && return 0
        else
            (( index > tty_y )) && return 0
        fi
        (( index > 1 )) && echo ""
        draw_bar "$index"
    done
}

draw_bar() {
    (( DRAW )) || return 1

    local index="$1" _counter spaces spacecount _op_symbol

    (( ${2:-0} )) && echo ""

    echo -n " ${index}."

    _counter=1
    spaces="$(( 4 - ${#index} ))"
    (( spaces < 0 )) && spaces=0
    while (( _counter <= spaces )); do
        echo -n " "
        ((_counter++))
    done

    get_operation "$index"
    _op_symbol="$op_symbol"

    echo -n "$startsym"
    echo -n "$symcolor"

    _counter=1
    spacecount="$(( tty_x - spaces - ${#index} - 5 ))"
    while (( _counter <= spacecount )); do
        (( ${3:-0} )) && _op_symbol=" "
        echo -n "$_op_symbol"
        ((_counter++))
    done

    echo -n "$rst"
    echo -n "$endsym"
    echo -n " "
}

move_cursor() {
    (( DRAW )) || return 1

    if (( DRAW_LATEST )); then
        echo -ne "\e[${tty_y};${1:-8}H"
    else
        echo -ne "\e[${current_system};${1:-8}H"
    fi
}

draw_progress() {
    (( DRAW )) || return 1
    (( DRAW_PROGRESS )) || return 0

    local spacecount

    (( DRAW_COUNTER )) || return 0
    spacecount="$(( tty_x - 9 ))"
    (( DRAW_COUNTER > spacecount )) && DRAW_COUNTER=1
    if (( DRAW_COUNTER == 1 )); then
        echo -ne "\e[$(( tty_x - 2 ))G \e[8G${symcolor}${op_symbol}${rst}"
    else
        echo -ne "\e[1D ${symcolor}${op_symbol}${rst}"
    fi
    ((DRAW_COUNTER++))
}

send_usr() {
    kill -s USR"$1" "$update_pid"
}

for_sigusr1() {
    DRAW_COUNTER=0
    move_cursor 0
    draw_bar "$current_system" 0 1
    move_cursor 8
    DRAW_COUNTER=1
    send_usr 1
}

for_sigusr2() {
    local same_check="$current_system"
    DRAW_COUNTER=0
    move_cursor 0
    draw_bar "$current_system"
    draw_params
    if (( same_check != current_system )); then
        move_cursor 0
        draw_bar "$current_system" $DRAW_LATEST
    fi
    move_cursor 8
    DRAW_COUNTER=1
    send_usr 1
}

for_sigwinch() {
    [[ -f "$temporary/update_pid" ]] || exit 0
    DRAW_COUNTER=0
    draw_params
    draw_bars
    if (( DRAW_PROGRESS )); then
        move_cursor 0
        draw_bar "$current_system" 0 1
    fi
    move_cursor 8
    DRAW_COUNTER=1
}

for_sigint() {
    DRAW_PROGRESS=0
    for_sigusr2
    trap - INT
}

for_exit() {
    local exit_code="$?"
    trap '' EXIT USR1 USR2 INT TERM HUP QUIT
    (( exit_code )) && rm -f "$temporary/status_pid"
}

not_initialized() {
    trap '' EXIT USR1 USR2 INT TERM HUP QUIT
    rm -f "$temporary/status_pid"
    tmux -L "$tmux_socket_name" kill-session -t skuf_update
}

cd /

trap ':' USR1 USR2
trap 'not_initialized' EXIT
trap 'exit 1' INT TERM HUP QUIT

echo -ne "\e]0;Status\a"

tput civis 2>/dev/null || echo -ne "\e[?25l"

until [[ "$(tmux -L "$tmux_socket_name" list-sessions -F '#{session_attached}:#{session_name}' 2>/dev/null)" =~ (^|$'\n')1:skuf_update($|$'\n') ]]; do
    :
done
tmux -L "$tmux_socket_name" display-popup -t skuf_update -w 17 -h 3 -E "bash -c \"read -p 'Starting up...' -s -r -t 1\""

until [[ -f "$temporary/update_pid" ]]; do
    :
done
update_pid="$(<"$temporary/update_pid")"

echo "$$" > "$temporary/status_pid"

until [[ -f "$temporary/ready_first_draw" ]]; do
    :
done

trap 'for_exit' EXIT
trap 'exit 1' TERM HUP QUIT
trap 'for_sigusr1' USR1
trap 'for_sigusr2' USR2
trap 'for_sigwinch' WINCH
trap 'for_sigint' INT

FIRST_DRAW=1
draw_params
draw_bars
move_cursor 8
FIRST_DRAW=0

echo "1" > "$temporary/done_first_draw"

until [[ -f "$temporary/system.current" ]]; do
    :
done
get_current_system

DRAW_PROGRESS=1
DRAW_COUNTER=1

while [[ -f "$temporary/update_pid" ]]; do
    draw_progress
    (read -r -d '' -t 0.2 unused <> <(:))
done

exit 0
EOF

chmod 755 "$temporary/status"
}
#####################################################################
generate_update() {
cat <<'EOF' > "$temporary/update"
#!/usr/bin/env bash

EOF

declare -p use_tmux post_script pre_script pacman_cache_dir store_pacman_cache exec_binary exec_arguments do_report stdout_report report_dest ignore_fails ignore_user_wish mount_dir all_mount_opts pacman_packages install_on_sync copy_resolvconf sync_packages update_systems high_repo_priority remote_systems temporary >> "$temporary/update"
(( use_tmux )) && declare -p tmux_socket_name >> "$temporary/update"
declare -fp out error warning msg die >> "$temporary/update"

cat <<'EOF' >> "$temporary/update"

send_usr() {
    [[ -f "$temporary/status_pid" ]] || return 1
    local counter=0 timeout=40 # 2 secs
    SIGDONE=0
    kill -s USR"$1" "$status_pid"
    until (( SIGDONE )); do
        ((counter++))
        if (( counter > timeout )); then
            break
        else
            read -s -r -d '' -t 0.05 unused
        fi
    done
}
send_int() {
    [[ -f "$temporary/status_pid" ]] || return 1
    kill -s INT "$status_pid"
}

ignore_error() {
    "$@" 2>/dev/null
    return 0
}

chroot_add_mount() {
    mount "$@" && CHROOT_ACTIVE_MOUNTS=("$2" "${CHROOT_ACTIVE_MOUNTS[@]}")
}

chroot_maybe_add_mount() {
    local cond="$1"; shift
    if eval "$cond"; then
        chroot_add_mount "$@"
    fi
}

chroot_setup() {
    CHROOT_ACTIVE_MOUNTS=()

    chroot_add_mount proc "$1/proc" -t proc -o nosuid,noexec,nodev &&
    chroot_add_mount sys "$1/sys" -t sysfs -o nosuid,noexec,nodev,ro &&
    ignore_error chroot_maybe_add_mount "[[ -d '$1/sys/firmware/efi/efivars' ]]" \
        efivarfs "$1/sys/firmware/efi/efivars" -t efivarfs -o nosuid,noexec,nodev,ro &&
    chroot_add_mount udev "$1/dev" -t devtmpfs -o mode=0755,nosuid &&
    chroot_add_mount devpts "$1/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec &&
    chroot_add_mount shm "$1/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev &&
    chroot_add_mount /run "$1/run" --bind -o private &&
    chroot_add_mount tmp "$1/tmp" -t tmpfs -o mode=1777,strictatime,nodev,nosuid
}

chroot_teardown() {
    if (( ${#CHROOT_ACTIVE_MOUNTS[@]} )); then
        umount $1 "${CHROOT_ACTIVE_MOUNTS[@]}" && unset CHROOT_ACTIVE_MOUNTS
    fi
}

f_mount() {
    SYSTEM_MOUNTED=0
    mount "$@" && SYSTEM_MOUNTED=1
}

f_umount() {
    if (( SYSTEM_MOUNTED )); then
        umount "$@" && SYSTEM_MOUNTED=0
    fi
}

mount_packages() {
    local pkg counter=0 error=0

    packages_dir="$mount_dir/tmp/some_pacman_repo"
    if [[ -d "$packages_dir" ]]; then
        umount "$packages_dir"/* 2>/dev/null
        rm -r -f "$packages_dir"
    fi
    install -d -m 755 "$packages_dir" || {
        error "Failed to create temporary directory for pacman packages -- '$packages_dir'"
        return 1
    }

    for pkg in "${pacman_packages[@]}"; do
        ((counter++))
        if [[ ! -f "$packages_dir/${pkg##*/}" ]]; then
            : >"$packages_dir/${pkg##*/}" || {
                error "Failed to create dummy file for mounting pacman package ($counter/${#pacman_packages[@]}) -- '$pkg'"
                error=1
                continue
            }
        fi
        chroot_add_mount "$pkg" "$packages_dir/${pkg##*/}" --bind -o ro || {
            error "Failed to mount --bind pacman package ($counter/${#pacman_packages[@]}) -- '$pkg'"
            error=1
        }
    done

    if (( error )); then
        return 1
    fi
}

mount_shared_cache_dir() {
    shared_cache_dir="$mount_dir/tmp/shared_pacman_cache"
    if [[ -d "$shared_cache_dir" ]]; then
        umount "$shared_cache_dir" 2>/dev/null
        rm -r -f "$shared_cache_dir"
    fi
    install -d -m 755 "$shared_cache_dir" || {
        error "Failed to create directory for shared pacman package cache -- '$shared_cache_dir'"
        return 1
    }
    chroot_add_mount "$pacman_cache_dir" "$shared_cache_dir" --bind -o rw || {
        error "Failed to mount --bind directory '$pacman_cache_dir' for shared pacman package cache -- '$shared_cache_dir'"
        return 1
    }
}

bad_mount_helper() {
    case "$1" in
        system)
            SYSTEM_MOUNTED=1
            ;;
        usystem)
            SYSTEM_MOUNTED=0
            ;;
        chroot_setup)
            # /proc, /sys, /sys/firmware/efi/efivarfs
            # /dev, /dev/pts, /dev/shm, /run, /tmp
            # in reverse order
            CHROOT_ACTIVE_MOUNTS=("$mount_dir"{/tmp,/run,/dev/shm,/dev/pts,/dev})
            [[ -d "$mount_dir/sys/firmware/efi/efivars" ]] &&
            CHROOT_ACTIVE_MOUNTS+=("$mount_dir/sys/firmware/efi/efivars")
            CHROOT_ACTIVE_MOUNTS+=("$mount_dir"{/sys,/proc})
            ;;
        chroot_teardown)
            CHROOT_ACTIVE_MOUNTS=()
            ;;
        shared_cache_dir)
            CHROOT_ACTIVE_MOUNTS=("$shared_cache_dir" "${CHROOT_ACTIVE_MOUNTS[@]}")
            ;;
        packages)
            local pkg
            CHROOT_ACTIVE_MOUNTS=("${CHROOT_SAVED_MOUNTS[@]}")
            for pkg in "${pacman_packages[@]}"; do
                CHROOT_ACTIVE_MOUNTS=("$packages_dir/${pkg##*/}" "${CHROOT_ACTIVE_MOUNTS[@]}")
            done
            ;;
    esac
}

create_pkg_symlinks() {
    local pkg

    for pkg in "${pacman_packages[@]}"; do
        if [[ "${pkg%/*}" == "${pacman_cache_dir%/}" ]]; then
            continue
        fi
        if [[ -L "${pacman_cache_dir}/${pkg##*/}" ]]; then
            :
        else
            ln -s -f "/tmp/some_pacman_repo/${pkg##*/}" "${pacman_cache_dir}/${pkg##*/}"
        fi
    done
}

remove_pkg_symlinks() {
    local pkg to_rm=()

    for pkg in "${pacman_packages[@]}"; do
        if [[ "${pkg%/*}" == "${pacman_cache_dir%/}" ]]; then
            continue
        fi
        if [[ -L "${pacman_cache_dir}/${pkg##*/}" ]]; then
            to_rm+=("${pacman_cache_dir}/${pkg##*/}")
        else
            :
        fi
    done

    if (( ${#to_rm[@]} )); then
        rm -f "${to_rm[@]}"
    fi
}

flush_stdin() {
    local unused
    read -r -d '' -t 0.1 -n 9999 unused
    unset unused
}

drop_to_shell() {
    local STATUS="$(<"$temporary/system.$index")" SHELL_EXIT
    echo "problem" > "$temporary/system.$index"
    send_usr 1

    if (( ignore_fails )); then
        FAIL_ACTION='!'
        return 0
    fi

    if [[ $1 == chroot ]]; then
        msg "Right now you are in a shell inside chroot. Try to figure out the problem."
        msg " If the problem is solved, write 'exit 0', and if not, write 'exit 1'"
        msg " If you want to abort the whole update process, write 'exit 5'"
        flush_stdin
        SHELL=/bin/bash chroot "$mount_dir"
        SHELL_EXIT="$?"
    else
        msg "Right now you are in a shell on the host. Try to figure out the problem."
        msg " If the problem is solved, write 'exit 0', and if not, write 'exit 1'"
        msg " If you want to abort the whole update process, write 'exit 5'"
        flush_stdin
        bash -i
        SHELL_EXIT="$?"
    fi

    case "$SHELL_EXIT" in
        0) echo "$STATUS" > "$temporary/system.$index"
           send_usr 1
           [[ $STATUS == update ]] && update_success=1
           FAIL_ACTION=':'
           ;;
        5) FAIL_ACTION='exit 5'
           ;;
      1|*) FAIL_ACTION='on_fail; echo "fail" > "$temporary/system.$index"; continue; !'
           ;;
    esac
}

fail() {
    # mount, chroot_setup, mount_packages
    # install_pre_script, pre_script
    # install_update_script, update
    # install_post_script, post_script
    # chroot_teardown, umount
    case "$1" in
        mount)
            error "Failed to mount remote system to '$mount_dir' -- '$current_system'"
            drop_to_shell
            ;;
        chroot_setup)
            error "Failed to setup chroot mounts for remote system -- '$current_system'"
            drop_to_shell
            ;;
        mount_shared_cache_dir)
            error "Failed to mount --bind shared pacman package cache directory '$shared_cache_dir' for remote system -- '$current_system'"
            drop_to_shell
            ;;
        mount_packages)
            error "Failed to mount --bind some packages to '$packages_dir' for remote system -- '$current_system'"
            drop_to_shell
            ;;
        install_pre_script)
            error "Failed to install pre-install script to '$mount_dir/tmp/pre_script' for remote system -- '$current_system'"
            drop_to_shell
            ;;
        pre_script)
            error "pre-install script executed with non-zero exit code -- '$current_system'"
            drop_to_shell chroot
            ;;
        install_update_script)
            error "Failed to install update script to '$mount_dir/tmp/update_script' for remote system -- '$current_system'"
            drop_to_shell
            ;;
        update)
            error "Failed to update remote system -- '$current_system'"
            drop_to_shell chroot
            ;;
        install_post_script)
            error "Failed to install post-install script to '$mount_dir/tmp/post_script' for remote system -- '$current_system'"
            drop_to_shell
            ;;
        post_script)
            error "post-install script executed with non-zero exit code -- '$current_system'"
            drop_to_shell chroot
            ;;
        chroot_teardown)
            error "Failed to umount chroot mounts for remote system -- '$current_system'"
            drop_to_shell
            ;;
        umount)
            error "Failed to umount remote system from '$mount_dir' -- '$current_system'"
            drop_to_shell
            ;;
    esac
}

copy_resolvconf() {
    if (( copy_resolvconf )); then
        if [[ -e "$mount_dir/etc/resolv.conf" ]]; then
            mv -f "$mount_dir/etc/resolv.conf" "$mount_dir/etc/.bkp.resolv.conf"
        fi
        cat /etc/resolv.conf > "$mount_dir/etc/resolv.conf"
        chmod 644 "$mount_dir/etc/resolv.conf"
    fi
}

restore_resolvconf() {
    if (( copy_resolvconf )); then
        if [[ -e "$mount_dir/etc/.bkp.resolv.conf" ]]; then
            rm -f "$mount_dir/etc/resolv.conf"
            mv -f "$mount_dir/etc/.bkp.resolv.conf" "$mount_dir/etc/resolv.conf"
        fi
    fi
}

get_epoch() {
    local printf

    if [[ -n "$EPOCHSECONDS" ]]; then
        echo "$EPOCHSECONDS"
    elif printf="$(printf "%(%s)T" -1 2>/dev/null)"; then
        echo "$printf"
    else
        date +"%s"
    fi
}

generate_report_string() {
    if [[ $1 == skipped ]]; then
        echo "\"${index}\",\"${current_system//\"/\"\"}\",\"skipped\",\"\"" > "$temporary/report.$index"
        return 0
    fi

    local status date_difference hours minutes seconds date_string

    end_date="$(get_epoch)"

    if (( update_success )); then
        status="success"
    else
        status="failed"
    fi

    if (( end_date && start_date )); then
        date_difference="$(( end_date - start_date ))"
        hours="$((   date_difference / 60 / 60 ))"
        minutes="$(( date_difference / 60 % 60 ))"
        seconds="$(( date_difference % 60 % 60 ))"
        date_string="${hours}h ${minutes}m ${seconds}s"
    fi

    echo "\"${index}\",\"${current_system//\"/\"\"}\",\"${status}\",\"${date_string}\"" > "$temporary/report.$index"
}

generate_report() {
    local system to_cat=()

    for system in "${!remote_systems[@]}"; do
        to_cat+=("$temporary/report.$system")
    done
    cat "${to_cat[@]}" >> "$temporary/report"
}

on_fail() {
    restore_resolvconf
    chroot_teardown || chroot_teardown -l
    f_umount "$mount_dir"
    if (( do_report )); then
        generate_report_string
    fi
}

for_exit() {
    local exit_code="$?"
    trap '' EXIT USR1 USR2 INT TERM HUP QUIT
    if (( update_systems && ${#pacman_packages[@]} && store_pacman_cache )); then
        remove_pkg_symlinks
    fi
    (( exit_code )) && on_fail
    (( do_report )) && generate_report
    rm -f "$temporary/update_pid"
}

not_initialized() {
    trap '' EXIT USR1 USR2 INT TERM HUP QUIT
    rm -f "$temporary/update_pid"
    tmux -L "$tmux_socket_name" kill-session -t skuf_update
}

cd /

if (( use_tmux )); then
#######################
trap ':' USR1 USR2
trap 'not_initialized' EXIT
trap 'exit 1' INT TERM HUP QUIT
#######################
fi

echo -ne "\e]0;Remote systems\a"

echo "$$" > "$temporary/update_pid"

if (( use_tmux )); then
#######################
until [[ -f "$temporary/status_pid" ]]; do
    :
done
status_pid="$(<"$temporary/status_pid")"
#######################
fi

if (( do_report )); then
    echo "\"System number\",\"System location\",\"Update result\",\"Time consumed\"" > "$temporary/report"
fi

for index in "${!remote_systems[@]}"; do
    echo "idle" > "$temporary/system.$index"
    if (( do_report )); then
        _repsys="${remote_systems[$index]}"
        [[ "$_repsys" == *::* ]] && _repsys="${_repsys%::*}"
        echo "\"${index}\",\"${_repsys//\"/\"\"}\",\"\",\"\"" > "$temporary/report.$index"
    fi
    last_index="$index"
done

if (( use_tmux )); then
#######################
echo "1" > "$temporary/ready_first_draw"

until [[ -f "$temporary/done_first_draw" ]]; do
    :
done
#######################
fi

trap '!' INT
trap 'for_exit' EXIT
trap 'exit 1' TERM HUP QUIT
trap 'SIGDONE=1' USR1

for index in "${!remote_systems[@]}"; do
    update_success=0
    FAIL_ACTION=':'
    current_system="${remote_systems[$index]}"
    if [[ "$current_system" == *::* ]]; then
        system_mount_opts="${current_system##*::}"
        current_system="${current_system%::*}"
    else
        system_mount_opts="$all_mount_opts"
    fi
    echo -ne "\e]0;[${index}/${last_index}] ${current_system}\a"
    msg "[${index}/${last_index}] ${current_system}"
    echo "$index" > "$temporary/system.current"
    send_usr 2

    if (( update_systems && ${#pacman_packages[@]} && store_pacman_cache )); then
        create_pkg_symlinks
    fi

    if (( do_report )); then
        start_date=
        end_date=
        start_date="$(get_epoch)"
    fi

    if [[ -d "$current_system" ]]; then
        f_mount --bind -o "$system_mount_opts" "$current_system" "$mount_dir" || {
            fail mount
            eval "$FAIL_ACTION" && bad_mount_helper system
        }
    else
        f_mount -t auto -o "$system_mount_opts" "$current_system" "$mount_dir" || {
            fail mount
            eval "$FAIL_ACTION" && bad_mount_helper system
        }
    fi

    if (( ! ignore_user_wish )); then
        if [[ -f "$mount_dir/etc/skuf_disable_external_update" ]] ||
           [[ -f "$mount_dir/etc/skuf_disable_external_updates" ]]; then
            f_umount "$mount_dir" || {
                fail umount
                eval "$FAIL_ACTION"
            }
            echo "skipped" > "$temporary/system.$index"
            if (( do_report )); then
                generate_report_string skipped
            fi
            continue
        fi
    fi

    chroot_setup "$mount_dir" || {
        fail chroot_setup
        eval "$FAIL_ACTION" && bad_mount_helper chroot_setup
    }

    if (( store_pacman_cache )); then
        mount_shared_cache_dir || {
            fail mount_shared_cache_dir
            eval "$FAIL_ACTION" && bad_mount_helper shared_cache_dir
        }
    fi

    if (( ${#pacman_packages[@]} )); then
        CHROOT_SAVED_MOUNTS=("${CHROOT_ACTIVE_MOUNTS[@]}")
        mount_packages || {
            fail mount_packages
            eval "$FAIL_ACTION" && bad_mount_helper packages
        }
        unset CHROOT_SAVED_MOUNTS
    fi

    copy_resolvconf

    if [[ -f "$pre_script" ]]; then
        install -D -m 755 "$pre_script" "$mount_dir/tmp/pre_script" || {
            fail install_pre_script
            eval "$FAIL_ACTION"
        }
        echo "pre_script" > "$temporary/system.$index"
        send_usr 1
        SYSTEM_PATH="$current_system" chroot "$mount_dir" /tmp/pre_script || {
            fail pre_script
            eval "$FAIL_ACTION"
        }
    fi

    install -D -m 755 "$temporary/update_script" "$mount_dir/tmp/update_script" || {
        fail install_update_script
        eval "$FAIL_ACTION"
    }
    echo "update" > "$temporary/system.$index"
    send_usr 1
    if chroot "$mount_dir" /tmp/update_script; then
        update_success=1
    else
        fail update
        eval "$FAIL_ACTION"
    fi

    if [[ -f "$post_script" ]]; then
        install -D -m 755 "$post_script" "$mount_dir/tmp/post_script" || {
            fail install_post_script
            eval "$FAIL_ACTION"
        }
        echo "post_script" > "$temporary/system.$index"
        send_usr 1
        SYSTEM_PATH="$current_system" chroot "$mount_dir" /tmp/post_script || {
            fail post_script
            eval "$FAIL_ACTION"
        }
    fi

    restore_resolvconf

    chroot_teardown || {
        fail chroot_teardown
        eval "$FAIL_ACTION" && bad_mount_helper chroot_teardown
    }
    f_umount "$mount_dir" || {
        fail umount
        eval "$FAIL_ACTION" && bad_mount_helper usystem
    }

    if (( update_success )); then
        echo "done" > "$temporary/system.$index"
    else
        echo "fail" > "$temporary/system.$index"
    fi

    if (( do_report )); then
        generate_report_string
    fi
done
send_int

if (( use_tmux && ! do_report )); then
    echo ""
    msg "Done! Press any key to exit"
    read -s -r -n 1 unused
fi

exit 0
EOF

chmod 755 "$temporary/update"
}
#####################################################################
generate_update_script() {
cat <<'EOF' > "$temporary/update_script"
#!/usr/bin/env bash

EOF

declare -p store_pacman_cache exec_binary exec_arguments pacman_packages install_on_sync sync_packages update_systems high_repo_priority >> "$temporary/update_script"
declare -fp out error warning msg die >> "$temporary/update_script"
    
cat <<'EOF' >> "$temporary/update_script"

set -o pipefail

setup_repo() {
    pushd /tmp/some_pacman_repo >/dev/null || return 1
    repo-add some_pacman_repo.db.tar *     || { popd >/dev/null; return 1; }
    popd >/dev/null
}

create_pacman_config() {
    {
        cat /etc/pacman.conf                        &&
        echo ""                                     &&
        echo "[some_pacman_repo]"                   &&
        echo "SigLevel = Optional"                  &&
        echo "Server = file:///tmp/some_pacman_repo"
    } > /tmp/mod_pacman.conf
}

if [[ -z "$exec_binary" ]]; then
    pacman_command=("pacman")
else
    pacman_command=("$exec_binary")
fi

if (( update_systems )); then
    pacman_command+=("-Syu")
    if (( ${#pacman_packages[@]} )); then
        setup_repo || die "Failed to setup pacman repo for provided pacman packages"
        create_pacman_config || die "Failed to create modified pacman.conf"
        pacman_command+=("--config")
        pacman_command+=("/tmp/mod_pacman.conf")
    fi
else
    pacman_command+=("-U")
fi

if (( store_pacman_cache )); then
    pacman_command+=("--cachedir")
    pacman_command+=("/tmp/shared_pacman_cache")
fi

pacman_command+=("--noconfirm")

if (( ${#exec_arguments[@]} )); then
    pacman_command+=(${exec_arguments[*]})
fi

if (( update_systems )); then
    if (( install_on_sync && ${#pacman_packages[@]} || ${#sync_packages[@]} )); then
        pacman_command+=("--")
    fi
    if (( install_on_sync && ${#pacman_packages[@]} )); then
        pkglist="$(bsdtar -xOf /tmp/some_pacman_repo/some_pacman_repo.db.tar | sed '/^%NAME%$/,/^[[:space:]]*$/!d;/^%NAME%$/d;/^[[:space:]]*$/d')" || die "Failed to retrieve package names"
        if (( high_repo_priority )); then
            pkglist="$(echo "$pkglist" | sed 's/^/some_pacman_repo\//')" || die "Failed to format package names"
        fi
        mapfile -t -O ${#pacman_command[@]} pacman_command < <(echo "$pkglist") || die "Failed to map package names to array"
    fi
    if (( ${#sync_packages[@]} )); then
        pacman_command+=("${sync_packages[@]}")
    fi
else
    pacman_command+=("--")
    pacman_command+=(/tmp/some_pacman_repo/*)
fi

exec "${pacman_command[@]}"
EOF

chmod 755 "$temporary/update_script"
}
#####################################################################
check_binaries
check_is_term

shift $(( OPTIND - 1 ))

syscnt=1
for remsys in "$@"; do
    if [[ "$remsys" == *::* ]]; then
        syschk="${remsys%::*}"
        sysopt="::${remsys##*::}"
    else
        syschk="$remsys"
        sysopt=""
    fi
    if [[ -n "$syschk" ]]; then
        syschk_rp="$(realpath "$syschk")" || die "realpath failed for remote system location -- '$syschk'"
        [[ -e "$syschk_rp" ]] || die "Unable to find location of remote system -- '$syschk_rp'"
        remote_systems[$syscnt]="${syschk_rp}${sysopt}"
        ((syscnt++))
    fi
done

if (( ! ${#remote_systems[@]} )); then
    die "No remote systems specified"
fi

mutate_opts
do_action_opts
check_opts_conflicts

crtemp
trap 'clean_up' EXIT

curdir="$(pwd)"
cd /

(( use_tmux )) && tmux_setup_socket
(( use_tmux )) && generate_status
generate_update
generate_update_script

if (( use_tmux )); then
    stty_size || die "Unable to fetch terminal window size"
    tmux_setup || { tmux_kill; die "Unable to setup tmux session"; }
    tmux_attach || error "'tmux attach' command executed with non-zero exit code"
    tmux_kill
else
    "$temporary/update"
fi
(( do_report )) && save_report

exit 0
# vim: set ft=sh ts=4 sw=4 et:
