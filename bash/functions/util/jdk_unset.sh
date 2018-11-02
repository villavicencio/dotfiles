#!/usr/bin/env bash

# Remove the system JDK version
function jdk_unset() {
	export PATH=$(echo $PATH | sed -E -e "s;:$1;;" -e "s;$1:?;;");
}
