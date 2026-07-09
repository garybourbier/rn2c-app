mod tor_proxy;

use std::sync::{Arc, Mutex};
use tauri::{Emitter, Manager};

const ONION_URL: &str =
    "http://e4a5qysp4kwollmwjnoanmk4qbvuowts4awaqjeeylocjc62i5wa2tyd.onion/";
const ONION_HOST: &str =
    "e4a5qysp4kwollmwjnoanmk4qbvuowts4awaqjeeylocjc62i5wa2tyd.onion";
#[cfg(target_os = "android")]
const LOCAL_PROXY_URL: &str = "http://127.0.0.1:8181/";

#[derive(Clone, serde::Serialize)]
struct TorEvent {
    ready: bool,
    message: String,
}

struct AppState {
    tor_event: Option<TorEvent>,
    frontend_ready: bool,
    logs: Vec<String>,
}

type SharedState = Arc<Mutex<AppState>>;

fn push_log(state: &SharedState, msg: &str) {
    eprintln!("[RN2C] {}", msg);
    state.lock().unwrap().logs.push(msg.to_string());
}

#[tauri::command]
fn get_onion_url() -> &'static str {
    #[cfg(target_os = "android")]
    return LOCAL_PROXY_URL;
    #[cfg(not(target_os = "android"))]
    return ONION_URL;
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
fn get_log(state: tauri::State<'_, SharedState>) -> Vec<String> {
    state.lock().unwrap().logs.clone()
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[allow(unused_unsafe)]
    unsafe {
        std::env::set_var("ALL_PROXY", "socks5h://127.0.0.1:19150");
        std::env::set_var("all_proxy", "socks5h://127.0.0.1:19150");
        std::env::set_var("NO_PROXY", "localhost,127.0.0.1");
        #[cfg(target_os = "android")]
        std::env::set_var("ARTI_FS_DISABLE_PERMISSION_CHECKS", "true");
    }

    let shared: SharedState = Arc::new(Mutex::new(AppState {
        tor_event: None,
        frontend_ready: false,
        logs: Vec::new(),
    }));

    tauri::Builder::default()
        .manage(shared.clone())
        .setup(move |app| {
            let handle = app.handle().clone();
            let state = shared.clone();

            tauri::async_runtime::spawn(async move {
                push_log(&state, "Démarrage d'Arti…");

                let pending = TorEvent {
                    ready: false,
                    message: "Connexion au réseau Tor…".to_string(),
                };
                emit_or_store(&handle, &state, pending);

                push_log(&state, "Bootstrap Tor en cours (peut prendre ~15s)…");

                let data_dir = handle.path().app_data_dir().expect("app_data_dir");
                match tor_proxy::bootstrap(data_dir).await {
                    Ok(tor_client) => {
                        push_log(&state, "Tor bootstrappé — stabilisation des circuits…");
                        tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;

                        let ev = TorEvent {
                            ready: true,
                            message: "Tor connecté".to_string(),
                        };
                        emit_or_store(&handle, &state, ev);
                        push_log(&state, "Ouverture de la fenêtre RN2C…");

                        // Android : reverse proxy HTTP local (proxy_url non supporté)
                        // Desktop : proxy SOCKS5 + proxy_url sur la webview
                        #[cfg(target_os = "android")]
                        {
                            // Sur Android : la splash navigue via get_onion_url() → 127.0.0.1:8181
                            // Pas de deuxième fenêtre — on lance juste le reverse proxy
                            push_log(&state, "Reverse proxy HTTP actif sur 127.0.0.1:8181");
                            if let Err(e) = tor_proxy::run_http_reverse_proxy(
                                tor_client, ONION_HOST, 80, 8181,
                            ).await {
                                push_log(&state, &format!("Proxy arrêté : {}", e));
                            }
                        }

                        #[cfg(not(target_os = "android"))]
                        {
                            let builder = tauri::WebviewWindowBuilder::new(
                                &handle,
                                "rn2c",
                                tauri::WebviewUrl::External(ONION_URL.parse().unwrap()),
                            )
                            .title("RN2C")
                            .proxy_url("socks5://127.0.0.1:19150".parse().unwrap());

                            #[cfg(desktop)]
                            let builder = builder.inner_size(1280.0, 820.0).center();

                            if let Ok(_w) = builder.build() {}

                            #[cfg(desktop)]
                            if let Some(splash) = handle.get_webview_window("main") {
                                let _ = splash.close();
                            }

                            push_log(&state, "Proxy SOCKS5 actif sur 127.0.0.1:19150");
                            if let Err(e) = tor_proxy::run_proxy(tor_client, 19150).await {
                                push_log(&state, &format!("Proxy arrêté : {}", e));
                            }
                        }
                    }
                    Err(e) => {
                        let msg = format!("Erreur Tor : {}", e);
                        push_log(&state, &msg);
                        let ev = TorEvent {
                            ready: false,
                            message: msg,
                        };
                        emit_or_store(&handle, &state, ev);
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_onion_url,
            get_tor_status,
            get_log,
            frontend_ready
        ])
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
