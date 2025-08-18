{% from "roles/endpoints/_macros.jinja" import install_binary, envfile, unitfile %}

endpoint4-user:
  user.present:
    - name: endpoint4

/var/log/endpoint4:
  file.directory:
    - user: endpoint4
    - group: endpoint4
    - mode: '0755'
    - require_in:
      - service: endpoints-enabled

/var/lib/endpoint4:
  file.directory:
    - user: endpoint4
    - group: endpoint4
    - mode: '0755'
    - require:
      - user: endpoint4-user

/var/lib/endpoint4/stress:
  file.directory:
    - user: endpoint4
    - group: endpoint4
    - mode: '0755'
    - require:
      - user: endpoint4-user

{{ install_binary('endpoint4') }}

/etc/default/endpoint4:
  file.managed:
    - source: salt://roles/endpoints/templates/endpoint.env.j2
    - template: jinja
    - context:
        port: 9134
        log_dir: "/var/log/endpoint4"
        name: "endpoint4"
    - require_in:
      - service: endpoints-enabled

{{ unitfile('endpoint4', 'endpoint4', 9134, 64) }}
