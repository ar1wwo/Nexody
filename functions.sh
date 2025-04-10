#!/bin/bash

# Custom echo function that handles silent operation and command substitution
print() {
	SILENT=false
	# Loop through all arguments
	for arg in "${args[@]}"; do
		if [[ "$arg" == "-s" ]]; then
			SILENT=true
		fi
	done	
	
	# Check seccond arg for -o
	if [[ "$2" == "-o" ]]; then
		mode="output"
	fi
	# Respect the SILENT flag
	if [ "$SILENT" != true ]; then
		echo "$1" >&2
	fi
	# Output to stdout only if mode is "output" and if used in command substitution
	if [ "$mode" = "output" ] && [ ! -t 1 ]; then
		echo "$1"
	fi
}