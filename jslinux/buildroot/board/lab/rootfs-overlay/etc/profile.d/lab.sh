scenario="$(cat /var/run/lab-scenario 2>/dev/null || printf endpoint1)"
printf '\nSelected API: http://127.0.0.1/api/v1/%s\n\n' "$scenario"
unset scenario
