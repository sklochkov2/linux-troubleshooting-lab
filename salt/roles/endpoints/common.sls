{% set arch_map = {'x86_64': 'amd64', 'aarch64': 'arm64'} %}
{% set arch = arch_map.get(grains['cpuarch'], 'amd64') %}

/opt/endpoints:
  file.directory:
    - mode: '0755'

# verify we actually copied artifacts (packer file provisioner)
# v2 is an example: bump to your artifact version
/tmp/artifacts/sha256sums.txt:
  file.exists

verify-artifacts:
  cmd.run:
    - name: "cd /tmp/artifacts && sha256sum -c sha256sums.txt"
    - unless: "test -f /opt/endpoints/.artifacts_v2_installed"

# A single reload resource all units can watch into
systemctl-daemon-reload:
  cmd.wait:
    - name: systemctl daemon-reload

