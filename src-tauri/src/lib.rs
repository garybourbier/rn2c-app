mod tor_proxy;

use std::sync::{Arc, Mutex};
use tauri::{Emitter, Manager};

const ONION_URL: &str =
    "http://e4a5qysp4kwollmwjnoanmk4qbvuowts4awaqjeeylocjc62i5wa2tyd.onion/";

#[derive(Clone, serde::Serialize)]
struct TorEvent {
    ready: bool,
    message: String,
}

// État partagé entre le backend Tor et la commande frontend_ready
struct AppState {
    tor_event: Option<TorEvent>,
    frontend_ready: bool,
}

type SharedState = Arc<Mutex<AppState>>;

#[tauri::command]
fn get_onion_url() -> &'static str {
    ONION_URL
}

#[tauri::command]
fn get_tor_status(state: tauri::State<'_, SharedState>) -> TorEvent {
    let s = state.lock().unwrap();
    s.tor_event.clone().unwrap_or(TorEvent {
        ready: false,
        message: "Connexion au réseau Tor…".to_string(),
    })
}

#[tauri::command]
fn frontend_ready(
    state: tauri::State<'_, SharedState>,
    app: tauri::AppHandle,
) {
    let mut s = state.lock().unwrap();
    s.frontend_ready = true;
    if let Some(ev) = s.tor_event.clone() {
        drop(s);
        app.emit("tor-status", ev).ok();
    }
}

pub fn run() {
    #[allow(unused_unsafe)]
    unsafe {
        std::env::set_var("ALL_PROXY", "socks5h://127.0.0.1:19150");
        std::env::set_var("all_proxy", "socks5h://127.0.0.1:19150");
        std::env::set_var("NO_PROXY", "localhost,127.0.0.1");
    }

    let shared: SharedState = Arc::new(Mutex::new(AppState {
        tor_event: None,
        frontend_ready: false,
    }));

    tauri::Builder::default()
        .manage(shared.clone())
        .setup(move |app| {
            let handle = app.handle().clone();
            let state = shared.clone();

            tauri::async_runtime::spawn(async move {
                let pending = TorEvent {
                    ready: false,
                    message: "Connexion au réseau Tor…".to_string(),
                };
                emit_or_store(&handle, &state, pending);

                match tor_proxy::bootstrap().await {
                    Ok(tor_client) => {
                        // Laisser les circuits se stabiliser
                        tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
                        let ev = TorEvent {
                            ready: true,
                            message: "Tor connecté".to_string(),
                        };
                        emit_or_store(&handle, &state, ev);

                        // Ouvrir la fenêtre principale avec le proxy Tor, fermer le splash
                        if let Ok(w) = tauri::WebviewWindowBuilder::new(
                            &handle,
                            "rn2c",
                            tauri::WebviewUrl::External(ONION_URL.parse().unwrap()),
                        )
                        .title("RN2C")
                        .proxy_url("socks5://127.0.0.1:19150".parse().unwrap())
                        .inner_size(1280.0, 820.0)
                        .center()
                        .build()
                        {
                            let _ = w; // fenêtre créée
                        }
                        if let Some(splash) = handle.get_webview_window("main") {
                            let _ = splash.close();
                        }

                        if let Err(e) = tor_proxy::run_proxy(tor_client, 19150).await {
                            eprintln!("[Tor] proxy arrêté : {}", e);
                        }
                    }
                    Err(e) => {
                        eprintln!("[Tor] bootstrap échoué : {}", e);
                        let ev = TorEvent {
                            ready: false,
                            message: format!("Erreur Tor : {}", e),
                        };
                        emit_or_store(&handle, &state, ev);
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![get_onion_url, get_tor_status, frontend_ready])
        .run(tauri::generate_context!())
        .expect("erreur lors du lancement de RN2C");
}

fn emit_or_store(handle: &tauri::AppHandle, state: &SharedState, ev: TorEvent) {
    let mut s = state.lock().unwrap();
    if s.frontend_ready {
        drop(s);
        handle.emit("tor-status", ev).ok();
    } else {
        s.tor_event = Some(ev);
    }
}
