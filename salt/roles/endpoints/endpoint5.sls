{% from "roles/endpoints/_macros.jinja" import install_binary, envfile, unitfile %}

endpoint5-user:
  user.present:
    - name: endpoint5

/var/log/endpoint5:
  file.directory:
    - user: endpoint5
    - group: endpoint5
    - mode: '0755'
    - require:
      - user: endpoint5-user
    - require_in:
      - service: endpoints-enabled

# Config directory + file with plausible content
/etc/endpoint5:
  file.directory:
    - user: root
    - group: root
    - mode: '0755'

/etc/endpoint5/config.json:
  file.managed:
    - contents: |
        {"message":"hello from endpoint5"}
    - mode: '0644'
    - user: root
    - group: root

{{ install_binary('endpoint5') }}

# env: add CONF_PATH for clarity (binary has same default)
#/etc/default/endpoint5 via macro:
{{ envfile('endpoint5', 9005, '/var/log/endpoint5') }}

{{ unitfile('endpoint5', 'endpoint5', 9005) }}

# Make sure AppArmor profile is present before starting endpoints
require-apparmor-for-endpoint5:
  test.nop:
   - require:
      - cmd: reload-endpoint5-profile
