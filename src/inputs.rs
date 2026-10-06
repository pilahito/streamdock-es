use mirajazz::{error::MirajazzError, types::DeviceInput};
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::mappings::{KEY_MAP_15, KEY_MAP_18, MAX_KEY_COUNT};

// Las tablas de traduccion tienen que cuadrar con los tamanos declarados. Si
// alguien anade un modelo con otra disposicion, esto revienta al compilar en vez
// de fallar en silencio sobre el escritorio del usuario.
const _: () = {
    assert!(KEY_MAP_15.len() == 15);
    assert!(KEY_MAP_18.len() == MAX_KEY_COUNT);
};

/// Numero de teclas del aparato que se esta leyendo.
///
/// `mirajazz` pide `process_input` como puntero a funcion, sin contexto, asi que
/// la disposicion activa tiene que vivir en un estatico. En la practica solo hay
/// un aparato conectado a la vez: todos los modelos v1 comparten numero de serie
/// y el plugin solo registra uno.
static ACTIVE_KEY_COUNT: AtomicUsize = AtomicUsize::new(15);

/// Fija la disposicion de teclas del aparato que se va a leer.
pub fn set_active_key_count(key_count: usize) {
    ACTIVE_KEY_COUNT.store(key_count, Ordering::Relaxed);
}

/// Disposicion de teclas activa.
pub fn active_key_count() -> usize {
    ACTIVE_KEY_COUNT.load(Ordering::Relaxed)
}

/// Tabla que traduce indice de OpenDeck -> tecla del firmware.
fn key_map() -> &'static [u8] {
    if active_key_count() <= KEY_MAP_15.len() {
        &KEY_MAP_15
    } else {
        &KEY_MAP_18
    }
}

pub fn process_input(input: u8, state: u8) -> Result<DeviceInput, MirajazzError> {
    log::debug!("Entrada recibida: {}, {}", input, state);

    let key_count = active_key_count();

    // `input` es 1-based y 0 significa "todas las teclas sueltas". Cualquier
    // valor por encima del numero de teclas real es basura del firmware.
    if input as usize > key_count {
        return Err(MirajazzError::BadData);
    }

    read_button_press(input, state, key_count)
}

fn read_button_states(states: &[u8], key_count: usize) -> Vec<bool> {
    (0..key_count).map(|i| states[i + 1] != 0).collect()
}

/// Convierte indice de tecla de OpenDeck a indice de tecla del firmware.
pub fn opendeck_to_device(key: u8) -> u8 {
    key_map().get(key as usize).copied().unwrap_or(key)
}

/// Convierte indice de tecla del firmware a indice de OpenDeck.
pub fn device_to_opendeck(key: usize) -> usize {
    // El firmware numera las teclas desde 1.
    let index = key.saturating_sub(1);

    key_map()
        .iter()
        .position(|&device_key| device_key as usize == index)
        .unwrap_or(index)
}

fn read_button_press(input: u8, state: u8, key_count: usize) -> Result<DeviceInput, MirajazzError> {
    let mut button_states = vec![0x01];
    button_states.extend(vec![0u8; key_count + 1]);

    if input == 0 {
        return Ok(DeviceInput::ButtonStateChange(read_button_states(
            &button_states,
            key_count,
        )));
    }

    let pressed_index: usize = device_to_opendeck(input as usize);

    // `device_to_opendeck` es 0-based, asi que sumamos 1
    button_states[pressed_index + 1] = state;

    Ok(DeviceInput::ButtonStateChange(read_button_states(
        &button_states,
        key_count,
    )))
}
