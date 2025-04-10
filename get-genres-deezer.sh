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

print "Deezer"
sleep 1.5
print "Searching: $artist_name - $song_title"

encoded_url="https://api.deezer.com/search?q=artist:\"${artist_name// /%20}\"%20track:\"${song_title// /%20}\""

# Send the request and capture the response
response=$(./curl -s "$encoded_url")

# Get the total number of results
count=$(echo "$response" | ./jq '.data | length')

print "Found $count result(s):"

# Loop through the results and format them
print
for ((i=0; i<count; i++)); do
    # Always mark the first entry as 'BEST MATCH'
    is_best=" "
    if [ $i -eq 0 ]; then
        is_best="→"
    fi
    
    # Get the results using ./jq and inject the necessary variables
    results=$(echo "$response" | ./jq -r --arg i "$i" --arg is_best "$is_best" '
        .data[$i|tonumber] as $rec |
        "\($is_best) [\($i|tonumber + 1)]\n" +
        "  Title:  \($rec.title)\n" +
        "  Artist: \($rec.artist.name)\n" +
        "  Album:  \($rec.album.title)\n" +
		"  ALID:   \($rec.album.id)\n"
')
    
    # Apply formatting based on whether it's the best match or not
    if [ $i -eq 0 ]; then
        print "$(tput bold)$results$(tput sgr0)"  # Best match in bold and green
    else
        print "$(tput setaf 8)$results$(tput sgr0)"  # Other results in gray
    fi
    print
done

# Extract the first album ID using ./jq and print it
album_id=$(echo "$response" | ./jq -r '.data[0].album.id')

# Print the album ID
print "Fetching genres for best match (ALID: $album_id)"

# Fetch album details using the album ID
album_details=$(./curl -s "https://api.deezer.com/album/$album_id")

# Extract genres from the album details
genres=$(echo "$album_details" | ./jq -r '[.genres.data[].name] | join(", ")')

# Print the genres
print "${genres,,}" -o