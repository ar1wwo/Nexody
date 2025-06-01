# Nexody

Nexody is a script meant to ease users into the creation of their own music library.
It automatically tags and downloads tracks and provides a fallback for tracks that are less known.

Relies on SoulSeek for tracks downloads, it requires a Spotify Playlist for search queries (Sldl allows other means to do so, but it's currently unsupported with Nexody).
Relies on Spotify, ITunes and MusicBrainz for tag searching and autotagging.

### Configuration File Contains Several Variables that need to be modified in order to run the script properly.
<br>
<ins>Configuration File:</ins>

The Name of the Folder Where the Songs Will be Saved

>LIBRARY_PATH = Library

The Spotify Playlist ID

>PLAYLIST_ID = 40Mx3bOxoddtOzRBZSf2Qf

Spotify ID and Secret are required, for more info on how to obtain them (https://developer.spotify.com/documentation/web-api)

>SPOTIFY_ID = c9d3a82d76744885b8e219f466e60370

>SPOTIFY_SECRET = 0d52f2e6c353459aa994c11f08bfee1c

SoulSeek User and Password

>SOULSEEK_USER = dzk

>SOULSEEK_PASSWORD = dzk



This program is made possible thanks to these open source projects: [Sldl](https://github.com/fiso64/slsk-batchdl), [Yt-dlp](https://github.com/yt-dlp), [Ffmpeg](https://github.com/FFmpeg/FFmpeg).

### Binaries of Ffmpeg, Sldl and Yt-dlp are required and must be in the same folder as Nexody.
### Ffmpeg must be compiled with the following libraries: libfdk_aac, libmp3lame.

To run, give the script permission and type ./Nexody in bash
