use std::env;
use std::fs::{create_dir_all, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};
use tiny_http::{Header, Request, Response, Server, StatusCode};

static COUNTER: AtomicU64 = AtomicU64::new(0);

fn env_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}
fn now_ms() -> u128 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis()
}
fn write_devnull(msg: &str) {
    if let Ok(mut devnull) = OpenOptions::new().write(true).open("/dev/null") {
        let _ = writeln!(devnull, "{}", msg);
    }
}

fn json_header() -> Header {
    "Content-Type: application/json".parse::<Header>().unwrap()
}

fn handle_req(req: Request, logdir: &PathBuf) {
    let url = req.url().to_string();

    if url == "/health" || url.starts_with("/health?") {
        let body = r#"{"service":"endpoint2","ok":true}"#;
        let _ = req.respond(
            Response::from_string(body)
                .with_status_code(StatusCode(200))
                .with_header(json_header()),
        );
        return;
    }

    let logs_dir = logdir.join("logs");
    if let Err(e) = create_dir_all(&logs_dir) {
        write_devnull(&format!("create_dir_all failed: {}", e));
        let body = r#"{"service":"endpoint2","ok":false,"error":"WRITE_FAILED"}"#;
        let _ = req.respond(
            Response::from_string(body)
                .with_status_code(StatusCode(500))
                .with_header(json_header()),
        );
        return;
    }

    let c = COUNTER.fetch_add(1, Ordering::Relaxed);
    let filename = format!("req-{}-{}.log", now_ms(), c);
    let path = logs_dir.join(filename);

    match OpenOptions::new().create_new(true).write(true).open(&path) {
        Ok(mut f) => {
            let _ = writeln!(f, "path={} time_ms={}", url, now_ms());
            let body = format!(
                r#"{{"service":"endpoint2","ok":true,"logged":"{}"}}"#,
                path.display()
            );
            let _ = req.respond(
                Response::from_string(body)
                    .with_status_code(StatusCode(200))
                    .with_header(json_header()),
            );
        }
        Err(e) => {
            write_devnull(&format!("open log file failed at {}: {}", path.display(), e));
            let body = r#"{"service":"endpoint2","ok":false,"error":"WRITE_FAILED"}"#;
            let _ = req.respond(
                Response::from_string(body)
                    .with_status_code(StatusCode(500))
                    .with_header(json_header()),
            );
        }
    }
}

fn main() {
    let port = env_or("PORT", "9002");
    let log_dir = PathBuf::from(env_or("LOG_DIR", "/var/log/endpoint2"));
    let addr = format!("127.0.0.1:{}", port);
    let server = Server::http(&addr).expect("bind failed");
    write_devnull(&format!("endpoint2 starting on {}", addr));

    for req in server.incoming_requests() {
        handle_req(req, &log_dir);
    }
}

