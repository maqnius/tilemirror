build:
    docker run --rm \
    -v $(pwd):/build \
    -w /build \
    elixir-centos7-builder:latest \
    sh -c "mix deps.get && MIX_ENV=prod mix release --overwrite"

deploy ssh_user ssh_host:
    rsync -ravz _build/prod/rel/tilemirror {{ ssh_host }}:~/
    ssh {{ ssh_user }}@{{ssh_host}} 'supervisorctl restart tilemirror'

create_build_env:
    docker build -t elixir-centos7-builder:latest -f elixir-centos7-builder.dockerfile .
