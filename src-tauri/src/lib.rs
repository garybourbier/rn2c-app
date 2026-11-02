mod tor_proxy;

use std::sync::{Arc, Mutex};
use tauri::{Emitter, Manager};

const ONION_URL: &str =
    "http://4xg4ryjrs64xd7kljwj7pryy7ci4zyu2hljpfq4gqj2xp4brjatu2rid.onion/";
const ONION_HOST: &str =
    "4xg4ryjrs64xd7kljwj7pryy7ci4zyu2hljpfq4gqj2xp4brjatu2rid.onion";
const LOCAL_PROXY_URL: &str = "http://127.0.0.1:8181/";

const LATEST_JSON_URL: &str =
    "https://raw.githubusercontent.com/garybourbier/rn2c-app/refs/heads/master/releases/latest.json";

#[derive(Clone, serde::Serialize)]
struct TorEvent {
    ready: bool,
    message: String,
}

#[derive(Clone, serde::Serialize)]
struct UpdateInfo {
    version: String,
    notes: String,
    downloads: serde_json::Value,
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
    LOCAL_PROXY_URL
}

#[tauri::command]
fn get_app_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
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

#[tauri::command]
async fn check_update() -> Option<UpdateInfo> {
    if cfg!(target_os = "android") {
        return None;
    }
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .ok()?;
    let resp = client.get(LATEST_JSON_URL).send().await.ok()?;
    if !resp.status().is_success() {
        return None;
    }
    let info: serde_json::Value = resp.json().await.ok()?;
    let latest = info["version"].as_str()?;
    if is_newer_version(latest, env!("CARGO_PKG_VERSION")) {
        Some(UpdateInfo {
            version: latest.to_string(),
            notes: info["notes"].as_str().unwrap_or("").to_string(),
            downloads: info["downloads"].clone(),
        })
    } else {
        None
    }
}

/// Trois nombres en chiffres ASCII, rien d'autre : « 1.x.0 », « v0.8.2 » ou « +1.0.0 » ne sont pas
/// des versions, et l'écran refuserait leurs liens.
fn version(v: &str) -> Option<(u32, u32, u32)> {
    let mut parties = v.split('.').map(|s| {
        if !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()) { s.parse::<u32>().ok() } else { None }
    });
    let v = (parties.next()??, parties.next()??, parties.next()??);
    if parties.next().is_some() { None } else { Some(v) }
}

fn is_newer_version(latest: &str, current: &str) -> bool {
    match (version(latest), version(current)) {
        (Some(l), Some(c)) => l > c,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::is_newer_version;

    #[test]
    fn plus_recente() {
        assert!(is_newer_version("0.8.2", "0.8.1"));
        assert!(is_newer_version("0.10.0", "0.9.9"));
        assert!(is_newer_version("1.0.0", "0.255.999"));
    }

    #[test]
    fn pas_plus_recente() {
        for v in ["0.8.1", "0.8.0", "0.7.99"] {
            assert!(!is_newer_version(v, "0.8.1"), "{v}");
        }
    }

    #[test]
    fn hors_forme() {
        for v in ["1.x.0", " 0.8.2", "v0.8.2", "0.x.9", "+1.0.0", "1.0", "1.0.0.0", "1.0.0-rc1",
                  "4294967296.0.0", "٠.٨.٢", "abc", "", "1..0", "1.0."] {
            assert!(!is_newer_version(v, "0.8.1"), "{v}");
        }
    }
}

#[tauri::command]
fn open_rn2c_window(app: tauri::AppHandle) {
    #[cfg(not(target_os = "android"))]
    {
        let builder = tauri::WebviewWindowBuilder::new(
            &app,
            "rn2c",
            tauri::WebviewUrl::External(LOCAL_PROXY_URL.parse().unwrap()),
        )
        .title("RN2C");

        #[cfg(desktop)]
        let builder = builder.inner_size(1280.0, 820.0).center();

        if let Ok(_w) = builder.build() {}

        #[cfg(desktop)]
        if let Some(splash) = app.get_webview_window("main") {
            let _ = splash.close();
        }
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

                        // Proxy HTTP local sur 127.0.0.1:8181 (contexte sécurisé → getUserMedia OK)
                        {
                            let tc = tor_client.clone();
                            tauri::async_runtime::spawn(async move {
                                if let Err(e) = tor_proxy::run_http_reverse_proxy(
                                    tc, ONION_HOST, 80, 8181,
                                ).await {
                                    eprintln!("[Tor] proxy HTTP arrêté : {}", e);
                                }
                            });
                        }
                        // Proxy SOCKS5 pour les requêtes Rust (check_update, etc.)
                        #[cfg(not(target_os = "android"))]
                        {
                            let tc = tor_client.clone();
                            tauri::async_runtime::spawn(async move {
                                if let Err(e) = tor_proxy::run_proxy(tc, 19150).await {
                                    eprintln!("[Tor] proxy SOCKS5 arrêté : {}", e);
                                }
                            });
                        }

                        // Laisse le proxy binder avant de notifier le frontend
                        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

                        let ev = TorEvent {
                            ready: true,
                            message: "Tor connecté".to_string(),
                        };
                        emit_or_store(&handle, &state, ev);
                        push_log(&state, "Proxy actif — en attente de l'interface…");
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
            get_app_version,
            get_tor_status,
            get_log,
            frontend_ready,
            check_update,
            open_rn2c_window,
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
