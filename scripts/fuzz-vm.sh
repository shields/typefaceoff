#!/bin/sh
set -eu

if [ $# -lt 7 ]; then
    echo "usage: $0 setup|run <vm> <image> <disk-gb> <artifacts> <driver-app> <app> [ui-fuzz run options...]" >&2
    exit 64
fi
mode=$1
vm=$2
image=$3
disk_gb=$4
artifacts=$5
driver_app=$6
app=$7
shift 7

state="$PWD/.build/fuzz-vm"
key="$state/id_ed25519"
password="admin"
shares="/Volumes/My Shared Files"
developer_dir=$(xcode-select -p)
xcode=${developer_dir%/Contents/Developer}
tart_pid=
ip=

fail() {
    echo "fuzz-vm: $*" >&2
    exit 1
}

case $disk_gb in
'' | *[!0-9]*) fail "disk size must be a positive integer in GB" ;;
esac
[ "$disk_gb" -gt 0 ] || fail "disk size must be a positive integer in GB"

[ "$xcode" != "$developer_dir" ] || fail "xcode-select -p ($developer_dir) is not inside an Xcode.app"

# Homebrew's ssh lacks macOS Local Network permission; it fails with "No route to host".
vm_ssh() {
    /usr/bin/ssh -F /dev/null -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
        -o UserKnownHostsFile="$state/known_hosts" -o StrictHostKeyChecking=accept-new \
        -i "$key" "$@"
}

quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap below.
stop_vm() {
    if [ -n "$tart_pid" ] && kill -0 "$tart_pid" 2>/dev/null; then
        # shellcheck disable=SC2016 # Expanded by the guest's shell.
        [ -z "$ip" ] || vm_ssh "admin@$ip" 'pkill -TERM -x ui-fuzz || exit 0
            i=0
            while [ "$i" -lt 120 ]; do pgrep -x ui-fuzz >/dev/null || exit 0; sleep 1; i=$((i + 1)); done' || true
        tart stop "$vm" >/dev/null || kill "$tart_pid"
        wait "$tart_pid" || true
    fi
}

start_vm() {
    mkdir -p "$state" "$artifacts"
    trap stop_vm EXIT
    trap 'exit 130' INT TERM
    tart run "$vm" "$@" --no-audio --no-clipboard \
        --dir="repo:$PWD:ro" --dir="xcode:$xcode:ro" --dir="artifacts:$artifacts" &
    tart_pid=$!
    ip=$(tart ip "$vm" --wait 180) || fail "$vm did not get an IP address"
    attempt=0
    until /usr/bin/nc -z -G 2 "$ip" 22 2>/dev/null; do
        kill -0 "$tart_pid" 2>/dev/null || fail "tart run $vm exited"
        attempt=$((attempt + 1))
        [ "$attempt" -lt 90 ] || fail "$vm did not start SSH"
        sleep 2
    done
}

authorize_key() {
    [ -f "$key" ] || ssh-keygen -q -t ed25519 -N "" -C "$vm" -f "$key"
    public_key=$(quote "$(cat "$key.pub")")
    askpass="$state/askpass"
    (umask 077 && printf '#!/bin/sh\necho %s\n' "$password" >"$askpass")
    chmod 700 "$askpass"
    status=0
    SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force /usr/bin/ssh -F /dev/null \
        -o PubkeyAuthentication=no -o ConnectTimeout=5 \
        -o UserKnownHostsFile="$state/known_hosts" -o StrictHostKeyChecking=accept-new \
        "admin@$ip" "umask 077 && mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys &&
            { grep -qxF $public_key ~/.ssh/authorized_keys ||
                echo $public_key >>~/.ssh/authorized_keys; }" </dev/null || status=$?
    rm -f "$askpass"
    [ "$status" -eq 0 ] || fail "could not authorize $key in $vm"
}

ensure_disk_capacity() {
    current_disk=$(tart get "$vm" --format json | plutil -extract Disk raw -o - -)
    case $current_disk in
    '' | *[!0-9]*) fail "could not read $vm disk size" ;;
    esac
    if [ "$current_disk" -lt "$disk_gb" ]; then
        echo "Expanding $vm disk from $current_disk GB to $disk_gb GB."
        tart set "$vm" --disk-size "$disk_gb"
    fi
}

prepare_guest() {
    vm_ssh "admin@$ip" "
        set -e
        until [ -d $(quote "$shares/repo") ]; do sleep 1; done
        defaults write com.apple.CrashReporter DialogType -string none
        ln -sfn $(quote "$shares/xcode") ~/Xcode.app
        xcrun llvm-profdata --version >/dev/null 2>&1 || echo $password | sudo -S -p '' sh -c '
            xcode-select --switch /Users/admin/Xcode.app/Contents/Developer
            xcodebuild -license accept'
        rm -rf ~/typefaceoff
        mkdir ~/typefaceoff
        ditto $(quote "$shares/repo/$driver_app") ~/typefaceoff/UIFuzzDriver.app
        ditto $(quote "$shares/repo/$app") ~/typefaceoff/TypefaceOff.app"
}

# The headless guest's display starts at 1024x768, narrower than the workbench window.
set_display() {
    vm_ssh "admin@$ip" "
        until [ \"\$(stat -f %Su /dev/console)\" = admin ]; do sleep 1; done
        swift $(quote "$shares/repo/scripts/set-vm-display.swift") 1920 1080"
}

run_campaign() {
    arguments=
    for argument in "$@"; do
        arguments="$arguments $(quote "$argument")"
    done
    vm_ssh -t "admin@$ip" "env TYPEFACEOFF_FUZZ_VM=1 $(quote "$shares/repo/scripts/run-fuzz-driver.sh") ~/typefaceoff/UIFuzzDriver.app \
        run --app ~/typefaceoff/TypefaceOff.app --artifacts $(quote "$shares/artifacts")$arguments"
}

case $mode in
setup)
    if ! tart get "$vm" >/dev/null 2>&1; then
        cpus=$(($(sysctl -n hw.ncpu) - 2))
        [ "$cpus" -le 8 ] || cpus=8
        [ "$cpus" -ge 2 ] || cpus=2
        memory=$(($(sysctl -n hw.memsize) / 2097152))
        [ "$memory" -le 16384 ] || memory=16384
        tart clone "$image" "$vm"
        tart set "$vm" --cpu "$cpus" --memory "$memory" --display 2560x1440pt
    fi
    ensure_disk_capacity
    start_vm
    authorize_key
    prepare_guest
    echo "In the $vm window, allow UIFuzzDriver in System Settings > Privacy & Security > Accessibility."
    run_campaign --duration 1s
    ;;
run)
    if ! tart get "$vm" >/dev/null 2>&1 || [ ! -f "$key" ]; then
        fail "$vm is not set up; run make fuzz-vm-setup"
    fi
    ensure_disk_capacity
    start_vm --no-graphics
    prepare_guest
    set_display
    run_campaign "$@"
    ;;
*)
    fail "unknown mode: $mode"
    ;;
esac
