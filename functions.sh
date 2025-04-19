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

parse_config() {
    local config_file="$1"
    if [[ ! -f "$config_file" ]]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    # Read each non-comment, non-empty line
    while IFS='=' read -r key value; do
        # Trim whitespace
        key="$(echo "$key" | xargs)"
        value="$(echo "$value" | xargs)"

        # Skip empty keys or comments
        [[ -z "$key" || "$key" == \#* ]] && continue

        # Export the key-value pair
        export "$key=$value"
    done < "$config_file"
}

sanitize() {
  string=$(echo "$1" | sed 's/[\\/*?"<>|:]//g' | sed 's/  \+/ /g' | sed 's/^[ \t]*//;s/[ \t]*$//')
  echo "$string"
}

slash_loader() {
    local text="$1"  # Accept text as an argument
    local chars=('/' '-' '\\' '|')
    local colors=("31" "33" "32" "36" "34" "35") # Red, Yellow, Green, Cyan, Blue, Magenta
    while :; do
        for i in {0..3}; do
            echo -ne "\r\e[${colors[i]}m${chars[i]}\e[0m ${text}"  # Print spinner + text
            sleep 0.1
        done
    done
}

interpolate_color() {
    local start_r=$1 start_g=$2 start_b=$3
    local end_r=$4 end_g=$5 end_b=$6
    local steps=$7
    local current_step=$8

    # Calculate intermediate color
    local r=$(( start_r + (end_r - start_r) * current_step / steps ))
    local g=$(( start_g + (end_g - start_g) * current_step / steps ))
    local b=$(( start_b + (end_b - start_b) * current_step / steps ))

    printf "\e[38;2;%d;%d;%dm" "$r" "$g" "$b"
}

gradient_loader() {
    local text="$1"  # Text to display
    local length=5
    local char="="
    local delay=0.1

    # Dark purple (#5A005A) → Bright pink (#FF00FF)
    local start_r=90 start_g=0 start_b=90
    local end_r=255 end_g=0 end_b=255

    while true; do
        # Growing phase
        for i in $(seq 1 $length); do
            line="["
            for j in $(seq 1 $i); do
                line+="$(interpolate_color $start_r $start_g $start_b $end_r $end_g $end_b $i $j)$char"
            done
            printf "\r%s\e[0m%$((length - i))s] %s" "$line" "" "$text"
            sleep $delay
        done

        # Shrinking phase
        for i in $(seq $length -1 1); do
            line="["
            for j in $(seq 1 $i); do
                line+="$(interpolate_color $start_r $start_g $start_b $end_r $end_g $end_b $i $j)$char"
            done
            printf "\r%s\e[0m%$((length - i))s] %s" "$line" "" "$text"
            sleep $delay
        done
    done
}