{% from "roles/endpoints/_macros.jinja" import install_binary, envfile, unitfile %}

# system user & log dir
endpoint2-user:
  user.present:
    - name: endpoint2

/var/log/endpoint2:
  file.directory:
    - user: endpoint2
    - group: endpoint2
    - mode: '0755'
    - require:
      - user: endpoint2-user
    - require_in:
      - service: endpoints-enabled

/var/log/endpoint2/logs:
  file.directory:
    - user: root
    - group: root
    - mode: '0755'

{{ install_binary('endpoint2') }}
{{ envfile('endpoint2', 9002, '/var/log/endpoint2') }}
{{ unitfile('endpoint2', 'endpoint2', 9002) }}
