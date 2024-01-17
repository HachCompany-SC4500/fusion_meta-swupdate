#!/usr/bin/env bash

# Setup command line completion for uboot-helper.sh script

_helper_completions() {

	if [ "${#COMP_WORDS[@]}" == "2" ]; then
		# Use compgen to generate a COMPREPLY with the list of all possible options if we complete the second word (first parameter of the command)
		# compgen will automatically complete the current word (${COMP_WORDS[1]) according to the possible match
		COMPREPLY=($(compgen -W "get-uboot-primary-offset get-uboot-secondary-offset get-uboot-size get-ubootenv-primary-offset get-ubootenv-secondary-offset get-ubootenv-size lock unlock backup-uboot-primary backup-ubootenv-primary restore-uboot-primary restore-ubootenv-primary is-uboot-synchronized is-ubootenv-synchronized is-secondary-uboot-used populate-uboot-env write-ubootenv-primary erase-uboot-primary erase-uboot-secondary erase-ubootenv-primary erase-ubootenv-secondary" -- "${COMP_WORDS[1]}"))
		return
	elif [ "${#COMP_WORDS[@]}" == "3" ]; then
		# Use compgen to generate a COMPREPLY with the list of all files of the current folder if command parameter is "write-ubootenv-primary"
		if [ "${COMP_WORDS[1]}" == "write-ubootenv-primary" ]; then
		        COMPREPLY=($(compgen -f -- "${COMP_WORDS[2]}"))
		fi
		return
	fi
}

# Tell bash to call "_helper_completions" to get completion for uboot-helper.sh
# https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion.html
complete -F _helper_completions uboot-helper.sh
