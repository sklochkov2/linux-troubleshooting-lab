/opt/challenges:
  file.directory:
    - user: root
    - group: root
    - mode: '0755'

/opt/challenges/inject_dns_poison.sh:
  file.managed:
    - source: salt://roles/challenges/files/inject_dns_poison.sh
    - mode: '0755'

/opt/challenges/reset-dns.sh:
  file.managed:
    - source: salt://roles/challenges/files/reset-dns.sh
    - mode: '0755'

# Apply the failure at image build time (idempotent)
apply-dns-poison:
  cmd.run:
    - name: /opt/challenges/inject_dns_poison.sh

/opt/challenges/inject_log_ownership.sh:
  file.managed:
    - source: salt://roles/challenges/files/inject_log_ownership.sh
    - mode: '0755'

/opt/challenges/endpoint2_backup.sh:
  file.managed:
    - source: salt://roles/challenges/files/endpoint2_backup.sh
    - mode: '0755'

/etc/cron.d/endpoint2-backup:
  file.managed:
    - source: salt://roles/challenges/files/cron_endpoint2_backup
    - mode: '0644'

apply-endpoint2-breakage:
  cmd.run:
    - name: /opt/challenges/inject_log_ownership.sh
    - require:
      - service: endpoints-enabled

/opt/challenges/inject_lockfile_endpoint3.sh:
  file.managed:
    - source: salt://roles/challenges/files/inject_lockfile_endpoint3.sh
    - mode: '0755'

/opt/challenges/reset_lockfile_endpoint3.sh:
  file.managed:
    - source: salt://roles/challenges/files/reset_lockfile_endpoint3.sh
    - mode: '0755'

# Apply at bake time so the endpoint starts in maintenance mode
apply-endpoint3-lock:
  cmd.run:
    - name: /opt/challenges/inject_lockfile_endpoint3.sh
    - require:
      - service: endpoints-enabled
