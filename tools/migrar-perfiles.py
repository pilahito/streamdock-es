#!/usr/bin/env python3
"""Migra perfiles de OpenDeck de la rejilla de 18 ranuras a la de 15.

El plugin original declaraba 6 columnas para todos los modelos, asi que los
aparatos de 15 teclas (AKP153, HSV293S y clones) tenian tres ranuras fantasma:
los indices 5, 11 y 17. Este script reordena los perfiles para que cada tecla
siga haciendo lo mismo una vez el plugin declara las 5 columnas reales.

    indice nuevo (15)   <-   indice viejo (18)
    -----------------------------------------
    0 .. 4                   0 .. 4
    5 .. 9                   6 .. 10
    10 .. 14                 12 .. 16
    (nada)                   5, 11, 17  -> se descartan

Uso:
    python3 tools/migrar-perfiles.py --simular     # solo enseña lo que haria
    python3 tools/migrar-perfiles.py               # lo aplica (con copia .bak)
    python3 tools/migrar-perfiles.py --dir RUTA    # otra carpeta de config
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

RANURAS_NUEVAS = 15
RANURAS_VIEJAS = 18

# Ranuras de la 6ª columna del plugin antiguo: existian en la interfaz pero no en
# el aparato. Ojo: los indices nuevos 5 y 11 coinciden con dos de ellas.
RANURAS_FANTASMA = (5, 11, 17)


def nuevo_a_viejo(nuevo: int) -> int:
    """Indice de la rejilla nueva -> indice equivalente en la vieja."""
    if nuevo < 5:
        return nuevo
    if nuevo < 10:
        return nuevo + 1
    return nuevo + 2


def migrar_perfil(ruta: Path, simular: bool) -> str:
    """Devuelve un resumen de lo hecho, o el motivo para no tocarlo."""
    datos = json.loads(ruta.read_text(encoding="utf-8"))
    claves = datos.get("keys")

    if claves is None:
        return "sin campo 'keys', se deja igual"
    if len(claves) == RANURAS_NUEVAS:
        return f"ya tiene {RANURAS_NUEVAS} ranuras, nada que hacer"
    if len(claves) != RANURAS_VIEJAS:
        return f"tiene {len(claves)} ranuras (ni 15 ni 18), se deja igual"
    if not any(k is not None for k in claves):
        return "vacio, nada que hacer"

    ocupadas_viejas = [i for i, k in enumerate(claves) if k is not None]

    # ¿Se pierde algo en las ranuras fantasma?
    perdidas = [i for i in RANURAS_FANTASMA if claves[i] is not None]

    nuevas = []
    for i in range(RANURAS_NUEVAS):
        viejo = nuevo_a_viejo(i)
        clave = claves[viejo]
        if clave is not None:
            clave = json.loads(json.dumps(clave))  # copia
            clave["context"] = f"Keypad.{i}.0"
        nuevas.append(clave)

    datos["keys"] = nuevas

    resumen = f"{len(ocupadas_viejas)} teclas configuradas"
    if perdidas:
        resumen += f"; se descartan las fantasma {', '.join(map(str, perdidas))}"

    if simular:
        return resumen

    ruta.with_suffix(".json.bak").write_text(
        json.dumps(json.loads(ruta.read_text(encoding="utf-8")), indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    ruta.write_text(json.dumps(datos, indent=2, ensure_ascii=False), encoding="utf-8")

    return resumen


def migrar_imagenes(carpeta: Path, simular: bool) -> list[str]:
    """Renombra Keypad.<viejo>.0 -> Keypad.<nuevo>.0 dentro de un perfil."""
    if not carpeta.is_dir():
        return []

    cambios: list[tuple[int, int]] = []
    for i in range(RANURAS_NUEVAS):
        viejo = nuevo_a_viejo(i)
        if viejo != i and (carpeta / f"Keypad.{viejo}.0").is_dir():
            cambios.append((viejo, i))

    if not cambios or simular:
        return [f"Keypad.{v}.0 -> Keypad.{n}.0" for v, n in cambios]

    # 1) Fuera las ranuras fantasma ANTES de renombrar. Tiene que ser antes y no
    #    despues: los indices nuevos 5 y 11 coinciden con dos de las fantasma, y
    #    si se borran al final se lleva por delante las imagenes recien movidas.
    for viejo in RANURAS_FANTASMA:
        sobrante = carpeta / f"Keypad.{viejo}.0"
        if sobrante.is_dir():
            shutil.rmtree(sobrante)

    # 2) A un nombre temporal, para no pisarnos al renombrar
    for viejo, nuevo in cambios:
        origen = carpeta / f"Keypad.{viejo}.0"
        if not origen.is_dir():
            continue
        origen.rename(carpeta / f".tmp_{nuevo}")
    for _, nuevo in cambios:
        temporal = carpeta / f".tmp_{nuevo}"
        if temporal.is_dir():
            temporal.rename(carpeta / f"Keypad.{nuevo}.0")

    return [f"Keypad.{v}.0 -> Keypad.{n}.0" for v, n in cambios]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", default="~/.config/opendeck",
                        help="carpeta de configuracion de OpenDeck")
    parser.add_argument("--simular", action="store_true",
                        help="enseña lo que haria sin tocar nada")
    args = parser.parse_args()

    base = Path(args.dir).expanduser()
    perfiles = base / "profiles"
    imagenes = base / "images"

    if not perfiles.is_dir():
        print(f"No encuentro {perfiles}", file=sys.stderr)
        print("¿Esta OpenDeck instalado y has usado algun perfil?", file=sys.stderr)
        return 1

    if args.simular:
        print("MODO SIMULACION — no se toca nada\n")

    tocados = 0
    fallos = 0
    for dispositivo in sorted(p for p in perfiles.iterdir() if p.is_dir()):
        ficheros = sorted(dispositivo.glob("*.json"))
        if not ficheros:
            continue

        print(f"Dispositivo {dispositivo.name}")
        for ruta in ficheros:
            try:
                resultado = migrar_perfil(ruta, args.simular)
            except Exception as exc:  # noqa: BLE001
                print(f"  {ruta.stem:<24} ERROR: {exc}")
                fallos += 1
                continue

            print(f"  {ruta.stem:<24} {resultado}")
            if resultado.startswith("ya tiene") or resultado.startswith("sin campo") \
                    or "se deja igual" in resultado or resultado.startswith("vacio"):
                continue
            tocados += 1

            carpeta_imgs = imagenes / dispositivo.name / ruta.stem
            try:
                for linea in migrar_imagenes(carpeta_imgs, args.simular):
                    print(f"      imagen {linea}")
            except Exception as exc:  # noqa: BLE001
                print(f"      ERROR moviendo imagenes: {exc}")
                fallos += 1
        print()

    if args.simular:
        print(f"{tocados} perfil(es) se migrarian. Quita --simular para aplicarlo.")
    else:
        print(f"{tocados} perfil(es) migrados. Se guardo un .bak de cada uno.")
        print("Reinicia OpenDeck para que lo vea.")

    if fallos:
        print(f"\n{fallos} perfil(es) dieron error; revisa la salida de arriba.", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
