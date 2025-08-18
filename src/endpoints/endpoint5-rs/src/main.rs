use std::env;
use std::fs::read_to_string;
use std::io::Write;
use tiny_http::{Header, Response, Server, StatusCode};

fn env_or(k: &str, d: &str) -> String {
    env::var(k).unwrap_or_else(|_| d.to_string())
}
fn json_header() -> Header {
    "Content-Type: application/json".parse::<Header>().unwrap()
}
fn log_stderr(msg: &str) {
    let _ = writeln!(&mut std::io::stderr(), "{}", msg);
}

fn main() {
    let port = env_or("PORT", "9005");
    let conf = env_or("CONF_PATH", "/etc/endpoint5/config.json");
    let addr = format!("127.0.0.1:{}", port);
    let server = Server::http(&addr).expect("bind failed");
    log_stderr(&format!("[endpoint5] listening on {}, conf={}", addr, conf));

    for req in server.incoming_requests() {
        let url = req.url().to_string();
        if url == "/health" || url.starts_with("/health?") {
            let _ = req.respond(
                Response::from_string(r#"{"service":"endpoint5","ok":true}"#)
                    .with_status_code(StatusCode(200))
                    .with_header(json_header()),
            );
            continue;
        }

        match read_to_string(&conf) {
            Ok(body) => {
                let payload = format!(
                    r#"{{"service":"endpoint5","ok":true,"config_len":{}}}"#,
                    body.len()
                );
                let _ = req.respond(
                    Response::from_string(payload)
                        .with_status_code(StatusCode(200))
                        .with_header(json_header()),
                );
            }
            Err(e) => {
                log_stderr(&format!("[endpoint5] failed to read {}: {}", conf, e));
                let _ = req.respond(
                    Response::from_string(
                        r#"{"service":"endpoint5","ok":false,"error":"CONFIG_READ_FAILED"}"#,
                    )
                    .with_status_code(StatusCode(500))
                    .with_header(json_header()),
                );
            }
        }
    }
}
