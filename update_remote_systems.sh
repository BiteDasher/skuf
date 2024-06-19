#!/usr/bin/env bash

post_script=
pre_script=
pacman_cache_dir="/var/cache/pacman/pkg"
store_pacman_cache=1
ignore_fails=0
mount_dir="/mnt"
all_mount_opts="rw"
pacman_packages=()
install_on_sync=0
copy_resolvconf=1
update_systems=1

remote_systems=()
temporary=

out() { echo "$@"; }
error() { out "==> ERROR:" "$@" >&2; }
warning() { out "==> WARNING:" "$@" >&2; }
msg() { out "==>" "$@"; }
die() { error "$@"; exit 1; }

usage() {
    cat <<EOF
usage: ${0##*/} [OPTIONS] [REMOTE SYSTEMS]::[MOUNT OPTS]

    Options:
      -a <SCRIPT>     Path to the script on host that will be copied
                       to remote system and executed after update
                       inside chroot
      -b <SCRIPT>     Path to the script on host that will be copied
                       to remote system and executed before update
                       inside chroot
      -c <CACHE_DIR>  Path to directory on the host where the pacman
                       package cache shared by remote systems will be
                       stored (default: /var/cache/pacman/pkg)
      -C              Do not use shared pacman package cache
      -i              Ignore all errors during the update
      -m <MOUNT_DIR>  Path to directory where remote systems will be
                       mounted
      -o <MOUNT_OPTS> Mount options for all remote systems
                       (default: rw)
      -p <PKG>        Path to local pacman package file
                       (Can be specified multiple times)
      -P              Provide 'pacman -Syu' with a list of packages
                       specified in '-p' for explicit (re)installation
      -r              Do not copy /etc/resolv.conf from host to
                       remote system during update
      -U              Do not update remote systems via 'pacman -Syu',
                       only update the package file(s) specified in
                       '-p' via 'pacman -U'

      -h              Print this help message

This script allows you to update multiple remote Arch Linux systems.
EOF
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

while getopts ':ha:b:c:Cim:o:p:PUr' __opt; do
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
        i) ignore_fails=1
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
        U) update_systems=0
           ;;
        :) die "option requires an argument -- '$OPTARG'"
           ;;
        ?) die "invalid option -- '$OPTARG'"
           ;;
    esac
done

check_binaries() {
    local text1 text2 binary binaries=(tmux realpath install rm mv cat sed chmod stty kill mount umount chroot) notfound=()

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

crtemp() {
    local SKUF_TMPDIR fallback=0

    while :; do

    ((fallback++))

    if [[ -n "${TMPDIR%/}" && "${TMPDIR%/}" != "/" ]]; then
        [[ "${TMPDIR%/}" == /* ]] || TMPDIR="$(realpath "$TMPDIR")" || continue
        SKUF_TMPDIR="${TMPDIR%/}/skuf_update.${RANDOM:-$fallback}"
    else
        SKUF_TMPDIR="/tmp/skuf_update.${RANDOM:-$fallback}"
    fi

    [[ -d "$SKUF_TMPDIR" ]] && continue
    install -d -m 700 "$SKUF_TMPDIR" || return 1
    echo "$SKUF_TMPDIR"
    return 0

    done
}

tmux_config() {
    cat <<EOF
set -g mouse on
set -g history-limit 10000
set -g status-position bottom
set -g status-left-length 20
set -g pane-border-status top
set -g pane-border-format " #{pane_title} "
set -g pane-border-style fg=green
set -g pane-active-border-style bg=default,fg=gray
EOF
}

tmux_check() {
    if tmux has-session -t skuf_update &>/dev/null; then
        die "tmux session 'skuf_update' already exists! Check it."
    fi
}

tmux_kill() {
    tmux kill-session -t skuf_update &>/dev/null
}

stty_size() {
    tty_size="$(stty size)" || return 1
    tty_x="${tty_size##* }"; tty_x="${tty_x:-0}"
    tty_y="${tty_size%% *}"; tty_y="${tty_y:-0}"
}

tmux_setup() {
    tmux -f <(tmux_config) new-session -x "$tty_x" -y "$tty_y" -s skuf_update -d "$temporary/status" &&
    tmux -f <(tmux_config) split-window -t skuf_update -h "$temporary/update" &&
    tmux resize-pane -t skuf_update:0.0 -x 16 &&
    tmux select-pane -t skuf_update:0.0 -d -T "Status" &&
    tmux select-pane -t skuf_update:0.1 -e -T "Remote systems"
}

tmux_attach() {
    tmux attach-session -t skuf_update
}

mutate_opts() {
    local _pkg pkg _resolvconf mutation=()
    # -a
    if [[ -n "$post_script" ]]; then
        post_script="$(echo "$post_script" | sed 's|/*$||')"
        post_script="$(realpath "$post_script")" ||
            die "realpath failed for post-install script"
        [[ -f "$post_script" ]] ||
            die "Unable to find post-install script -- '$_post_script'"
    fi
    # -b
    if [[ -n "$pre_script" ]]; then
        pre_script="$(echo "$pre_script" | sed 's|/*$||')"
        pre_script="$(realpath "$pre_script")" ||
            die "realpath failed for post-install script"
        [[ -f "$pre_script" ]] ||
            die "Unable to find post-install script -- '$pre_script'"
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

check_opts_dups() {
    if [[ "$pacman_cache_dir" == "$mount_dir" ]]; then
        die "Pacman package cache directory and mount directory cannot be the same"
    fi
}

#####################################################################
generate_status() {
cat <<'EOF' > "$temporary/status"
#!/usr/bin/env bash

EOF

declare -p ignore_fails remote_systems temporary >> "$temporary/status"

cat <<'EOF' >> "$temporary/status"

rst="$(echo -ne "\e[0m")"

get_operation() {
    operation="$(<"$temporary/system.$1")"
    # idle, pre_script, update, post_script, done, problem
    case "$operation" in
        pre_script)
            symcolor="$(echo -ne "\e[0;34m")"
            op_symbol="-"
            startsym="$(echo -ne "\e[1;34m[\e[0m")"
            endsym="$(echo -ne "\e[1;34m]\e[0m")"
            ;;
        update)
            symcolor="$(echo -ne "\e[0m")"
            op_symbol="."
            startsym="$(echo -ne "\e[1m[\e[0m")"
            endsym="$(echo -ne "\e[1m]\e[0m")"
            ;;
        post_script)
            symcolor="$(echo -ne "\e[0;36m")"
            op_symbol="-"
            startsym="$(echo -ne "\e[1;36m[\e[0m")"
            endsym="$(echo -ne "\e[1;36m]\e[0m")"
            ;;
        done)
            symcolor="$(echo -ne "\e[0;32m")"
            op_symbol="="
            startsym="$(echo -ne "\e[1;32m[\e[0m")"
            endsym="$(echo -ne "\e[1;32m]\e[0m")"
            ;;
        problem)
            if (( ignore_fails )); then
                symcolor="$(echo -ne "\e[0;31m")"
                op_symbol="X"
                startsym="$(echo -ne "\e[1;31m[\e[0m")"
                endsym="$(echo -ne "\e[1;31m]\e[0m")"
            else
                symcolor="$(echo -ne "\e[0;33m")"
                op_symbol="?"
                startsym="$(echo -ne "\e[1;33m[\e[0m")"
                endsym="$(echo -ne "\e[1;33m]\e[0m")"
            fi
            ;;
        idle|*)
            symcolor="$(echo -ne "\e[0m")"
            op_symbol=" "
            startsym="$(echo -ne "\e[1m[\e[0m")"
            endsym="$(echo -ne "\e[1m]\e[0m")"
            ;;
    esac
}

get_current_system() {
    current_system="$(<"$temporary/system.current")"
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
    (( DRAW )) || return 1

    local index

    echo -ne "\e[H\e[2J\e[3J"

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

for_sigusr1() {
    DRAW_COUNTER=0
    move_cursor 0
    draw_bar "$current_system" 0 1
    move_cursor 8
    DRAW_COUNTER=1
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
}

for_sigwinch() {
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
    trap - INT
}

until [[ -f "$temporary/update_pid" ]]; do
    :
done

update_pid="$(<"$temporary/update_pid")"

echo "$$" > "$temporary/status_pid"

trap : USR1
trap : USR2

until [[ -f "$temporary/system.current" ]]; do
    :
done

trap for_sigusr1 USR1
trap for_sigusr2 USR2
trap for_sigwinch WINCH
trap for_sigint INT

tput civis 2>/dev/null || echo -ne "\e[?25l"

draw_params
draw_bars
move_cursor 8

DRAW_PROGRESS=1
DRAW_COUNTER=1
while [[ -f "$temporary/update_pid" ]]; do
    draw_progress
    read -s -r -t 0.2 unused
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

declare -p post_script pre_script pacman_cache_dir store_pacman_cache ignore_fails mount_dir all_mount_opts pacman_packages install_on_sync copy_resolvconf update_systems remote_systems temporary >> "$temporary/update"
declare -fp out error warning msg die >> "$temporary/update"

cat <<'EOF' >> "$temporary/update"

send_usr1() {
    kill -s USR1 "$status_pid"
}
send_usr2() {
    kill -s USR2 "$status_pid"
}
send_int() {
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
        efivarfs "$1/sys/firmware/efi/efivars" -t efivarfs -o nosuid,noexec,nodev &&
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

mount_packages() {
    local pkg

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
        : >"$packages_dir/${pkg##*/}" || {
            error "Failed to create dummy file for mounting pacman package -- '$pkg'"
            return 1
        }
        chroot_add_mount "$pkg" "$packages_dir/${pkg##*/}" --bind -o ro || {
            error "Failed to mount --bind pacman package -- '$pkg'"
            return 1
        }
    done
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


flush_stdin() {
    local unused
    read -r -d '' -t 0.1 -n 9999 unused
    unset unused
}

drop_to_shell() {
    local STATUS="$(<"$temporary/system.$index")" SHELL_EXIT
    echo "problem" > "$temporary/system.$index"
    send_usr1

    if (( ignore_fails )); then
        FAIL_ACTION=:
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
           send_usr1
           [[ $STATUS == update ]] && update_success=1
           FAIL_ACTION=:
           ;;
        5) FAIL_ACTION="exit 5"
           ;;
        1|*) FAIL_ACTION="on_fail; continue"
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
            error "Failed to mount --bind packages for remote system -- '$current_system'"
            drop_to_shell
            ;;
        install_pre_script)
            error "Failed to install pre-install script to remote system -- '$current_system'"
            drop_to_shell
            ;;
        pre_script)
            error "pre-install script executed with non-zero exit code -- '$current_system'"
            drop_to_shell chroot
            ;;
        install_update_script)
            error "Failed to install update script to remote system -- '$current_system'"
            drop_to_shell
            ;;
        update)
            error "Failed to update remote system -- '$current_system'"
            drop_to_shell chroot
            ;;
        install_post_script)
            error "Failed to install post-install script to remote system -- '$current_system'"
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

on_fail() {
    restore_resolvconf
    chroot_teardown || chroot_teardown -l
    umount "$mount_dir" 2>/dev/null
}

for_exit() {
    trap '' EXIT INT TERM HUP QUIT
    on_fail
    rm -r -f "$temporary"
}

echo "$$" > "$temporary/update_pid"

until [[ -f "$temporary/status_pid" ]]; do
    :
done

status_pid="$(<"$temporary/status_pid")"

trap for_exit EXIT
trap ! INT
trap "exit 1" TERM HUP QUIT

for index in "${!remote_systems[@]}"; do
    echo "idle" > "$temporary/status.$index"
    last_index="$index"
done

cd /

system_mount_opts=
for index in "${!remote_systems[@]}"; do
    update_success=0
    FAIL_ACTION=:
    current_system="${remote_systems[$index]}"
    if [[ "$current_system" == *::* ]]; then
        system_mount_opts="${current_system##*::}"
        current_system="${current_system%::*}"
    else
        system_mount_opts="$all_mount_opts"
    fi
    echo -ne "\e]0;[${index}/${last_index}] ${current_system}\a"
    echo "$index" > "$temporary/system.current"
    send_usr2

    if [[ -d "$current_system" ]]; then
        mount --bind -o "$system_mount_opts" "$current_system" "$mount_dir" || {
            fail mount
            eval "$FAIL_ACTION"
        }
    else
        mount -t auto -o "$system_mount_opts" "$current_system" "$mount_dir" || {
            fail mount
            eval "$FAIL_ACTION"
        }
    fi

    chroot_setup "$mount_dir" || {
        fail chroot_setup
        eval "$FAIL_ACTION"
    }

    if (( store_pacman_cache )); then
        mount_shared_cache_dir || {
            fail mount_shared_cache_dir
            eval "$FAIL_ACTION"
        }
    fi

    if (( ${#pacman_packages[@]} )); then
        mount_packages || {
            fail mount_packages
            eval "$FAIL_ACTION"
        }
    fi

    copy_resolvconf

    if [[ -f "$pre_script" ]]; then
        install -D -m 755 "$pre_script" "$mount_dir/tmp/pre_script" || {
            fail install_pre_script
            eval "$FAIL_ACTION"
        }
        echo "pre_script" > "$temporary/system.$index"
        send_usr1
        chroot "$mount_dir" /tmp/pre_script || {
            fail pre_script
            eval "$FAIL_ACTION"
        }
    fi

    install -D -m 755 "$temporary/update_script" "$mount_dir/tmp/update_script" || {
        fail install_update_script
        eval "$FAIL_ACTION"
    }
    echo "update" > "$temporary/system.$index"
    send_usr1
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
        send_usr1
        chroot "$mount_dir" /tmp/post_script || {
            fail post_script
            eval "$FAIL_ACTION"
        }
    fi

    restore_resolvconf

    chroot_teardown || {
        fail chroot_teardown
        eval "$FAIL_ACTION"
    }
    umount "$mount_dir" || {
        fail umount
        eval "$FAIL_ACTION"
    }

    if (( update_success )); then
        echo "done" > "$temporary/system.$index"
        send_usr1
    fi
done
send_usr2
send_int

msg "Done! Press any key to exit"
read -s -r -n 1 unused
exit 0
EOF

chmod 755 "$temporary/update"
}
#####################################################################
generate_update_script() {
cat <<'EOF' > "$temporary/update_script"
#!/usr/bin/env bash

EOF

declare -p store_pacman_cache pacman_packages install_on_sync update_systems >> "$temporary/update_script"
declare -fp out error warning msg die >> "$temporary/update_script"
    
cat <<'EOF' >> "$temporary/update_script"

setup_repo() {
    pushd /tmp/some_pacman_repo
    repo-add some_pacman_repo.db.tar *
    popd
}

create_pacman_config() {
    {
        cat /etc/pacman.conf
        echo ""
        echo "[some_pacman_repo]"
        echo "SigLevel = Optional"
        echo "Server = file:///tmp/some_pacman_repo"
    } > /tmp/mod_pacman.conf
}

pacman_command=("pacman")
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

if (( update_systems )); then
    if (( install_on_sync && ${#pacman_packages[@]} )); then
        pacman_command+=("--")
        mapfile -t -O ${#pacman_command[@]} pacman_command < <(tar -xOf /tmp/some_pacman_repo/some_pacman_repo.db.tar | sed '/%NAME%/,/^[[:space:]]*$/!d;/%NAME%/d;/^[[:space:]]*$/d')
    fi
else
    pacman_command+=("--")
    for pkg in /tmp/some_pacman_repo/*; do
        pacman_command+=("$pkg")
    done
fi

exec "${pacman_command[@]}"
EOF

chmod 755 "$temporary/update_script"
}
#####################################################################
check_binaries

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

umask 0077

mutate_opts
do_action_opts
check_opts_dups

temporary="$(crtemp)" || die "Unable to create temporary directory"

generate_update
generate_status
generate_update_script

tmux_check
stty_size || die "Unable to fetch terminal window size"
tmux_setup || { tmux_kill; die "Unable to setup tmux session"; }
tmux_attach || { tmux_kill; die "Unable to attach to tmux session"; }
tmux_kill

:
# vim: set ft=sh ts=4 sw=4 et:
