use arti_client::{TorClient, TorClientConfig};
use arti_client::config::CfgPath;
use tor_rtcompat::PreferredRuntime;
use tokio::net::{TcpListener, TcpStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::{Result, bail, ensure};

pub async fn bootstrap(data_dir: std::path::PathBuf) -> Result<TorClient<PreferredRuntime>> {
    let mut builder = TorClientConfig::builder();
    builder.storage().state_dir(CfgPath::new_literal(data_dir.join("tor-state")));
    builder.storage().cache_dir(CfgPath::new_literal(data_dir.join("tor-cache")));
    let config = builder.build()?;
    let tor = TorClient::<PreferredRuntime>::create_bootstrapped(config).await?;
    Ok(tor)
}

pub async fn run_proxy(tor: TorClient<PreferredRuntime>, port: u16) -> Result<()> {
    let listener = TcpListener::bind(("127.0.0.1", port)).await?;
    eprintln!("[Tor] proxy SOCKS5 actif sur 127.0.0.1:{}", port);
    loop {
        let (conn, _) = listener.accept().await?;
        let tor = tor.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_socks5(conn, tor).await {
                eprintln!("[Tor] {}", e);
            }
        });
    }
}

async fn handle_socks5(mut conn: TcpStream, tor: TorClient<PreferredRuntime>) -> Result<()> {
    // Négociation auth
    let mut buf = [0u8; 2];
    conn.read_exact(&mut buf).await?;
    bail_if!(buf[0] != 5, "pas SOCKS5");
    let mut methods = vec![0u8; buf[1] as usize];
    conn.read_exact(&mut methods).await?;
    conn.write_all(&[5, 0]).await?; // pas d'auth

    // Requête CONNECT
    let mut hdr = [0u8; 4];
    conn.read_exact(&mut hdr).await?;
    ensure!(hdr[1] == 1, "seul CONNECT est supporté");

    let (host, port) = match hdr[3] {
        1 => {
            let mut ip = [0u8; 4];
            conn.read_exact(&mut ip).await?;
            let mut p = [0u8; 2];
            conn.read_exact(&mut p).await?;
            (format!("{}.{}.{}.{}", ip[0], ip[1], ip[2], ip[3]), u16::from_be_bytes(p))
        }
        3 => {
            let mut len = [0u8; 1];
            conn.read_exact(&mut len).await?;
            let mut domain = vec![0u8; len[0] as usize];
            conn.read_exact(&mut domain).await?;
            let mut p = [0u8; 2];
            conn.read_exact(&mut p).await?;
            (String::from_utf8(domain)?, u16::from_be_bytes(p))
        }
        _ => bail!("type d'adresse non supporté"),
    };

    eprintln!("[Tor] CONNECT {}:{}", host, port);

    let mut last_err = String::new();
    for attempt in 0..4u8 {
        if attempt > 0 {
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            eprintln!("[Tor] retry {}/3 {}:{}", attempt, host, port);
        }
        match tor.connect((host.as_str(), port)).await {
            Ok(mut tor_stream) => {
                conn.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
                tokio::io::copy_bidirectional(&mut conn, &mut tor_stream).await.ok();
                return Ok(());
            }
            Err(e) => { last_err = e.to_string(); }
        }
    }
    conn.write_all(&[5, 4, 0, 1, 0, 0, 0, 0, 0, 0]).await.ok();
    bail!("Tor connect {}:{} — {}", host, port, last_err)
}

// Reverse proxy HTTP local (Android : proxy_url non supporté ; Desktop : contexte sécurisé requis pour getUserMedia)
pub async fn run_http_reverse_proxy(
    tor: TorClient<PreferredRuntime>,
    onion_host: &'static str,
    onion_port: u16,
    listen_port: u16,
) -> Result<()> {
    let listener = TcpListener::bind(("127.0.0.1", listen_port)).await?;
    eprintln!("[HTTP] reverse proxy actif sur 127.0.0.1:{}", listen_port);
    loop {
        let (conn, _) = listener.accept().await?;
        let tor = tor.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_http_reverse(conn, tor, onion_host, onion_port).await {
                eprintln!("[HTTP] {}", e);
            }
        });
    }
}

async fn handle_http_reverse(
    mut client: TcpStream,
    tor: TorClient<PreferredRuntime>,
    onion_host: &str,
    onion_port: u16,
) -> Result<()> {
    eprintln!("[HTTP] nouvelle connexion entrante");
    // Lit les headers jusqu'à \r\n\r\n
    let mut header_buf: Vec<u8> = Vec::with_capacity(4096);
    let mut byte = [0u8; 1];
    loop {
        client.read_exact(&mut byte).await?;
        header_buf.push(byte[0]);
        if header_buf.ends_with(b"\r\n\r\n") { break; }
        if header_buf.len() > 65536 { bail!("headers trop longs"); }
    }

    let header_str = String::from_utf8_lossy(&header_buf);
    let mut lines = header_str.lines();

    let request_line = lines.next().unwrap_or("");
    let mut parts = request_line.splitn(3, ' ');
    let method  = parts.next().unwrap_or("GET").to_string();
    let url     = parts.next().unwrap_or("/").to_string();
    let version = parts.next().unwrap_or("HTTP/1.1").to_string();

    // Extrait le chemin depuis l'URL absolue ou relative
    let path = if url.starts_with("http://") || url.starts_with("https://") {
        let without_scheme = url.splitn(2, "://").nth(1).unwrap_or("");
        let path_start = without_scheme.find('/').unwrap_or(without_scheme.len());
        let p = &without_scheme[path_start..];
        if p.is_empty() { "/".to_string() } else { p.to_string() }
    } else {
        url.clone()
    };

    // Reconstruit les headers en fixant Host
    let mut new_request = format!("{} {} {}\r\n", method, path, version);
    let mut host_written = false;
    for line in lines {
        if line.is_empty() { continue; }
        if line.to_ascii_lowercase().starts_with("host:") {
            new_request.push_str(&format!("Host: {}\r\n", onion_host));
            host_written = true;
        } else {
            new_request.push_str(line);
            new_request.push_str("\r\n");
        }
    }
    if !host_written {
        new_request.push_str(&format!("Host: {}\r\n", onion_host));
    }
    new_request.push_str("\r\n");

    eprintln!("[HTTP] → {} {} → {}:{}", method, path, onion_host, onion_port);
    eprintln!("[HTTP] requête reconstituée:\n{}", new_request.trim_end());

    // Timeout : le circuit .onion peut prendre 20-40s la première fois
    // Si trop long, on sert une page de chargement et le WebView re-essaie (meta refresh)
    let connect = tokio::time::timeout(
        tokio::time::Duration::from_secs(20),
        tor.connect((onion_host, onion_port)),
    ).await;

    match connect {
        Ok(Ok(mut onion)) => {
            eprintln!("[HTTP] .onion connecté — envoi requête ({} bytes)", new_request.len());
            // Timeout global sur write+read : latence .onion résidentiel peut atteindre 60s
            let req_bytes = new_request.into_bytes();
            let mut first = [0u8; 512];
            let result = tokio::time::timeout(
                tokio::time::Duration::from_secs(90),
                async {
                    onion.write_all(&req_bytes).await?;
                    onion.flush().await?;
                    eprintln!("[HTTP] requête envoyée, attente réponse…");
                    let n = onion.read(&mut first).await?;
                    Ok::<usize, std::io::Error>(n)
                },
            ).await;

            match result {
                Ok(Ok(0)) => {
                    eprintln!("[HTTP] serveur fermé sans réponse (0 bytes)");
                    send_loading_page(&mut client).await.ok();
                }
                Ok(Ok(n)) => {
                    eprintln!("[HTTP] réponse reçue ({} bytes) : {:?}",
                        n, String::from_utf8_lossy(&first[..n.min(200)]));
                    client.write_all(&first[..n]).await.ok();
                    tokio::io::copy_bidirectional(&mut client, &mut onion).await.ok();
                    eprintln!("[HTTP] pipe terminé");
                }
                Ok(Err(e)) => {
                    eprintln!("[HTTP] erreur I/O : {}", e);
                    send_loading_page(&mut client).await.ok();
                }
                Err(_) => {
                    eprintln!("[HTTP] timeout global (90s) — page de chargement");
                    send_loading_page(&mut client).await.ok();
                }
            }
        }
        Ok(Err(e)) => {
            eprintln!("[HTTP] Tor erreur : {}", e);
            send_loading_page(&mut client).await.ok();
        }
        Err(_) => {
            eprintln!("[HTTP] timeout connexion — page de chargement");
            send_loading_page(&mut client).await.ok();
        }
    }
    Ok(())
}

async fn send_loading_page(client: &mut TcpStream) -> Result<()> {
    let body = r#"<!DOCTYPE html><html lang="fr"><head>
<meta charset="UTF-8"><meta http-equiv="refresh" content="20">
<style>*{margin:0;padding:0;box-sizing:border-box}
body{background:#0a0a0a;color:#1aff1a;font-family:'Courier New',monospace;height:100vh;
display:flex;flex-direction:column;align-items:center;justify-content:center;gap:20px}
.logo{font-size:3rem;font-weight:bold;letter-spacing:.3em;text-shadow:0 0 20px #1aff1a66}
.sub{font-size:.75rem;letter-spacing:.2em;color:#0d5c0d;text-transform:uppercase}
.msg{font-size:.85rem;color:#1aff1a99}
.bar{width:280px;height:2px;background:#111;border:1px solid #1a7a1a33;overflow:hidden}
.fill{height:100%;background:#1aff1a;box-shadow:0 0 8px #1aff1a;animation:s 1.5s ease-in-out infinite}
@keyframes s{0%{width:0%;margin-left:0%}50%{width:40%;margin-left:30%}100%{width:0%;margin-left:100%}}
</style></head><body>
<div class="logo">RN2C</div>
<div class="sub">Radio Noise To Come</div>
<div class="msg">Connexion au réseau Tor…</div>
<div class="bar"><div class="fill"></div></div>
</body></html>"#;
    let resp = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(), body
    );
    client.write_all(resp.as_bytes()).await?;
    Ok(())
}

macro_rules! bail_if {
    ($cond:expr, $msg:literal) => {
        if $cond { bail!($msg); }
    };
}
use bail_if;
