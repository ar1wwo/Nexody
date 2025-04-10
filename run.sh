#!/bin/bash

# Replace with your own Client ID and Client Secret
CLIENT_ID="c9d3a82d76744885b8e219f466e60370"
CLIENT_SECRET="0d52f2e6c353459aa994c11f08bfee1c"
PLAYLIST_ID="40Mx3bOxoddtOzRBZSf2Qf"
OUTPUT_FILE="playlist_tracks.csv"

# Get access token
ACCESS_TOKEN=$(./curl -s -X POST https://accounts.spotify.com/api/token \
  -d grant_type=client_credentials \
  -u "$CLIENT_ID:$CLIENT_SECRET" | ./jq -r '.access_token // empty')

# First, fetch all tracks from the playlist
TRACKS_JSON=$(./curl -s -X GET "https://api.spotify.com/v1/playlists/$PLAYLIST_ID/tracks" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

# Extract all unique artist IDs
ARTIST_IDS=$(echo "$TRACKS_JSON" | ./jq -r '.items[].track.artists[].id' | sort | uniq | tr '\n' ',' | sed 's/,$//')

# Fetch all artist details in one batch request
ARTISTS_DATA=$(./curl -s -X GET "https://api.spotify.com/v1/artists?ids=$ARTIST_IDS" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

# Create CSV file with header
echo "title,artists,artist,album,date,track,genres,length,albumart,spotifyid,filename" > "$OUTPUT_FILE"

# Process the tracks and append to CSV
echo "$TRACKS_JSON" | ./jq -r --argjson artists "$ARTISTS_DATA" '
  .items[] | 
  [
    (.track.name // ""),
    ([.track.artists[].name] | join(", ") // ""),
    (.track.artists[0].name // ""),
    (.track.album.name // ""),
    (.track.album.release_date // ""),
    (.track.track_number // ""),
    (
      (.track.artists // []) as $track_artists |
      ($artists.artists // []) | map({id: .id, genres: (.genres // [])}) |
      [.[] | select(.id as $id | $track_artists | any(.id == $id))] |
      [.[].genres] | flatten | unique | join(", ") // ""
    ),
    ((.track.duration_ms // 0) / 1000 | floor),
    (.track.album.images[0]?.url // ""),
    (.track.id // "")
  ] | @csv' >> "$OUTPUT_FILE"

echo "Playlist tracks saved to $OUTPUT_FILE"

./sldl "https://open.spotify.com/playlist/40Mx3bOxoddtOzRBZSf2Qf" --user wompy --pass wompy --log-file debug.txt 