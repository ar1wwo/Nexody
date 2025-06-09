#!/bin/bash

# Check dependencies
command -v ./jq >/dev/null 2>&1 || { echo >&2 "jq required but not found. Aborting."; exit 1; }
command -v ./curl >/dev/null 2>&1 || { echo >&2 "curl required but not found. Aborting."; exit 1; }

[ $# -lt 2 ] && { echo "Usage: $0 <Artist> <Title> [-s]" >&2; exit 1; }

artist="$1"
title="$2"
args=("$@")

# Source the function library
source ./functions.sh

get-genres-musicbrainz() {

	print "MusicBrainz"
	sleep 1
	print "Searching: $artist - $title"

	# Get raw results
	response=$(./curl -f -s -G -A "MusicBrainzBot/1.0" \
		"https://musicbrainz.org/ws/2/recording/" \
		--data-urlencode "query=artist:${artist} AND recording:${title}" \
		-d "fmt=json" \
		-d "inc=artist-credits+releases" 2>/dev/null) || {
		print "Error: Failed to fetch data from MusicBrainz"
		exit 1
	}

	# Get all recordings with proper score filtering
	recordings=$(echo "$response" | ./jq -c '
		[.recordings[] | 
		select(.score? | type == "number") |
		select(.score > 60)]
		' 2>/dev/null)

	if [ -z "$recordings" ] || [ "$recordings" = "[]" ]; then
		print "No results found"
		exit 1
	fi

	# Improved scoring system for best match selection
	best_matches=()
	best_score=0
	count=$(echo "$recordings" | ./jq 'length')

	for ((i=0; i<count; i++)); do
		current_artist=$(echo "$recordings" | ./jq -r ".[$i][\"artist-credit\"][0].name")
		current_score=$(echo "$recordings" | ./jq -r ".[$i].score | tonumber")
		
		# Name matching bonuses
		if [ "${current_artist,,}" = "${artist,,}" ]; then
			current_score=$((current_score + 40))  # Exact match bonus
		elif [[ "${current_artist,,}" == *"${artist,,}"* ]]; then
			current_score=$((current_score + 20))  # Partial match bonus
		fi
		
		# Release count bonus (more releases = more likely canonical version)
		release_count=$(echo "$recordings" | ./jq -r ".[$i].releases | length")
		current_score=$((current_score + release_count))
		
		# Track best matches
		if (( current_score > best_score )); then
			best_matches=($i)
			best_score=$current_score
		elif (( current_score == best_score )); then
			best_matches+=($i)
		fi
	done

	# Secondary sort by release date when scores are equal
	if (( ${#best_matches[@]} > 1 )); then
		best_matches=($(printf '%s\n' "${best_matches[@]}" | while read i; do
			date=$(echo "$recordings" | ./jq -r ".[$i].releases[0].date")
			year=$(echo "$date" | grep -oE '[0-9]{4}' | head -1 || echo "9999")
			echo "$year $i"
		done | sort -n | cut -d' ' -f2))
	fi

	# Display all results
	print "Found $count result(s):"
	print

	for ((i=0; i<count; i++)); do
		is_best=" "
		if [[ " ${best_matches[*]} " = *" $i "* ]]; then
			is_best="→"
		fi
		
		results=$(echo "$recordings" | ./jq -r --arg i "$i" --arg is_best "$is_best"  '
			.[($i|tonumber)] as $rec |
			"\($is_best) [\($i|tonumber + 1)]\n" +
			"  Title:  \($rec.title)\n" +
			"  Artist: \($rec["artist-credit"][0].name)\n" +
			"  Album:  \($rec.releases[0].title // "Unknown")\n" +
			"  MBID:   \($rec["artist-credit"][0].artist.id)\n"
			')	
		
		if [ $i -eq ${best_matches[0]} ]; then
			print "$(tput bold)$results$(tput sgr0)"
		else	
			print "$(tput setaf 8)$results$(tput sgr0)"
		fi
		print
	done

	# Get genres for primary best match
	best_mbid=$(echo "$recordings" | ./jq -r ".[${best_matches[0]}][\"artist-credit\"][0].artist.id")
	[ -z "$best_mbid" ] && { print "Error: No valid MBID found for best match"; exit 1; }

	print "Fetching genres for best match (MBID: $best_mbid)"

	genres=$(./curl -f -s -A "MusicBrainzBot/1.0" \
		"https://musicbrainz.org/ws/2/artist/$best_mbid?inc=genres&fmt=json" 2>/dev/null | \
		./jq -r '[.genres | sort_by(-.count) | .[].name] | join(";")') || {
		print "Error: Failed to fetch genres"
		exit 1
	}
	# Print the genres
	print "${genres,,}" -o
	print ""
}

get-genres-deezer() {
    local max_retries=5
    local retry_delay=2

    print "Deezer"
    print "Searching: $artist - $title"

    encoded_url="https://api.deezer.com/search?q=artist:\"${artist// /%20}\"%20track:\"${title// /%20}\""

    # Function to perform a retryable curl call and validate JSON,
    # optionally check for an expected JSON key
    retry_curl() {
        local url="$1"
        local expected_key="${2:-}"  # optional second argument, e.g. "data"
        local attempt=1
        local response

        while (( attempt <= max_retries )); do
            response=$(./curl -s "$url")

            # DEBUG: uncomment next line to see raw response on each attempt
            # echo "DEBUG: Attempt $attempt response: $response" >&2

            # Check for valid JSON
            if echo "$response" | ./jq empty >/dev/null 2>&1; then
                # If expected_key is set, check for its presence
                if [ -z "$expected_key" ] || echo "$response" | ./jq "has(\"$expected_key\")" | grep -q true; then
                    echo "$response"
                    return 0
                fi
            fi

            # Check for rate limiting message
            if echo "$response" | grep -qi "rate limit"; then
                print "Rate limited by Deezer API, retrying in ${retry_delay}s (attempt $attempt/$max_retries)..."
            else
                print "Malformed or invalid JSON, retrying in ${retry_delay}s (attempt $attempt/$max_retries)..."
            fi

            ((attempt++))
            sleep $retry_delay
        done

        return 1
    }

    # Retryable search request, expect "data" key
    response=$(retry_curl "$encoded_url" "data") || {
        print "Failed to get valid search results from Deezer after $max_retries attempts."
        return 0
    }

    count=$(echo "$response" | ./jq '.data | length')
    [ "$count" -eq 0 ] && return 0

    print "Found $count result(s):"
    print

    for ((i=0; i<count; i++)); do
        is_best=" "
        if [ $i -eq 0 ]; then
            is_best="→"
        fi

        results=$(echo "$response" | ./jq -r --arg i "$i" --arg is_best "$is_best" '
            .data[$i|tonumber] as $rec |
            "\($is_best) [\($i|tonumber + 1)]\n" +
            "  Title:  \($rec.title)\n" +
            "  Artist: \($rec.artist.name)\n" +
            "  Album:  \($rec.album.title)\n" +
            "  ALID:   \($rec.album.id)\n"
        ')

        if [ $i -eq 0 ]; then
            print "$(tput bold)$results$(tput sgr0)"
        else
            print "$(tput setaf 8)$results$(tput sgr0)"
        fi
        print
    done

    album_id=$(echo "$response" | ./jq -r '.data[0].album.id')

    print "Fetching genres for best match (ALID: $album_id)"

    album_url="https://api.deezer.com/album/$album_id"

    # Retryable album details request, no expected key check (valid JSON only)
    album_details=$(retry_curl "$album_url") || {
        echo "DEBUG: Failed album details retrieval after $max_retries attempts. Last raw response:"
        echo "$album_details"
        print "Failed to get valid album details from Deezer after $max_retries attempts."
        return 0
    }

    genres=$(echo "$album_details" | ./jq -r 'if .genres.data and (.genres.data | length > 0) then [.genres.data[].name] | join(";") else "" end')
	[ -z "$genres" ] && return 0

    print "${genres,,}" -o
    print ""
}

get-genres-itunes() {

	print "iTunes"
	sleep 3
	print "Searching: $artist - $title"

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
	ENCODED_ARTIST=$(echo "$artist" | ./jq -sRr @uri)
	ENCODED_SONG=$(echo "$title" | ./jq -sRr @uri)

	# Make API request to the iTunes API
	url="https://itunes.apple.com/search?term=${ENCODED_SONG}+${ENCODED_ARTIST}&entity=song&limit=10"
	response=$(./curl -s "$url")

	# Get best matches
	best_matches=($(select_best_match "$response" "$artist" "$title"))

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
	genres=$(echo $response | ./jq -r '.results[0].primaryGenreName' | sed 's/\//;/')

	# Print the genres
	
	if [ "$genres" != "null" ]; then
		print "${genres,,}" -o
	fi
	print ""
}

# Replace the entire if-block with this:

# Try MusicBrainz first
genres=$(get-genres-musicbrainz)

# If empty, try Deezer
if [ -z "$genres" ]; then
    genres=$(get-genres-deezer)
fi

# If still empty, try iTunes
if [ -z "$genres" ]; then
    genres=$(get-genres-itunes)
fi

# Output the final result (empty if all failed)
print "$genres" -o