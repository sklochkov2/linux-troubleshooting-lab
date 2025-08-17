# Linux Troubleshooting Lab

A reproducible, cloud-agnostic playground for practicing **Linux debugging** in a realistic web stack.
You deploy a single VM that fronts several upstream services behind **Nginx**. Some endpoints are
**intentionally misconfigured** in ways that mirror real-world failures. The goal is to explore, observe,
form hypotheses, and fix issues using standard Linux tools — not to guess solutions.

> **No spoilers:** This README explains how to build and run the lab, not how the challenges are implemented.

---

## What’s included

* **Immutable VM image (AMI)** built with **Packer** and configured via **Salt (masterless)**.
* **Nginx reverse proxy** exposing uniform HTTP endpoints:

  * `/api/v1/endpoint1 … /api/v1/endpointN`
* **Tiny upstream services** (Go and/or Rust) with minimal resource usage.
* Optional **dashboard** (lightweight Go binary) that probes endpoints (can be disabled).
* A **reset script** to restore the VM to its initial “challenge” state (useful for repeated practice).

---

## Architecture (high level)

```
Client → Nginx (reverse proxy)
              ├── /api/v1/endpoint1 → upstream #1 (service)
              ├── /api/v1/endpoint2 → upstream #2 (service)
              └── /api/v1/endpointN → upstream #N (service)

Provisioning:  Packer → Salt (local/masterless)
Runtime:       systemd units for Nginx, upstream services, (optional) dashboard
Artifacts:     Prebuilt binaries shipped during image build (no compiling on AMI)
```

Designed to run on minimal instances (e.g., `t3.micro`) to keep costs low.

---

## Repository layout

```
linux-troubleshooting-lab/
├─ src/                      # source code for services & dashboard
│  ├─ dashboard/
│  └─ endpoints/
├─ artifacts/                # built binaries (tar.gz), versioned (gitignored)
│  └─ vX/
├─ salt/                     # Salt states (masterless)
│  └─ roles/
│     ├─ nginx/
│     ├─ php/
│     ├─ endpoints/          # one state per endpoint + shared macros
│     ├─ dashboard/
│     └─ challenges/         # injectors/reset (generic, spoiler-free)
├─ packer/                   # Packer HCL template(s) + scripts
├─ terraform/                # Terraform to launch a VM from the AMI
├─ tools/                    # local build helpers for artifacts
└─ Makefile                  # end-to-end automation (build → bake → apply)
```

**Separation of concerns:** Salt contains **states/templates**, not application source.
Binaries are prebuilt on your workstation, placed under `artifacts/`, and copied in by Packer.

---

## Requirements

* **Packer** ≥ 1.7 (HCL2 templates; supports `packer init`)
* **Terraform** ≥ 1.2
* **AWS CLI** (configured profile with permissions to build AMIs & launch instances)
* **Go** (if building Go services) and/or **Rust** (if building Rust services)
* An existing **EC2 key pair** (used by Terraform for SSH access)

---

## Quick start (no spoilers)

### 1) Build artifacts locally (fast; uses your CPU)

```bash
# Example: build Go services (produces artifacts/v1/*.tar.gz + sha256sums.txt)
./tools/build-go.sh v1 amd64

# Example: build a Rust service variant (produces artifacts/v2/*.tar.gz + sha256sums.txt)
./tools/build-rust.sh v2 amd64
```

Artifacts are versioned under `artifacts/vX/` and are **gitignored**.

### 2) Bake the AMI with Packer

```bash
# The Makefile wraps the common flags and writes the AMI ID for Terraform:
make packer-build VERSION=v1 AWS_REGION=eu-west-2
```

This copies Salt + artifacts to the builder, applies Salt masterless, and emits a
`packer/manifest.json`. The Makefile parses it and writes the new AMI ID to:

```
terraform/ami.auto.tfvars
```

### 3) Configure Terraform variables (gitignored)

Create `terraform/terraform.tfvars`:

```hcl
region        = "eu-west-2"
key_name      = "your-ec2-keypair-name"
ssh_cidr      = "203.0.113.42/32"  # restrict SSH to your IP if possible
# ami_id is auto-written to terraform/ami.auto.tfvars by the Makefile
```

### 4) Launch the VM

```bash
make tf-apply
# or, if you prefer to point at your tfvars explicitly:
make tf-apply-file
```

### 5) Access

* Nginx root: `http://<public-dns>/`
* Endpoints: `http://<public-dns>/api/v1/endpoint1` … `/endpointN`
* (Optional) Dashboard: proxied path if configured, or `http://<public-dns>:8080/` if exposed

### 6) Tear down when finished

```bash
make tf-destroy
```

---

## The Makefile (common targets)

* `make artifacts` — build binaries from `src/*` into `artifacts/$(VERSION)/`
* `make packer-init` / `make packer-validate` / `make packer-build`
* `make tf-init` / `make tf-validate` / `make tf-apply` / `make tf-destroy`
* `make up` — convenience: artifacts → packer-build → tf-apply
* `make clean` — remove local Terraform state/work dirs
* `make deep-clean` — also clear Packer cache/manifest

> The Packer build uses a **manifest** post-processor; `make packer-build` parses it to populate `terraform/ami.auto.tfvars` automatically.

---

## Configuration & conventions

* Endpoints use a uniform prefix: **`/api/v1/endpoint1..N`**.
* Each endpoint has:

  * a dedicated **system user**,
  * a **log directory** under `/var/log/endpointX`,
  * an **env file** `/etc/default/endpointX`,
  * a **systemd unit** `endpointX.service`.
* The optional dashboard reads configuration from `/etc/default/lab-dashboard`
  (listen address, base URL, path prefix, endpoint count).

Keep private Terraform variables in `terraform/terraform.tfvars` and ensure it’s listed in `.gitignore`.

---

## Debugging image builds (without spoilers)

**Keep the builder alive & SSH in:**

```bash
PACKER_LOG=1 PACKER_LOG_PATH=packer-debug.log \
packer build -on-error=ask packer/ubuntu-2404.pkr.hcl
# On failure, choose to keep the instance.
```

Inspect on the builder:

```bash
sudo systemctl status <service> --no-pager
sudo journalctl -u <service> -n 200 --no-pager
sudo tail -n +200 /var/log/salt/ami-build.log 2>/dev/null || true
```

**Capture Salt logs during bake:**

Provisioners can use:

```bash
salt-call --local --retcode-passthrough -l debug \
  --log-file /var/log/salt/ami-build.log --log-file-level=debug \
  state.apply roles.<role>
```

This streams details to Packer output and keeps a log on disk for later inspection.

---

## Resetting a VM (for trainees)

A helper script is installed at:

```
/usr/local/sbin/reset-state.sh
```

It restores the VM to a fresh practice state. Run it via SSH when needed.

---

## Extending the lab (no spoilers)

* **Add an endpoint**

  1. Implement a new service under `src/endpoints/endpointN/…` and build it into `artifacts/vX/`.
  2. Add a Salt state `salt/roles/endpoints/endpointN.sls` using shared macros to:

     * create the system user,
     * ensure `/var/log/endpointN` exists,
     * install the artifact to `/opt/endpoints/endpointN/server`,
     * drop `/etc/default/endpointN` and `endpointN.service`.
  3. Include it from `salt/roles/endpoints/init.sls`.
  4. Add an Nginx `location` for `/api/v1/endpointN → 127.0.0.1:<port>`.

* **Add a challenge**

  * Place generic **injector** scripts in `salt/roles/challenges/files/` and apply them in a dedicated state.
  * Avoid embedding solutions in descriptions, filenames, or unit `Description=` text.

---

## Costs & cleanup

* This project creates **paid resources** in your cloud account.
* Use `make tf-destroy` to terminate instances and delete the security group.
* Periodically **deregister old AMIs** and delete their **snapshots** if you no longer need them.

---

## Security notes

* Restrict SSH with `ssh_cidr` (prefer your fixed IP/CIDR).
* Treat AMIs as **immutable snapshots**; rebuild rather than hot-editing.
* Keep secrets out of Git. Use AWS profiles/SSO for credentials and a gitignored `terraform.tfvars` for local values.

---

## Contributing

* Keep Salt states **spoiler-free**.
* Prefer **one Salt file per endpoint**, sharing macros in `salt/roles/endpoints/_macros.jinja`.
* Keep binaries out of Git; commit only sources and build scripts.
