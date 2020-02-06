#!/usr/bin/env bash

# Start a PHP server from a directory, optionally specifying the port
# (Requires PHP 5.4.0+.)
function server_php() {
  port="${1:-4000}";
  ip=$(ipconfig getifaddr en1);
	local ip, port
	sleep 1 && open "http://${ip}:${port}/" &
	php -S "${ip}:${port}";
}
