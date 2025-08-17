{%- set arch_map = {'x86_64': 'amd64', 'aarch64': 'arm64'} %}
{%- set arch = arch_map.get(grains['cpuarch'], 'amd64') %}

/opt/dashboard:
  file.directory:
    - mode: '0755'

extract-dashboard:
  archive.extracted:
    - name: /opt/dashboard
    - source: /tmp/artifacts/dashboard_linux_{{ arch }}.tar.gz
    - enforce_toplevel: False

/opt/dashboard/dashboard:
  file.managed:
    - source: /opt/dashboard/dashboard_linux_{{ arch }}
    - mode: '0755'

/etc/default/lab-dashboard:
  file.managed:
    - source: salt://roles/dashboard/files/dashboard.env

/etc/systemd/system/lab-dashboard.service:
  file.managed:
    - source: salt://roles/dashboard/files/dashboard.service

daemon-reload-dashboard:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/lab-dashboard.service

lab-dashboard:
  service.running:
    - name: lab-dashboard
    - enable: true
    - require:
      - cmd: daemon-reload-dashboard
