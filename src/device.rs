use data_url::DataUrl;
use image::load_from_memory_with_format;
use mirajazz::{device::Device, error::MirajazzError, state::DeviceStateUpdate};
use openaction::{OUTBOUND_EVENT_MANAGER, SetImageEvent};
use std::{sync::Arc, time::Duration};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

use crate::{
    DEVICES, FLUSH_NOTIFY, TOKENS,
    inputs::{opendeck_to_device, set_active_key_count},
    mappings::{CandidateDevice, ENCODER_COUNT, Kind, ROW_COUNT, get_image_format_for_key},
};

/// Initializes a device and listens for events
pub async fn device_task(candidate: CandidateDevice, token: CancellationToken) {
    log::info!("Ejecutando tarea del dispositivo {:?}", candidate);

    // Wrap in a closure so we can use `?` operator
    let device = async || -> Result<Device, MirajazzError> {
        let device = connect(&candidate).await?;

        device.set_brightness(50).await?;
        device.clear_all_button_images().await?;
        device.flush().await?;

        Ok(device)
    }()
    .await;

    let device: Device = match device {
        Ok(device) => device,
        Err(err) => {
            handle_error(&candidate.id, err).await;

            log::error!(
                "Error al inicializar el dispositivo, se termina la tarea: {:?}",
                candidate
            );

            return;
        }
    };

    log::info!("Registrando dispositivo {}", candidate.id);
    if let Some(outbound) = OUTBOUND_EVENT_MANAGER.lock().await.as_mut() {
        outbound
            .register_device(
                candidate.id.clone(),
                candidate.kind.human_name(),
                ROW_COUNT as u8,
                candidate.kind.col_count() as u8,
                ENCODER_COUNT as u8,
                0,
            )
            .await
            .unwrap();
    }

    DEVICES.write().await.insert(candidate.id.clone(), device);

    let flush_notify = Arc::new(Notify::new());
    FLUSH_NOTIFY
        .write()
        .await
        .insert(candidate.id.clone(), flush_notify.clone());

    tokio::select! {
        _ = device_events_task(&candidate) => {},
        _ = device_flush_task(&candidate.id, flush_notify, token.clone()) => {},
        _ = token.cancelled() => {}
    };

    FLUSH_NOTIFY.write().await.remove(&candidate.id);

    log::info!("Apagando device {:?}", candidate);

    if let Some(device) = DEVICES.read().await.get(&candidate.id) {
        device.shutdown().await.ok();
    }

    log::info!("Tarea del dispositivo terminada: {:?}", candidate);
}

/// Handles errors, returning true if should continue, returning false if an error is fatal
pub async fn handle_error(id: &String, err: MirajazzError) -> bool {
    log::error!("Error en el dispositivo {}: {}", id, err);

    // Some errors are not critical and can be ignored without sending disconnected event
    if matches!(err, MirajazzError::ImageError(_) | MirajazzError::BadData) {
        return true;
    }

    log::info!("Desregistrando el dispositivo {}", id);
    if let Some(outbound) = OUTBOUND_EVENT_MANAGER.lock().await.as_mut() {
        outbound.deregister_device(id.clone()).await.unwrap();
    }

    log::info!("Cancelando tareas del dispositivo {}", id);
    if let Some(token) = TOKENS.read().await.get(id) {
        token.cancel();
    }

    log::info!("Quitando el dispositivo {} de la lista", id);
    DEVICES.write().await.remove(id);

    log::info!("Limpieza terminada para {}", id);

    false
}

pub async fn connect(candidate: &CandidateDevice) -> Result<Device, MirajazzError> {
    let result = Device::connect(
        &candidate.dev,
        candidate.kind.protocol_version(),
        candidate.kind.key_count(),
        ENCODER_COUNT,
    )
    .await;

    match result {
        Ok(device) => Ok(device),
        Err(e) => {
            log::error!("Error al conectar con el dispositivo: {e}");

            Err(e)
        }
    }
}

/// Flushes queued images after a 50ms quiet window following the last set_button_image call.
/// Sleeps entirely when the device is idle — no polling.
async fn device_flush_task(id: &String, notify: Arc<Notify>, token: CancellationToken) {
    loop {
        tokio::select! {
            _ = notify.notified() => {}
            _ = token.cancelled() => break,
        }

        // Keep resetting the window while more images arrive; fire when quiet for 16ms.
        loop {
            tokio::select! {
                _ = notify.notified() => {}
                _ = token.cancelled() => return,
                _ = tokio::time::sleep(Duration::from_millis(50)) => break,
            }
        }

        let flush_result = {
            let guard = DEVICES.read().await;
            if let Some(device) = guard.get(id) {
                log::info!("Volcando los cambios pendientes");
                device.flush().await
            } else {
                Ok(())
            }
        };
        if let Err(err) = flush_result {
            handle_error(id, err).await;
            break;
        }
    }
}

/// Handles events from device to OpenDeck
async fn device_events_task(candidate: &CandidateDevice) -> Result<(), MirajazzError> {
    log::info!("Conectando con {} para recibir eventos", candidate.id);

    // La lectura de teclas no recibe contexto, asi que fijamos aqui la
    // disposicion del aparato antes de crear el lector.
    set_active_key_count(candidate.kind.key_count());

    let devices_lock = DEVICES.read().await;
    let reader = match devices_lock.get(&candidate.id) {
        Some(device) => device.get_reader(crate::inputs::process_input),
        None => return Ok(()),
    };
    drop(devices_lock);

    log::info!("Conectado a {} para recibir eventos", candidate.id);

    log::info!("Lector preparado para {}", candidate.id);

    loop {
        log::info!("Leyendo actualizaciones...");

        let updates = match reader.read(None).await {
            Ok(updates) => updates,
            Err(e) => {
                if !handle_error(&candidate.id, e).await {
                    break;
                }

                continue;
            }
        };

        for update in updates {
            log::info!("Nueva actualizacion: {:#?}", update);

            let id = candidate.id.clone();

            if let Some(outbound) = OUTBOUND_EVENT_MANAGER.lock().await.as_mut() {
                match update {
                    DeviceStateUpdate::ButtonDown(key) => outbound.key_down(id, key).await.unwrap(),
                    DeviceStateUpdate::ButtonUp(key) => outbound.key_up(id, key).await.unwrap(),
                    DeviceStateUpdate::EncoderDown(encoder) => {
                        outbound.encoder_down(id, encoder).await.unwrap();
                    }
                    DeviceStateUpdate::EncoderUp(encoder) => {
                        outbound.encoder_up(id, encoder).await.unwrap();
                    }
                    DeviceStateUpdate::EncoderTwist(encoder, val) => {
                        outbound
                            .encoder_change(id, encoder, val as i16)
                            .await
                            .unwrap();
                    }
                }
            }
        }
    }

    Ok(())
}

/// Handles different combinations of "set image" event, including clearing the specific buttons and whole device
pub async fn handle_set_image(
    device: &Device,
    id: &str,
    evt: SetImageEvent,
) -> Result<(), MirajazzError> {
    match (evt.position, evt.image) {
        (Some(position), Some(image)) => {
            log::info!("Poniendo imagen en la tecla {}", position);

            // OpenDeck sends image as a data url, so parse it using a library
            let url = DataUrl::process(image.as_str()).unwrap(); // Isn't expected to fail, so unwrap it is
            let (body, _fragment) = url.decode_to_vec().unwrap(); // Same here

            // Allow only image/jpeg mime for now
            if url.mime_type().subtype != "jpeg" {
                log::error!("Tipo MIME incorrecto: {}", url.mime_type());

                return Ok(()); // Not a fatal error, enough to just log it
            }

            let image = load_from_memory_with_format(body.as_slice(), image::ImageFormat::Jpeg)?;

            let kind = Kind::from_vid_pid(device.vid, device.pid).unwrap(); // Safe to unwrap here, because device is already filtered

            device
                .set_button_image(
                    opendeck_to_device(position),
                    get_image_format_for_key(&kind, position),
                    image,
                )
                .await?;

            if let Some(notify) = FLUSH_NOTIFY.read().await.get(id) {
                notify.notify_one();
            }
        }
        (Some(position), None) => {
            device
                .clear_button_image(opendeck_to_device(position))
                .await?;

            if let Some(notify) = FLUSH_NOTIFY.read().await.get(id) {
                notify.notify_one();
            }
        }
        (None, None) => {
            device.clear_all_button_images().await?;
            device.flush().await?;
        }
        _ => {}
    }

    Ok(())
}
