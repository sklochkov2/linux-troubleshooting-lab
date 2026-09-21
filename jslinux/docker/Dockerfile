FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bc \
        bison \
        build-essential \
        ca-certificates \
        cpio \
        curl \
        file \
        flex \
        git \
        libncurses-dev \
        patch \
        perl \
        python3 \
        rsync \
        unzip \
        wget \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
