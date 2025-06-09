#!/bin/bash

args=("$@")

# Source the function library
source ./functions.sh

# Parse config file
parse_config "nexody.cfg"

OUTPUT_FILE="tracks.csv"

# Get access token
ACCESS_TOKEN=$(./curl -s -X POST https://accounts.spotify.com/api/token \
  -d grant_type=client_credentials \
  -u "$SPOTIFY_ID:$SPOTIFY_SECRET" | ./jq -r '.access_token // empty')

# Initialize CSV
echo "title,artist,artists,album,date,track,genres,length,albumart,id" > "$OUTPUT_FILE"

offset=0
limit=40
total=1  # dummy value to enter the loop
delay=3  # seconds to wait if Retry-After header is missing

while [ "$offset" -lt "$total" ]; do
  # --- Retry-safe playlist request ---
  while :; do
    response=$(./curl -i -s -G "https://api.spotify.com/v1/playlists/$PLAYLIST_ID/tracks" \
      -d limit=$limit -d offset=$offset \
      -H "Authorization: Bearer $ACCESS_TOKEN")

    status=$(echo "$response" | head -n 1 | cut -d' ' -f2)

    if [ "$status" = "429" ]; then
      retry_after=$(echo "$response" | grep -i "Retry-After:" | awk '{print $2}' | tr -d '\r')
      retry_after=${retry_after:-$delay}
      echo "Rate limited (tracks), waiting $retry_after seconds..." >&2
      sleep "$retry_after"
    else
      break
    fi
  done

  # Strip headers from response
  response=$(echo "$response" | sed -e '1,/^\r$/d')

  # On the first iteration, get total number of tracks
  total=$(echo "$response" | ./jq -r '.total // 0')

  # Extract all unique artist IDs for this batch
  artist_ids=$(echo "$response" | ./jq -r '.items[].track.artists[].id' | sort -u | paste -sd, -)

  # --- Retry-safe artist genre fetch ---
  while :; do
    artists_data=$(./curl -i -s -G "https://api.spotify.com/v1/artists" \
      --data-urlencode "ids=$artist_ids" \
      -H "Authorization: Bearer $ACCESS_TOKEN")

    artist_status=$(echo "$artists_data" | head -n 1 | cut -d' ' -f2)

    if [ "$artist_status" = "429" ]; then
      retry_after=$(echo "$artists_data" | grep -i "Retry-After:" | awk '{print $2}' | tr -d '\r')
      retry_after=${retry_after:-5}
      echo "Rate limited (artists), waiting $retry_after seconds..." >&2
      sleep "$retry_after"
    else
      break
    fi
  done

  # Strip headers from artist response
  artists_data=$(echo "$artists_data" | sed -e '1,/^\r$/d')

  # Append track data with genres to CSV
echo "$response" | ./jq -r --argjson artists "$artists_data" '
  .items[] | 
  [
    (.track.name // ""),
    (.track.artists[0].name // ""),
    ([.track.artists[].name] | join(";") // ""),
    (.track.album.name // ""),
    (.track.album.release_date // ""),
    (.track.track_number // "" | tostring),
    (.track.disc_number // "" | tostring),
    (
      (.track.artists // []) as $track_artists |
      ($artists.artists // []) | map({id: .id, genres: (.genres // [])}) |
      [.[] | select(.id as $id | $track_artists | any(.id == $id))] |
      [.[].genres] | flatten | unique | join(";") // ""
    ),
    ((.track.duration_ms // 0) / 1000 | floor | tostring),
    (.track.album.images[0]?.url // ""),
    (.track.id // "")
  ] | @csv' >> "$OUTPUT_FILE"

  offset=$((offset + limit))
done

# Process substitution avoids subshell for the while loop
while IFS=$'\x01' read -r title artist artists album date track disc genres length albumart id; do

    sanitized_artist=$(sanitize "$artist")
	sanitized_title=$(sanitize "$title")
    sanitized_album=$(sanitize "$album")
	
	filename="$LIBRARY_PATH/$sanitized_artist/$sanitized_album/$sanitized_title"

	oldtrack=$(./ffprobe -v error -show_entries format_tags=track -of default=noprint_wrappers=1:nokey=1 "${filename}.flac")
	olddisc=$(./ffprobe -v error -show_entries format_tags=disc -of default=noprint_wrappers=1:nokey=1 "${filename}.flac")

	if [ -z "$oldtrack" ] || [ -z "$olddisc" ]; then
	
	echo "$sanitized_artist/$sanitized_album/$sanitized_title"
	echo "track = $oldtrack > $track"
	echo "disc = $olddisc > $disc"
	echo ""
	
	./ffmpeg -nostdin -loglevel error -y -i "${filename}.flac" \
	  -map 0 -c copy \
	  -metadata track="$track" \
	  -metadata disc="$disc" \
	  "${filename}.tmp.flac" && mv -f "${filename}.tmp.flac" "${filename}.flac"

	fi

done < <(sed 's/","/\x01/g' "$OUTPUT_FILE" | tail -n +2)  # sed runs here, but in a subshell (safe)