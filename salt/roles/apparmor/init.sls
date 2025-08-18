apparmor-pkgs:
  pkg.installed:
    - pkgs:
      - apparmor
      - apparmor-utils

/etc/apparmor.d/opt.endpoints.endpoint5.server:
  file.managed:
    - source: salt://roles/apparmor/files/opt.endpoints.endpoint5.server
    - mode: '0644'

# Ensure service is up and profile is (re)loaded after changes
apparmor-service:
  service.running:
    - name: apparmor
    - enable: true
    - require:
      - pkg: apparmor-pkgs
      - file: /etc/apparmor.d/opt.endpoints.endpoint5.server

reload-endpoint5-profile:
  cmd.run:
    - name: apparmor_parser -r /etc/apparmor.d/opt.endpoints.endpoint5.server
    - onchanges:
      - file: /etc/apparmor.d/opt.endpoints.endpoint5.server
    - require:
      - service: apparmor-service

