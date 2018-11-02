#!/usr/bin/env bash
source $HOME/Projects/Personal/dotfiles/bash/functions/util/jdk_unset.sh --source-only

# Function to set the system JDK version.
function jdk_set() {
	if [ $# -ne 0 ]; then
		jdk_unset '/System/Library/Frameworks/JavaVM.framework/Home/bin'
		if [ -n "${JAVA_HOME+x}" ]; then
			jdk_unset $JAVA_HOME
		fi
		export JAVA_HOME=`/usr/libexec/java_home -v $@`
		export PATH=$JAVA_HOME/bin:$PATH
	fi
}
