# Guía para agentes y contribuidores

Este fork nació para arreglar un problema concreto: el plugin original declaraba
18 ranuras para todos los modelos, y los aparatos de 15 teclas arrastraban tres
teclas fantasma. Si vas a tocar algo, ten esto en cuenta.

## Reglas del proyecto

1. **El número de teclas es por modelo.** Nunca vuelvas a meter una constante
   global de teclas. Usa `Kind::key_count()` y `Kind::col_count()`.
2. **Las tablas de traducción van en pareja.** `KEY_MAP_15` y `KEY_MAP_18` de
   `src/mappings.rs` deben cuadrar con los tamaños declarados; hay un `assert!`
   en tiempo de compilación en `src/inputs.rs` que lo comprueba.
3. **`process_input` no tiene contexto.** `mirajazz` lo pide como puntero a
   función, así que la disposición activa se guarda en un estático
   (`ACTIVE_KEY_COUNT`). Si algún día se soportan dos aparatos de distinta
   disposición a la vez, esto hay que replanteárselo.
4. **Nada de dependencies nuevas sin justificarlo.** El plugin tiene que arrancar
   rápido y compilar en Linux y Windows.
5. **Todo en español**: documentación, comentarios, mensajes de log y textos del
   manifiesto.

## Antes de dar algo por terminado

```bash
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo clippy --all-targets --target x86_64-pc-windows-gnu -- -D warnings
./empaquetar.sh
```

El CI hace exactamente esto. Si clippy se queja, se arregla; no se silencia con
`#[allow]` salvo que haya una razón de peso, y entonces se explica en un
comentario.

## Mensajes de commit

Conventional Commits, en español y sin florituras:

```
feat(device): soporte para el modelo X
fix(mappings): corregir el numero de teclas de los v1
docs(readme): aclarar la migracion de perfiles
chore(ci): compilar tambien para Windows
```

Tipos: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `build`, `ci`.

## Qué NO hacer por tu cuenta

- No abras pull requests, issues ni comentarios en nombre del proyecto.
- No publiques releases sin que lo pida el responsable.
- No toques los perfiles ni la configuración de OpenDeck del usuario.

## Uso de IA

Este fork se ha desarrollado con asistencia de LLM, y se dice claramente. El
código se revisa, se compila y se prueba antes de publicar. Las contribuciones
hechas con ayuda de IA son bienvenidas siempre que pasen el CI y quien las envíe
entienda lo que hace.
