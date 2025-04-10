#!/bin/bash

# Check dependencies
command -v ./jq >/dev/null 2>&1 || { echo >&2 "jq required but not found. Aborting."; exit 1; }
command -v ./curl >/dev/null 2>&1 || { echo >&2 "curl required but not found. Aborting."; exit 1; }

[ $# -lt 2 ] && { echo "Usage: $0 <Artist> <Title> [-s]" >&2; exit 1; }

artist_name="$1"
song_title="$2"
args=("$@")

# Source the function library
source ./functions.sh

print "iTunes"
sleep 3
print "Searching: $artist_name - $song_title"

# Case-insensitive comparison functions
ci_equals() {
    [[ "${1,,}" = "${2,,}" ]]
}

ci_contains() {
    [[ "${1,,}" == *"${2,,}"* ]]
}

# Function to select best match from iTunes results
select_best_match() {
    local response="$1"
    local artist="$2"
    local title="$3"
    
    local best_score=0
    local best_matches=()
    local count=$(echo "$response" | ./jq '.resultCount')

	print "Found $count result(s):"
    
    for ((i=0; i<count; i++)); do
        local current_data=$(echo "$response" | ./jq ".results[$i]")
        local current_artist=$(echo "$current_data" | ./jq -r ".artistName")
        local current_title=$(echo "$current_data" | ./jq -r ".trackName")
        local current_score=0
        
        # Base score components
        if ci_equals "$current_title" "$title"; then
            current_score=$((current_score + 50))
        elif ci_contains "$current_title" "$title"; then
            current_score=$((current_score + 30))
        fi

        if ci_equals "$current_artist" "$artist"; then
            current_score=$((current_score + 40))
        elif ci_contains "$current_artist" "$artist"; then
            current_score=$((current_score + 20))
        fi

        local collection=$(echo "$current_data" | ./jq -r ".collectionName")
        if ci_equals "$collection" "$title" || ci_contains "$collection" "$title"; then
            current_score=$((current_score + 15))
        fi

        local track_explicitness=$(echo "$current_data" | ./jq -r ".trackExplicitness")
        [ "$track_explicitness" = "notExplicit" ] && current_score=$((current_score + 5))

        if (( current_score > best_score )); then
            best_matches=("$i")
            best_score=$current_score
        elif (( current_score == best_score )); then
            best_matches+=("$i")
        fi
    done
    
    echo "${best_matches[@]}"
}

# URL encode the artist and song names
ENCODED_ARTIST=$(echo "$artist_name" | ./jq -sRr @uri)
ENCODED_SONG=$(echo "$song_title" | ./jq -sRr @uri)

# Make API request to the iTunes API
url="https://itunes.apple.com/search?term=${ENCODED_SONG}+${ENCODED_ARTIST}&entity=song&limit=10"
response=$(./curl -s "$url")

# Get best matches
best_matches=($(select_best_match "$response" "$artist_name" "$song_title"))

# Process and display results
# Detailed output format
print
count=$(echo "$response" | ./jq '.resultCount')

for ((i=0; i<count; i++)); do
	# Determine if this is a best match
	is_best=" "
	if [[ " ${best_matches[@]} " =~ " $i " ]]; then
		is_best="→"
	fi
	
	# Format the result using ./jq
	results=$(echo "$response" | ./jq -r --arg i "$i" --arg is_best "$is_best" '
		.results[$i|tonumber] as $rec |
		"\($is_best) [\($i|tonumber + 1)]\n" +
		"  Title:  \($rec.trackName)\n" +
		"  Artist: \($rec.artistName)\n" +
		"  Album:  \($rec.collectionName)\n" +
		"  ARID:   \($rec.artistId)\n"
	')
	
	# Apply formatting
	if [[ " ${best_matches[@]} " =~ " $i " ]]; then
		print "$(tput bold)$results$(tput sgr0)"
	else	
		print "$(tput setaf 8)$results$(tput sgr0)"
	fi
	print
done


best_index=${best_matches[0]}
best_arid=$(echo "$response" | ./jq -r ".results[$best_index].artistId")

print "Fetching genres for best match (ARID: $best_arid)"

# Make the API request to get the artist details
# response=$(./curl -s "https://itunes.apple.com/lookup?id=$best_arid&entity=album")
response=$(./curl -s "https://itunes.apple.com/lookup?id=${best_arid}")

# Extract the genres from the JSON response
genres=$(echo $response | ./jq -r '.results[0].primaryGenreName' | sed 's/\//, /')

# Print the genres
print "${genres,,}" -o