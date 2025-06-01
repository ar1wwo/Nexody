# Nexody

Nexody is a script meant to ease users into the creation of their own music library.<br>
It automatically tags and downloads tracks and provides a fallback for tracks that are less known.

Relies on SoulSeek for tracks downloads, it requires a Spotify Playlist for search queries<br> (Sldl allows other means to do so, but it's currently unsupported with Nexody).<br>
Relies on Spotify, ITunes and MusicBrainz for tag searching and autotagging.

### Configuration File Contains Several Variables that need to be modified in order to run the script properly.
<br>
<ins>Configuration File:</ins>
<br>
<br>
The Name of the Folder Where the Songs Will be Saved

>LIBRARY_PATH = 

The Spotify Playlist ID

>PLAYLIST_ID = 

Spotify ID and Secret are required, for more info on how to obtain them (https://developer.spotify.com/documentation/web-api)

>SPOTIFY_ID = 

>SPOTIFY_SECRET = 

SoulSeek User and Password

>SOULSEEK_USER = 

>SOULSEEK_PASSWORD = 

<br>
<br>

Nedoxy is made possible thanks to these open source projects: [Sldl](https://github.com/fiso64/slsk-batchdl), [Yt-dlp](https://github.com/yt-dlp), [Ffmpeg](https://github.com/FFmpeg/FFmpeg).

### Binaries of Ffmpeg, Sldl and Yt-dlp are required and must be in the same folder as Nexody.<br>
### Ffmpeg must be compiled with the following libraries: libfdk_aac, libmp3lame.

To run, give the scripts permission and type ./Nexody in bash
