<?php
header('Content-Type: application/json');

$host = "www.wikipedia.org";
$ip   = gethostbyname($host);

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, "https://".$host."/");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 5);
$resp = curl_exec($ch);
$err  = curl_error($ch);
$http = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

echo json_encode([
  "service"     => "endpoint1-php",
  "host"        => $host,
  "resolved_ip" => $ip,
  "http_code"   => $http,
  "curl_error"  => $err,
  "ok"          => ($err === "")
], JSON_PRETTY_PRINT);
?>
