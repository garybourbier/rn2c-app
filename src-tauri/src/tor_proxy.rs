use arti_client::{TorClient, TorClientConfig};
use tor_rtcompat::PreferredRuntime;
use tokio::net::{TcpListener, TcpStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::{Result, bail, ensure};

pub async fn bootstrap() -> Result<TorClient<PreferredRuntime>> {
    let config = TorClientConfig::default();
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

macro_rules! bail_if {
    ($cond:expr, $msg:literal) => {
        if $cond { bail!($msg); }
    };
}
use bail_if;
