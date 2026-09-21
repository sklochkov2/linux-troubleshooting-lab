# JSLinux browser lab user and deployment guide

This directory builds and deploys the browser-hosted version of the Linux
troubleshooting lab. The result is a static website: the x86_64 emulator, Linux
kernel, guest disk, terminal, and challenge status UI all run in the
participant's browser. No per-participant VM or application backend is needed.

The shared image contains four selectable challenges. Each challenge URL boots
one active scenario, while the table of contents stays spoiler-free. The
browser implementation is independent of the AWS/Packer/Salt deployment.

## Support status and release gate

The implementation uses:

- Bellard's March 2026 precompiled JSLinux x86_64 runtime;
- Bellard's Linux 6.19.3 x86_64 kernel;
- a reproducibly generated Buildroot x86_64/musl filesystem;
- a block-backed ext2 guest disk;
- a browser-rendered status indicator driven by an in-guest HTTP probe.

The x86_64 runtime and kernel are publicly downloadable and pinned by SHA-256,
but a corresponding source release and explicit redistribution terms were not
identified. Building and privately testing the prototype is supported by this
guide. Obtain clarification or permission from the author before publishing
the generated site to external users.

The first image uses musl. Buildroot glibc 2.41 rejected the CPU ISA level
advertised by the emulator before starting `init`. Do not assume that arbitrary
precompiled glibc-only software will run until an older or specially configured
glibc image has been validated.

## End-to-end workflow

For a normal challenge update:

1. Edit the service, guest overlay, package list, or page.
2. Run `make jslinux-image`.
3. Start the local static server with `make jslinux-serve`.
4. Perform the broken, repaired, and reset acceptance checks.
5. Review licensing output when dependencies changed.
6. Copy `jslinux/dist/` to a versioned directory on the web server.
7. Atomically switch the web server's `current` symlink.
8. Verify the deployed site and retain the previous release for rollback.

If only deployment configuration changed and `jslinux/dist/` already contains
the approved build, rebuilding the image is unnecessary.

## Prerequisites

Build host:

- Linux on x86_64;
- Docker with permission to run containers;
- GNU Make;
- Python 3 for the local development server;
- approximately 15 GB of free disk space for Buildroot sources, toolchains,
  intermediate files, and Docker layers;
- network access to `buildroot.org` and `bellard.org` during the first build.

Deployment host:

- any static HTTP server;
- HTTPS for participant-facing deployments;
- the ability to serve `.wasm` as `application/wasm`;
- enough storage for the generated `dist/` directory, currently approximately
  214 MB.

The guest disk is split into 256 KiB chunks. Browsers load chunks on demand, so
the initial transfer is smaller than the complete distribution size.

## Repository layout

```text
jslinux/
├── buildroot/
│   ├── board/lab/rootfs-overlay/
│   │   ├── etc/init.d/            # guest startup scripts
│   │   ├── etc/nginx/             # guest Nginx configuration
│   │   ├── etc/init.d/            # scenario selector and guest services
│   │   └── usr/sbin/              # status and scheduled guest scripts
│   ├── configs/
│   │   └── lab_x86_64_defconfig   # architecture, tools, and packages
│   └── package/
│       ├── endpoint3-js/          # challenge 3 service
│       └── lab-endpoints/         # challenge 1, 2, and 4 services
├── docker/
│   └── Dockerfile                 # reproducible build environment
├── scripts/
│   ├── build-in-container.sh      # complete image assembly
│   └── serve.sh                   # local static server
├── web/
│   ├── index.html
│   ├── challenge.html
│   ├── boot-config.js
│   ├── lab-ui.js
│   └── lab.css
├── Makefile
└── versions.env                   # pinned upstream versions and hashes
```

Generated and ignored directories:

```text
jslinux/build/   # downloads, sources, toolchain, and Buildroot output
jslinux/dist/    # deployable static website
```

## Updating the challenges

### Change the endpoint implementation

The guest-native C services live in:

```text
jslinux/buildroot/package/lab-endpoints/src/endpoint1.c
jslinux/buildroot/package/lab-endpoints/src/endpoint2.c
jslinux/buildroot/package/endpoint3-js/src/server.c
jslinux/buildroot/package/lab-endpoints/src/endpoint4.c
```

The build script invalidates both local Buildroot packages on every image
build, so `make jslinux-image` recompiles these sources. The resulting x86_64
musl binaries are installed under `/usr/sbin/`.

Services must remain in the foreground. The scenario init script handles
selection, backgrounding, users, resource limits, and PID files.

### Change the initial broken state

The initial state comes from the root filesystem overlay:

```text
jslinux/buildroot/board/lab/rootfs-overlay/
```

Files placed there are copied into the guest image. Additional initial faults
are applied by the selected branch of:

```text
etc/init.d/S35lab-scenario
```

Changing or removing an overlay file requires rebuilding the image. A browser
refresh cannot update a previously built image; it only resets the running VM
to the state contained in that image.

### Change service startup

Edit:

```text
etc/init.d/S35lab-scenario
etc/init.d/S60lab-status
usr/sbin/lab-status-reporter
```

within the root filesystem overlay.

Startup scripts must be executable. Preserve executable mode when adding them
to Git:

```bash
chmod +x jslinux/buildroot/board/lab/rootfs-overlay/etc/init.d/S*
chmod +x jslinux/buildroot/board/lab/rootfs-overlay/usr/sbin/lab-status-reporter
```

Buildroot runs the `S*` scripts in lexical order. The status reporter may start
before Nginx is fully ready because it continuously retries.

### Add guest packages or diagnostic tools

Edit:

```text
jslinux/buildroot/configs/lab_x86_64_defconfig
```

Package options use Buildroot symbols such as:

```text
BR2_PACKAGE_STRACE=y
BR2_PACKAGE_NGINX=y
```

Use the pinned Buildroot release's configuration names. After changing the
configuration, run the normal image build. Use a clean build if changing the C
library, architecture, or toolchain options.

The current image includes:

- `strace` and `lsof`;
- `ps`, `top`, and other procps tools;
- `ss` and other iproute2 tools;
- `curl` and BusyBox `wget`;
- `file`, `find`, `grep`, `sed`, `less`, `nano`, and Bash;
- Nginx.

### Change guest Nginx routing

Edit:

```text
jslinux/buildroot/board/lab/rootfs-overlay/etc/nginx/nginx.conf
```

This is Nginx inside the VM. It is unrelated to the outer web server that
serves the JSLinux static site.

### Change the page or status display

Edit files under:

```text
jslinux/web/
```

These files are copied directly into `dist/` on every build. The status
reporter emits a reserved OSC 777 console sequence:

```text
ESC ] 777 ; lab-status ; endpoint3 ; STATUS BEL
```

`STATUS` is `starting`, `unhealthy`, or `healthy`. `lab-ui.js` removes that
sequence before rendering terminal output and updates the indicator for the
scenario selected by `LAB_SCENARIO=endpointN`.

### Update JSLinux, the kernel, TinyEMU, or Buildroot

Pinned versions and SHA-256 hashes are stored in:

```text
jslinux/versions.env
```

Do not update a hash merely because a download changed. Confirm the upstream
release, inspect its provenance, test it separately, and then update both the
version and expected hash. Runtime or kernel upgrades require the full browser
acceptance test, including `strace`.

## Building the image

From the repository root:

```bash
make jslinux-image
```

Equivalent command:

```bash
make -C jslinux image
```

The first build:

1. builds the Docker build environment;
2. downloads and verifies pinned upstream assets;
3. builds the x86_64/musl cross-toolchain;
4. builds packages and all four endpoints;
5. creates a 192 MB ext2 filesystem;
6. splits the filesystem into HTTP-addressable chunks;
7. assembles the complete static site under `jslinux/dist/`.

The first build can take several minutes. Downloads and Buildroot outputs are
cached in `jslinux/build/`; later builds are incremental.

Each normal build forcibly recompiles both local endpoint packages and
refreshes the root filesystem overlay and web files.

### When to perform a clean build

Run a clean build after changing:

- target architecture;
- C library;
- compiler or kernel ABI assumptions;
- Buildroot version;
- fundamental toolchain settings.

Commands:

```bash
make -C jslinux clean
make jslinux-image
```

`clean` removes both `build/` and `dist/`, including downloaded archives and
the compiled cross-toolchain.

### Build output

The deployable directory contains:

```text
jslinux/dist/
├── index.html
├── challenge.html
├── boot-config.js
├── image-version-<image-version>.js
├── lab-ui.js
├── lab.css
├── jslinux.js
├── term.js
├── x86_64emu-wasm.js
├── x86_64emu-wasm.wasm
├── kernel-x86_64-lab-<image-version>.bin
├── root-x86_64-<image-version>.cfg
├── root-x86_64-<image-version>/blk.txt
├── root-x86_64-<image-version>/blk*.bin
└── build-info.txt
```

Only `dist/` is deployed. Do not expose `build/`, repository files, Docker
sockets, or build credentials through the web server.

## Running locally

Start the development server:

```bash
make jslinux-serve
```

Open:

```text
http://127.0.0.1:8000/
```

Use another port if necessary:

```bash
make -C jslinux serve PORT=8080
```

Do not open `index.html` through `file://`. Browsers require HTTP for Wasm and
guest disk requests.

Stop the server with `Ctrl+C`.

## Local acceptance test

Perform this test after changing the guest, runtime, kernel, status protocol, or
page.

1. Open the table of contents in a supported desktop Chromium or Firefox
   browser and confirm it lists challenges 1–4 without fault descriptions.
2. Open each challenge and confirm the VM starts only the selected endpoint.
3. Confirm the VM reaches `linux-lab login:` and the status becomes
   **Needs repair**.
4. Log in as `root`; the prototype has no root password.
5. Confirm the selected public in-guest path returns a non-2xx response:

   ```bash
   scenario="$(cat /var/run/lab-scenario)"
   curl -i "http://127.0.0.1/api/v1/${scenario}"
   ```

6. Confirm diagnostic tools such as `strace`, `lsof`, `ss`, and `ps` work.
7. Apply the intended repair and confirm the selected path returns HTTP 200.
8. Confirm the page indicator changes to **Working**.
9. Select **Reset challenge**.
10. Confirm the VM boots again, the path returns a non-2xx response, and the
    indicator returns to **Needs repair**.
11. Repeat the broken, repaired, and reset checks for all four challenges.
12. Check the browser developer console for Wasm, CSP, MIME, or failed-request
    errors.

The browser cannot directly request the guest's loopback or DHCP address.
Endpoint checks must run inside the guest and reach the page through the status
channel.

## Preparing a release

Record a release identifier:

```bash
release_id="$(date -u +%Y%m%dT%H%M%SZ)"
```

Optionally create a checksum manifest:

```bash
(
  cd jslinux/dist
  find . -type f -print0 \
    | sort -z \
    | xargs -0 sha256sum
) > "jslinux-dist-${release_id}.sha256"
```

Optionally package the static site:

```bash
tar -C jslinux/dist \
  -czf "jslinux-dist-${release_id}.tar.gz" \
  .
```

Keep `build-info.txt`, the checksum manifest, the Git commit ID, and the
deployment timestamp together in release records.

## Deploying with Nginx

The following layout supports atomic releases and rollback:

```text
/srv/www/linux-lab/
├── releases/
│   ├── 20260919T120000Z/
│   └── 20260920T090000Z/
└── current -> releases/20260920T090000Z
```

### 1. Install a release

On the web server:

```bash
sudo install -d -m 0755 /srv/www/linux-lab/releases
release_id="$(date -u +%Y%m%dT%H%M%SZ)"
sudo install -d -m 0755 "/srv/www/linux-lab/releases/${release_id}"
sudo rsync -a --delete \
  jslinux/dist/ \
  "/srv/www/linux-lab/releases/${release_id}/"
sudo find "/srv/www/linux-lab/releases/${release_id}" \
  -type d -exec chmod 0755 {} +
sudo find "/srv/www/linux-lab/releases/${release_id}" \
  -type f -exec chmod 0644 {} +
```

When building on a different machine, transfer the release archive or use
`rsync` over SSH:

```bash
rsync -az --delete \
  jslinux/dist/ \
  deploy@example.org:/tmp/linux-lab-release/
```

Then move it into the versioned release directory on the server.

### 2. Configure Nginx

Example dedicated HTTPS virtual host:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name lab.example.org;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name lab.example.org;

    root /srv/www/linux-lab/current;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/lab.example.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/lab.example.org/privkey.pem;

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;
    add_header Cross-Origin-Resource-Policy same-origin always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; img-src 'self' data: blob:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'self'" always;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~* \.wasm$ {
        default_type application/wasm;
        expires 1h;
        try_files $uri =404;
    }

    location ~* \.(bin|js|css)$ {
        expires 1h;
        try_files $uri =404;
    }

    location ~* \.(html|cfg|txt)$ {
        expires -1;
        try_files $uri =404;
    }

    location ~ /\. {
        deny all;
    }
}
```

The relevant requirements are:

- `.wasm` is served as `application/wasm`;
- arbitrary missing paths return 404 rather than `index.html`;
- byte-range support is not required for the split guest disk;
- all emulator and guest assets use the same origin;
- the CSP permits Wasm compilation but not arbitrary inline scripts;
- directory listing is disabled.

Stock JSLinux does not use `SharedArrayBuffer`, so COOP/COEP headers are not
required for this build.

Validate and reload Nginx:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### 3. Activate the release atomically

```bash
release_id=20260919T120000Z
sudo ln -s \
  "/srv/www/linux-lab/releases/${release_id}" \
  /srv/www/linux-lab/current.next
sudo mv -Tf \
  /srv/www/linux-lab/current.next \
  /srv/www/linux-lab/current
```

The Nginx configuration only needs reloading when its configuration changes,
not when switching the symlink.

### 4. Verify the deployed site

Check response metadata:

```bash
curl -I https://lab.example.org/
curl -I https://lab.example.org/x86_64emu-wasm.wasm
curl -I https://lab.example.org/root-x86_64-20260919-3.cfg
curl -I https://lab.example.org/root-x86_64-20260919-3/blk.txt
```

The Wasm response must include:

```text
Content-Type: application/wasm
```

Then repeat the browser acceptance test against the HTTPS URL. Test at least one
supported Chromium and Firefox release.

### 5. Roll back

Point `current` to the previous release:

```bash
previous_release=20260918T170000Z
sudo ln -s \
  "/srv/www/linux-lab/releases/${previous_release}" \
  /srv/www/linux-lab/current.next
sudo mv -Tf \
  /srv/www/linux-lab/current.next \
  /srv/www/linux-lab/current
```

Retain at least one known-good release until the new deployment passes
acceptance testing.

## Deploying to another static host

Object storage, a CDN, Apache, Caddy, and other static hosts can serve `dist/`
if they provide:

- HTTPS;
- correct MIME type for `.wasm`;
- ordinary GET requests for every file and guest disk chunk;
- no authentication redirect or HTML fallback for binary paths;
- consistent same-origin delivery or correct CORS headers;
- enough maximum-object count for the split disk chunks.

For object storage, set metadata explicitly:

```text
*.html  text/html; charset=utf-8
*.js    application/javascript
*.css   text/css
*.wasm  application/wasm
*.bin   application/octet-stream
*.cfg   text/plain; charset=utf-8
*.txt   text/plain; charset=utf-8
```

Do not publish from the Buildroot output directory. Publish only the contents
of `jslinux/dist/`.

## Caching and CDN behavior

Kernel, VM configuration, and disk paths include `LAB_IMAGE_VERSION` from
`versions.env`. Increment it whenever those assets change. HTML remains the
entry point that selects the current version.

Recommended defaults:

- `index.html`, `challenge.html`, `*.cfg`, and `build-info.txt`: no cache or
  revalidate;
- JavaScript, CSS, Wasm, kernel, and disk chunks: cache for one hour;
- purge the CDN after switching a release if the public URL remains unchanged.

Serving a mixture of files from two releases can pair an old emulator or config
with a new disk image. Atomic origin deployment and conservative caching reduce
that risk.

## Security guidance

- Obtain redistribution permission before public release.
- Serve the site over HTTPS.
- Keep all runtime assets on the same controlled origin.
- Do not enable guest external networking unless a scenario requires it.
- Do not expose the build directory or repository.
- Treat status messages as untrusted input; `lab-ui.js` validates the scenario
  and allowed status values.
- The participant has guest root access. The browser status is a convenience,
  not a tamper-resistant scoring mechanism.
- Use an external verifier if challenge completion affects grading or
  certification.
- Review the Content Security Policy after adding analytics, fonts, workers, or
  third-party assets rather than weakening it broadly.

## Licensing and software inventory

TinyEMU and the older published JSLinux demo are distributed under the MIT
license. The 2026 x86_64 binaries need separate redistribution clarification.

The generated guest contains packages with their own licenses. Generate
Buildroot's legal-information bundle before distributing a release:

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp/home \
  --volume "$PWD/jslinux:/workspace" \
  linux-troubleshooting-lab-jslinux-builder \
  make -C build/sources/buildroot-2025.02.18 \
    O=/workspace/build/buildroot-output-x86_64-musl \
    legal-info
```

Output is written below:

```text
jslinux/build/buildroot-output-x86_64-musl/legal-info/
```

Review package manifests, source archives, license files, and obligations before
publishing.

## Troubleshooting

### The build cannot download an upstream asset

Confirm network access to `buildroot.org` and `bellard.org`. A checksum mismatch
is a hard failure. Do not bypass it; determine whether the upstream file changed
and update `versions.env` only after review.

### A source edit is not present in the guest

Run:

```bash
make jslinux-image
```

The endpoint package is invalidated automatically. For architecture, libc, or
toolchain changes, perform a clean build.

### The browser shows a blank page or `file://` errors

Serve `dist/` over HTTP or HTTPS. Do not open `index.html` directly.

### Wasm fails to compile

Check:

- `.wasm` has `Content-Type: application/wasm`;
- CSP includes `'wasm-unsafe-eval'` in `script-src`;
- the Wasm request returns binary data rather than an HTML error page;
- all files came from the same release.

### The terminal remains at `Loading...`

Open browser developer tools and inspect failed requests. Verify:

```text
kernel-x86_64-lab-<image-version>.bin
x86_64emu-wasm.js
x86_64emu-wasm.wasm
root-x86_64-<image-version>.cfg
root-x86_64-<image-version>/blk.txt
root-x86_64-<image-version>/blk*.bin
```

Also confirm the browser has enough memory for the configured 512 MB guest.

### The VM panics with `CPU ISA level is lower than required`

The guest was built with an incompatible glibc baseline. The supported
prototype configuration uses musl. Restore
`BR2_TOOLCHAIN_BUILDROOT_MUSL=y`, clean, and rebuild.

### The VM boots but status stays unavailable

Inside the guest:

```bash
ps | grep lab-status
scenario="$(cat /var/run/lab-scenario)"
curl -i "http://127.0.0.1/api/v1/${scenario}"
/etc/init.d/S60lab-status restart
```

Check that `lab-status-reporter` and `lab-ui.js` use the same scenario
identifier and protocol.

### Nginx inside the guest fails

Inside the guest:

```bash
nginx -t
cat /var/log/nginx/error.log
ss -lntp
```

Remember that guest Nginx and deployment-host Nginx are separate processes with
separate configurations.

### Reset does not restore the broken state

Reset reloads the immutable disk delivered by the web server. Confirm the
initial fault exists in the root filesystem overlay, rebuild, deploy the entire
new `dist/` atomically, and clear stale CDN/browser caches.

## Architecture notes and current limitations

- One reproducible Buildroot image contains all four services, but
  `LAB_SCENARIO=endpointN` starts only one per browser VM.
- The browser table of contents links to separate challenge URLs without
  describing their faults.
- The services are small C implementations compiled with the guest toolchain.
  They preserve the API and syscall behavior relevant to each scenario.
- The parent page cannot route to guest loopback or the guest DHCP address.
  Status is reported over the VirtIO console.
- The guest uses BusyBox init, not systemd.
- Reset reloads the page rather than hot-restarting the emulator.
- External guest networking is not required. The AppArmor challenge remains
  out of scope because Bellard's supplied kernel does not enable that LSM.
- The disk is block-backed because future database scenarios may depend on
  filesystem locking and durability behavior that the JSLinux 9P backend does
  not faithfully provide.
- The design and future implementation phases are documented in
  `../docs/jslinux-feasibility-and-design.md`.
