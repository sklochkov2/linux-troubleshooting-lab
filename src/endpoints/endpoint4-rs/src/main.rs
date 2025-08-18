use std::env;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const ACCEPT_RESERVE: usize = 1; // leave 1 spare FD so accept() never EMFILEs
const HANDLER_GUARDS: usize = 8; // max guards per request; raising NOFILE will surpass this

fn env_or(k: &str, d: &str) -> String {
    env::var(k).unwrap_or_else(|_| d.to_string())
}

fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis()
}

fn log_stderr(msg: &str) {
    let _ = writeln!(&mut std::io::stderr(), "{}", msg);
}

#[cfg(target_os = "linux")]
fn current_nofile_soft() -> u64 {
    let mut rlim = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    unsafe {
        if libc::getrlimit(libc::RLIMIT_NOFILE, &mut rlim) == 0 {
            rlim.rlim_cur as u64
        } else {
            1024
        }
    }
}

/// Pre-open files up to EMFILE, then free `reserve_total` handles.
/// We keep the remaining FDs held alive by leaking the Vec.
fn saturate_fds(stress_dir: &PathBuf, reserve_total: usize) {
    std::fs::create_dir_all(stress_dir).ok();
    let mut held: Vec<File> = Vec::new();
    let mut opened = 0usize;

    loop {
        let p = stress_dir.join(format!("fill-{}.bin", opened));
        match OpenOptions::new().create(true).append(true).open(&p) {
            Ok(f) => {
                let _ = f.as_raw_fd();
                held.push(f);
                opened += 1;
                if opened % 32 == 0 {
                    log_stderr(&format!("[endpoint4] pre-opened {} files...", opened));
                }
                if opened > 800 {
                    break;
                }
            }
            Err(e) => {
                log_stderr(&format!(
                    "[endpoint4] hit EMFILE boundary (expected): {}",
                    e
                ));
                break;
            }
        }
    }

    for _ in 0..reserve_total {
        if let Some(f) = held.pop() {
            drop(f);
        }
    }

    log_stderr(&format!(
        "[endpoint4] RLIMIT_NOFILE soft={} held_after_reserve={} (reserve_total=ACCEPT:{} + GUARDS:{})",
        current_nofile_soft(),
        held.len(),
        ACCEPT_RESERVE, HANDLER_GUARDS
    ));

    // keep the baseline pressure alive
    std::mem::forget(held);
}

fn read_request(stream: &mut TcpStream) -> String {
    stream
        .set_read_timeout(Some(std::time::Duration::from_millis(100)))
        .ok();
    let mut buf = [0u8; 2048];
    let n = stream.read(&mut buf).unwrap_or(0);
    String::from_utf8_lossy(&buf[..n]).into_owned()
}

fn write_response(stream: &mut TcpStream, status: &str, body: &str) {
    let resp = format!(
        "HTTP/1.0 {}\r\nServer: lab-endpoint4\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        status, body.len(), body
    );
    let _ = stream.write_all(resp.as_bytes());
    let _ = stream.flush();
}

fn handle_conn(mut stream: TcpStream, stress_dir: &PathBuf) {
    let req = read_request(&mut stream);
    let first_line = req.lines().next().unwrap_or_default();
    let path = first_line.split_whitespace().nth(1).unwrap_or("/");

    if path == "/health" || path.starts_with("/health?") {
        write_response(
            &mut stream,
            "200 OK",
            r#"{"service":"endpoint4","ok":true}"#,
        );
        return;
    }

    // Guard: consume up to HANDLER_GUARDS spare FDs (bounded; we don't eat new headroom forever).
    let mut guards: Vec<File> = Vec::new();
    for _ in 0..HANDLER_GUARDS {
        match OpenOptions::new().read(true).open("/dev/null") {
            Ok(f) => {
                let _ = f.as_raw_fd();
                guards.push(f);
            }
            Err(_) => break,
        }
    }

    // Try to open a per-request file: with the original low limit this should EMFILE;
    // after raising limits, there will be extra headroom and this will succeed.
    let fname = stress_dir.join(format!("req-{}.bin", now_ms()));
    match OpenOptions::new()
        .create_new(true)
        .append(true)
        .open(&fname)
    {
        Ok(mut f) => {
            let _ = writeln!(f, "ok {}", now_ms());
            write_response(
                &mut stream,
                "200 OK",
                r#"{"service":"endpoint4","ok":true}"#,
            );
        }
        Err(e) => {
            log_stderr(&format!(
                "[endpoint4] open failed (expected EMFILE under low limit): {} → {}",
                fname.display(),
                e
            ));
            write_response(
                &mut stream,
                "503 Service Unavailable",
                r#"{"service":"endpoint4","ok":false,"error":"EMFILE_TOO_MANY_OPEN_FILES"}"#,
            );
        }
    }

    drop(guards); // restore baseline so next accept() still has ACCEPT_RESERVE space
}

fn main() {
    let port = env_or("PORT", "9004");
    let stress_dir = PathBuf::from(env_or("STRESS_DIR", "/var/lib/endpoint4/stress"));

    // Bind first so the listener FD is allocated before we apply pressure
    let addr = format!("127.0.0.1:{}", port);
    let listener = TcpListener::bind(&addr).expect("bind failed");
    log_stderr(&format!(
        "[endpoint4] listening on {}, stress_dir={}",
        addr,
        stress_dir.display()
    ));

    // Leave ACCEPT_RESERVE + HANDLER_GUARDS spare slots.
    saturate_fds(&stress_dir, ACCEPT_RESERVE + HANDLER_GUARDS);

    for conn in listener.incoming() {
        match conn {
            Ok(stream) => handle_conn(stream, &stress_dir),
            Err(e) => {
                log_stderr(&format!("[endpoint4] accept error: {}", e));
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
        }
    }
}
