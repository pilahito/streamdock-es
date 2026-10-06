#!/usr/bin/env bash
#
# Empaqueta el plugin para Linux y Windows y genera opendeck-akp153.plugin.zip
#
# Uso:
#   ./empaquetar.sh            # usa la version de Cargo.toml
#   ./empaquetar.sh 0.12.0     # fija la version
#
# Salida: build/opendeck-akp153.plugin.zip

set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$AQUI"

ID="st.lynx.plugins.opendeck-akp153.sdPlugin"
VERSION="${1:-$(grep -m1 '^version' Cargo.toml | cut -d'"' -f2)}"

echo
echo "Empaquetando StreamDock ES v$VERSION"
echo "==================================="
echo

export PATH="$HOME/.cargo/bin:$PATH"

echo "[1/5] Compilando para Linux…"
cargo build --release --target x86_64-unknown-linux-gnu --target-dir target/plugin-linux

echo
echo "[2/5] Compilando para Windows…"
if ! rustup target list --installed | grep -q x86_64-pc-windows-gnu; then
	echo "      anadiendo el target de Windows…"
	rustup target add x86_64-pc-windows-gnu
fi
cargo build --release --target x86_64-pc-windows-gnu --target-dir target/plugin-win

echo
echo "[3/5] Montando el paquete…"
rm -rf build
mkdir -p "build/$ID"

cp -r assets "build/$ID/"
cp manifest.json "build/$ID/"

cp target/plugin-linux/x86_64-unknown-linux-gnu/release/opendeck-akp153 \
	"build/$ID/opendeck-akp153-linux"
cp target/plugin-win/x86_64-pc-windows-gnu/release/opendeck-akp153.exe \
	"build/$ID/opendeck-akp153-win.exe"

chmod +x "build/$ID/opendeck-akp153-linux"

# macOS solo si alguien lo ha compilado antes a mano; no es obligatorio
if [ -f target/plugin-mac/universal2-apple-darwin/release/opendeck-akp153 ]; then
	cp target/plugin-mac/universal2-apple-darwin/release/opendeck-akp153 \
		"build/$ID/opendeck-akp153-mac"
	echo "      (incluido binario de macOS)"
else
	echo "      (sin binario de macOS: el manifiesto lo menciona, OpenDeck lo ignora en Linux/Windows)"
fi

# La version del manifiesto manda: sincronizamos por si acaso
python3 - "$VERSION" "build/$ID/manifest.json" <<'PY'
import json, sys
version, path = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data["Version"] = version
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

echo
echo "[4/5] Comprobando el paquete…"
for f in manifest.json assets/icon.png opendeck-akp153-linux opendeck-akp153-win.exe; do
	if [ -e "build/$ID/$f" ]; then
		printf '      ✓ %s\n' "$f"
	else
		printf '      ✗ FALTA %s\n' "$f" >&2
		exit 1
	fi
done
file "build/$ID/opendeck-akp153-linux" | sed 's/^/      /'
file "build/$ID/opendeck-akp153-win.exe" | sed 's/^/      /'

echo
echo "[5/5] Comprimiendo…"
rm -f build/opendeck-akp153.plugin.zip
if command -v zip >/dev/null 2>&1; then
	(cd build && zip -qr opendeck-akp153.plugin.zip "$ID")
else
	python3 - "$ID" <<'PY'
import os, sys, zipfile
folder = sys.argv[1]
with zipfile.ZipFile("build/opendeck-akp153.plugin.zip", "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(os.path.join("build", folder)):
        for name in files:
            full = os.path.join(root, name)
            z.write(full, os.path.relpath(full, "build"))
PY
fi

echo
ls -lh build/opendeck-akp153.plugin.zip | sed 's/^/      /'
echo
echo "Hecho: build/opendeck-akp153.plugin.zip"
echo
