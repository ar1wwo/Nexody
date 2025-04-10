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
    ./jq -r '[.genres | sort_by(-.count) | .[].name] | join(", ")') || {
    print "Error: Failed to fetch genres"
    exit 1
}

print "${genres,,}" -o