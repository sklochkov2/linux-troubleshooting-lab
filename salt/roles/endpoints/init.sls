include:
  - roles.endpoints.common
  - roles.endpoints.endpoint2
  - roles.endpoints.endpoint3
  - roles.endpoints.endpoint4
  - roles.endpoints.endpoint5

# After all endpoints are defined, enable/start them here so we keep ordering simple
endpoints-enabled:
  service.running:
    - names:
      - endpoint2
      - endpoint3
      - endpoint4
      - endpoint5
    - enable: true
    - require:
      - cmd: systemctl-daemon-reload

mark-artifacts-installed:
  file.managed:
    - name: /opt/endpoints/.artifacts_v2_installed
    - contents: "ok\n"
    - require:
      - service: endpoints-enabled

