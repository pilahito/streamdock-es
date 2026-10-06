#!/usr/bin/env bash
#
# instalador de StreamDock ES para Linux
#
#   - instala OpenDeck si no esta
#   - copia las reglas udev para que /dev/hidraw* sea accesible sin sudo
#   - deja el plugin en ~/.config/opendeck/plugins/
#
# Uso:
#   ./install-linux.sh              # instala todo
#   ./install-linux.sh --sin-udev   # no toca /etc (solo el plugin)

set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="st.lynx.plugins.opendeck-akp153.sdPlugin"
DESTINO="$HOME/.config/opendeck/plugins/$PLUGIN_ID"
REGLAS="$AQUI/40-opendeck-akp153.rules"
SIN_UDEV=0

for arg in "$@"; do
	case "$arg" in
		--sin-udev) SIN_UDEV=1 ;;
		-h | --help)
			sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*)
			echo "Opcion desconocida: $arg" >&2
			exit 2
			;;
	esac
done

ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
aviso() { printf '  \033[33m!\033[0m %s\n' "$1"; }
error() { printf '  \033[31m✗\033[0m %s\n' "$1" >&2; }

echo
echo "StreamDock ES — instalador para Linux"
echo "====================================="
echo

# ── 1. OpenDeck ────────────────────────────────────────────────────────────
echo "[1/4] OpenDeck"

if command -v opendeck >/dev/null 2>&1; then
	ok "ya instalado ($(command -v opendeck))"
else
	if command -v pacman >/dev/null 2>&1; then
		echo "      instalando con pacman…"
		sudo pacman -S --needed --noconfirm opendeck
		ok "instalado con pacman"
	elif command -v apt >/dev/null 2>&1; then
		aviso "en Debian/Ubuntu OpenDeck no esta en los repositorios"
		aviso "instalalo desde https://github.com/nekename/OpenDeck/releases"
	elif command -v dnf >/dev/null 2>&1; then
		aviso "en Fedora usa el .rpm de https://github.com/nekename/OpenDeck/releases"
	else
		aviso "no reconozco tu gestor de paquetes"
		aviso "instala OpenDeck a mano: https://github.com/nekename/OpenDeck"
	fi
fi

# ── 2. reglas udev ─────────────────────────────────────────────────────────
echo
echo "[2/4] Reglas udev"

if [ "$SIN_UDEV" -eq 1 ]; then
	aviso "omitidas (--sin-udev)"
elif [ ! -f "$REGLAS" ]; then
	error "no encuentro $REGLAS"
	exit 1
else
	sudo install -m 644 "$REGLAS" /etc/udev/rules.d/40-opendeck-akp153.rules
	ok "copiadas a /etc/udev/rules.d/40-opendeck-akp153.rules"
	sudo udevadm control --reload-rules
	sudo udevadm trigger --action=change --subsystem-match=hidraw || true
	ok "udev recargado"
fi

# ── 3. plugin ──────────────────────────────────────────────────────────────
echo
echo "[3/4] Plugin"

mkdir -p "$DESTINO"

if [ -x "$AQUI/opendeck-akp153-linux" ]; then
	install -m 755 "$AQUI/opendeck-akp153-linux" "$DESTINO/opendeck-akp153-linux"
	install -m 644 "$AQUI/manifest.json" "$DESTINO/manifest.json"
	[ -d "$AQUI/assets" ] && cp -r "$AQUI/assets" "$DESTINO/"
	ok "plugin copiado desde el propio repositorio"
elif [ -f "$AQUI/opendeck-akp153.plugin.zip" ]; then
	python3 - "$AQUI/opendeck-akp153.plugin.zip" "$DESTINO/.." <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
PY
	chmod +x "$DESTINO/opendeck-akp153-linux" 2>/dev/null || true
	ok "plugin descomprimido desde el .zip"
else
	error "no encuentro el binario. Compila con ./empaquetar.sh o descarga el .zip de releases"
	exit 1
fi

# ── 4. permisos del hidraw ─────────────────────────────────────────────────
echo
echo "[4/4] Comprobacion del dispositivo"

encontrado=0
for nodo in /dev/hidraw*; do
	[ -e "$nodo" ] || continue
	vid=$(cat "/sys/class/hidraw/$(basename "$nodo")/device/uevent" 2>/dev/null | grep -o 'HID_ID=[0-9A-F]*:[0-9A-F]*:[0-9A-F]*' | cut -d: -f3 | tr 'A-F' 'a-f')
	case "$vid" in
		00005548 | 00000300 | 00006603 | 00000b00 | 00000c00 | 00000a00 | 00001500 | 00000500 | 00000600 | 00000400)
			if [ -r "$nodo" ]; then
				ok "$nodo es legible por $(id -un)"
			else
				aviso "$nodo existe pero no es legible. Desenchufa y vuelve a enchufar el aparato."
			fi
			encontrado=1
			;;
	esac
done

if [ "$encontrado" -eq 0 ]; then
	aviso "no he visto ningun stream deck conocido conectado"
fi

echo
echo "Listo. Desenchufa y vuelve a enchufar el aparato y reinicia OpenDeck."
echo
