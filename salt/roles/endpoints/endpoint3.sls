{% from "roles/endpoints/_macros.jinja" import install_binary, envfile, unitfile %}

endpoint3-user:
  user.present:
    - name: endpoint3

/var/log/endpoint3:
  file.directory:
    - user: endpoint3
    - group: endpoint3
    - mode: '0755'

/var/lib/endpoint3:
  file.directory:
    - user: root
    - group: root
    - mode: '0755'

{{ install_binary('endpoint3') }}
{{ envfile('endpoint3', 9907, '/var/log/endpoint3') }}
{{ unitfile('endpoint3', 'endpoint3', 9907) }}
