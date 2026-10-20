#!/usr/bin/env bash
set -u

DEVICE_NAME='SYNA3602:00 0911:5288 Touchpad'

echo '== Sistema =='
sed -n '1,12p' /etc/os-release
uname -a
printf 'Sessão: %s / %s\n' "${XDG_CURRENT_DESKTOP:-desconhecida}" "${XDG_SESSION_TYPE:-desconhecida}"

echo
echo '== DMI =='
for field in sys_vendor product_name product_version board_vendor board_name; do
    printf '%-18s ' "$field"
    cat "/sys/class/dmi/id/$field" 2>/dev/null || true
done

echo
echo '== Touchpad =='
awk -v name="$DEVICE_NAME" '
    BEGIN { RS = "" }
    index($0, "N: Name=\"" name "\"") { print }
' /proc/bus/input/devices

event_node=$(awk -v name="$DEVICE_NAME" '
    BEGIN { RS = "" }
    index($0, "N: Name=\"" name "\"") {
        for (i = 1; i <= NF; i++)
            if ($i ~ /^event[0-9]+$/) event = $i
    }
    END { if (event) print "/dev/input/" event }
' /proc/bus/input/devices)

if [[ -n $event_node ]]; then
    echo
    echo '== Capacidades de botão =='
    EVENT_NODE="$event_node" python3 - <<'PY'
import os

event = os.path.basename(os.environ['EVENT_NODE'])
words = open(f'/sys/class/input/{event}/device/capabilities/key', encoding='ascii').read().split()
words = [int(word, 16) for word in reversed(words)]
for code, name in [(272, 'BTN_LEFT'), (273, 'BTN_RIGHT'), (274, 'BTN_MIDDLE')]:
    word, bit = divmod(code, 64)
    advertised = word < len(words) and bool((words[word] >> bit) & 1)
    print(f'{name:<12} code={code} advertised={advertised}')
PY

    echo
    echo '== Quirks efetivas =='
    libinput quirks list "$event_node" 2>&1 || true
fi

echo
echo '== Overrides locais =='
for file in /etc/libinput/local-overrides.quirks /usr/share/libinput/local-overrides.quirks; do
    if [[ -e $file ]]; then
        echo "[$file]"
        sed -n '1,160p' "$file"
    fi
done

echo
echo '== input-remapper =='
systemctl is-enabled input-remapper-daemon.service 2>&1 || true
systemctl is-active input-remapper-daemon.service 2>&1 || true
awk 'BEGIN{RS=""} /input-remapper/ {print $0"\n"}' /proc/bus/input/devices
