use std::env;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};
use tiny_http::{Header, Request, Response, Server, StatusCode};

fn env_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

fn write_devnull(msg: &str) {
    if let Ok(mut devnull) = OpenOptions::new().write(true).open("/dev/null") {
        let _ = writeln!(devnull, "{}", msg);
    }
}

fn json_header() -> Header {
    "Content-Type: application/json".parse::<Header>().unwrap()
}

fn now_rfc3339() -> String {
    // avoid pulling chrono: simple RFC3339-ish timestamp
    let ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis();
    format!("{}ms_since_epoch", ms)
}

fn handle_req(req: Request, lock_path: &str) {
    let url = req.url().to_string();

    // Health is always OK
    if url == "/health" || url.starts_with("/health?") {
        let body = r#"{"service":"endpoint3","ok":true}"#;
        let _ = req.respond(
            Response::from_string(body)
                .with_status_code(StatusCode(200))
                .with_header(json_header()),
        );
        return;
    }

    // "Maintenance" lock: if present, fail the request and write reason to /dev/null
    // Intentionally open() instead of just metadata() so strace clearly shows the access.
    match File::open(lock_path) {
        Ok(_) => {
            write_devnull(&format!(
                "{} LOCK PRESENT at {} -> refusing request to {}",
                now_rfc3339(),
                lock_path,
                url
            ));
            let body = r#"{"service":"endpoint3","ok":false,"error":"MAINTENANCE"}"#;
            let _ = req.respond(
                Response::from_string(body)
                    .with_status_code(StatusCode(503)) // Service Unavailable
                    .with_header(json_header()),
            );
            return;
        }
        Err(_) => {
            // No lock → normal response (keep it simple)
            let body = r#"{"service":"endpoint3","ok":true}"#;
            let _ = req.respond(
                Response::from_string(body)
                    .with_status_code(StatusCode(200))
                    .with_header(json_header()),
            );
        }
    }
}

fn main() {
    let port = env_or("PORT", "9907");
    // default lock file location (doesn't rely on env, but supports one if set)
    let lock_path = env_or("LOCK_FILE", "/var/lib/endpoint3/maintenance.lock");

    let addr = format!("127.0.0.1:{}", port);
    let server = Server::http(&addr).expect("bind failed");

    // Write startup note to /dev/null so journalctl remains quiet by design
    write_devnull(&format!(
        "endpoint3 starting on {} with lock file {}",
        addr, lock_path
    ));

    for req in server.incoming_requests() {
        handle_req(req, &lock_path);
    }
}
