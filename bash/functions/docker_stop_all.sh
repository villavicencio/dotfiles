#!/usr/bin/env bash

function docker_stop_all() {
    docker-compose stop $1
	docker-compose rm --force $1
}
