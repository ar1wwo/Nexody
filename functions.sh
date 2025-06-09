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

# Log functionality ------------------------------------------------------------------------------------------------------------------------------------------- #

LOG_DIR="logs"																																				# Declare Logs directory
mkdir -p "$LOG_DIR"																																				# Create Logs directory if not present
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')																															# Variable for current time
LOG_FILE="$LOG_DIR/nexody_$TIMESTAMP.log"																														# Declare Log file output

log() {
  if [ $# -eq 1 ]; then
    echo "[$(date +"%T")] $1" >> "$LOG_FILE"
  elif [ $# -gt 1 ]; then
    "$@" 2>&1 | while IFS= read -r line; do
      echo "[$(date +"%T")] $line" >> "$LOG_FILE"
    done
  fi
}

sanitize() {
  string=$(echo "$1" | sed 's/[\\/*?"<>|:]//g' | sed 's/  \+/ /g' | sed 's/^[ \t]*//;s/[ \t]*$//')
  echo "$string"
}

escape_glob() {
  # Escapes glob-sensitive characters: [ ] \ * ?
  echo "$1" | sed 's/[][\\*?]/\\&/g'
}

index() {
  echo $(( $1 * (len2 + 1) + $2 ))
}

normalize() {
  local s=$(echo "$1" | tr '[:upper:]' '[:lower:]')

  # Leading articles
  s=$(echo "$s" | sed -E 's/^(the|a|an)\s+//')

  # Remove parentheses and brackets content
  s=$(echo "$s" | sed -E 's/\(.*?\)//g; s/\[.*?\]//g')

  # Define suffix keywords in a variable for easy extension
  local suffixes='feat\.?|remix(ed)?|remaster(ed)?|live|edit(ed)?|version|demo|acoustic|instrumental|explicit|clean|rework(ed)?|club mix|extended mix|original mix|mix|radio|bonus track|deluxe|mono|stereo|cover|tribute|performance|edition|intro|outro|interlude|skit|freestyle|snippet|sample|reprise'

  # Remove dash or colon + optional words + suffix and everything after
  s=$(echo "$s" | sed -E "s/\s*[-:]\s*([^[:space:]]+\s+)*?($suffixes).*//i")

  # Remove suffix and everything after if suffix is not after separator
  s=$(echo "$s" | sed -E "s/\s*($suffixes).*//i")

  # Remove spaces and punctuation
  s=$(echo "$s" | tr -d '[:space:]' | tr -d '[:punct:]')

  echo "$s"
}

levenshtein_normalized() {
  local str1=$(normalize "$1")
  local str2=$(normalize "$2")
  len1=${#str1}
  len2=${#str2}
  local i j

  # simulate 2D array with flat 1D array
  local -a d

  for ((i=0; i<=len1; i++)); do d[$(index $i 0)]=$i; done
  for ((j=0; j<=len2; j++)); do d[$(index 0 $j)]=$j; done

  for ((i=1; i<=len1; i++)); do
    for ((j=1; j<=len2; j++)); do
      if [ "${str1:i-1:1}" == "${str2:j-1:1}" ]; then
        cost=0
      else
        cost=1
      fi

      deletion=$(( d[$(index $((i-1)) $j)] + 1 ))
      insertion=$(( d[$(index $i $((j-1)))] + 1 ))
      substitution=$(( d[$(index $((i-1)) $((j-1)))] + cost ))

      min=$deletion
      (( insertion < min )) && min=$insertion
      (( substitution < min )) && min=$substitution

      d[$(index $i $j)]=$min
    done
  done

  echo "${d[$(index $len1 $len2)]}"
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

    log "$1"

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