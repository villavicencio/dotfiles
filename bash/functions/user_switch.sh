#!/usr/bin/env bash

function user_switch() {
	read -s -p Password: pwd;
	if [ $pwd == 'dv9161984' ]; then
		/System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -switchToUserID `id -u z`
    fi
    unset pwd;
}
