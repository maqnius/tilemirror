# Build-only Docker image for creating mix release targeting CentOS 7
FROM centos:7

# Fix CentOS 7 EOL - switch to vault mirrors
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-* && \
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*


# Install EPEL and development tools
RUN yum install -y epel-release && \
    yum install -y \
    gcc \
    gcc-c++ \
    make \
    automake \
    autoconf \
    ncurses-devel \
    openssl-devel \
    wget \
    git \
    unzip && \
    yum clean all

# Install Erlang
ENV ERLANG_VERSION=26.2.1
RUN wget https://github.com/erlang/otp/releases/download/OTP-${ERLANG_VERSION}/otp_src_${ERLANG_VERSION}.tar.gz && \
    tar -xzf otp_src_${ERLANG_VERSION}.tar.gz && \
    cd otp_src_${ERLANG_VERSION} && \
    ./configure --without-javac && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf otp_src_${ERLANG_VERSION}*

# Install Elixir
ENV ELIXIR_VERSION=v1.19.4
RUN wget https://github.com/elixir-lang/elixir/releases/download/${ELIXIR_VERSION}/elixir-otp-26.zip && \
    unzip elixir-otp-26.zip -d /usr/local && \
    rm elixir-otp-26.zip

# Set UTF-8 locale to avoid encoding warnings
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force


# Set work directory
WORKDIR /build

# Default command shows how to use this image
CMD ["echo", "Mount your project and run: mix deps.get && MIX_ENV=prod mix release"]