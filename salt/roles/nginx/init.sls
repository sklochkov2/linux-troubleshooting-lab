nginx-service:
  service.running:
    - name: nginx
    - enable: true
    - watch:
      - file: /etc/nginx/sites-available/default

/etc/nginx/sites-available/default:
  file.managed:
    - source: salt://roles/nginx/files/default.conf
    - user: root
    - group: root
    - mode: '0644'

reload-nginx:
  cmd.wait:
    - name: systemctl reload nginx
    - watch:
      - file: /etc/nginx/sites-available/default
