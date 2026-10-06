# Política sobre IA

## Código

Se puede usar asistencia de LLM para escribir código. De hecho, este fork se ha
desarrollado así y no lo escondemos.

Lo que sí se exige:

- quien envía el cambio tiene que entender lo que hace y poder defenderlo;
- tiene que pasar `cargo fmt`, `cargo clippy -D warnings` y compilar en Linux y
  Windows;
- conviene decirlo en la descripción del cambio.

## Comunicación

Los textos del proyecto (documentación, comentarios, mensajes de log, issues)
están escritos por personas o por agentes, pero **siempre revisados**. No se
acepta texto generado sin revisar: si algo está mal explicado, es culpa de quien
lo firma.

## Herramientas automáticas

Los agentes son bienvenidos si trabajan con las mismas reglas que cualquiera:
cambios pequeños, revisables, con el CI en verde y sin tocar la configuración
del usuario sin permiso.
