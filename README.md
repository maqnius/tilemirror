# Tilemirror for Uberspace Hosts

This elixir application mirrors the tiles served from a MapTile account using a file cache.

This helps to serve the tiles on your page from the origin server (no consent needed) while sparing the MapTile servers.

The maps included in a webpage mostly load the same few tiles, so no need for a roundtrip around the globe.


# Quickstart

1. Build and deploy the application

```sh
# create centos docker container serving as the build env
$ just create_build_env 
# build the application in the docker container
$ just build
# rsync the build assets to the tilemirror home folder and restarts the service
$ just deploy <ssh-user> <ssh-host>
```


2. Create service script
   
```ini
# etc/services.d/tilemirror.ini
[program:tilemirror]
directory=/home/<user>/tilemirror/
command=/home/<user>/tilemirror/bin/tilemirror start
environment=MAP_TILER_API_KEY=<api_key>
startsecs=2
```

3. Start the service file

```sh
$ supervisorctl reread
$ supervisorctl update
```

4. Connect the `_tile/` path to `0.0.0.0:4000`

```sh
$ uberspace web backend set <host>/tiles --http --port 4000
```

Your tiles should now be served from `/_tile/10/532/340.webp` or `/_tile/10/532/340.png`.
