# Ensure php-fpm running & enabled
php-fpm-service:
  service.running:
    - name: php8.3-fpm
    - enable: true

# Drop the PHP script that will exercise DNS
/var/www/html/endpoint1.php:
  file.managed:
    - source: salt://roles/php/files/endpoint1.php
    - user: www-data
    - group: www-data
    - mode: '0644'
