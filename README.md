# docker-rtpengine

This is SIPWise rtpengine (previously: rtpproxy-ng, and before that: mediaproxy-ng) properly dockerified as a first-class citizen under the upstream project's preferred linux variant.

Parts of this project were borrowed in part from Binan/rtpengine-docker

## Files

- `Dockerfile*` properly builds a first-class rtpengine runtime from source
- `Makefile` merely calls `docker-compose build` and `docker-compose up` for local iteration convenience.
- `README.md` is the file you are reading right now.
- `docker-compose.yml` is a v2 config example, with some pre-defined defaults and a list of environment variables.
- `rtpengine/` submodule tree that is currently pointing at the master branch which just recently had PR #77 applied.
- `run.sh` script converts these environment variables into rtpengine daemon command-line options.

## Note:

This repository assumes that the resultant docker container will be run as privileged with host network stack and will be responsible for building and running the kernel module as well as the iptables rules.

## Build and Run

First, initialize the git submodules:

    git submodule update --init --recursive

If you are running an Ubuntu, Debian, Centos, or Fedora docker host, you should now be able to:

    docker-compose up

After this first build, though, you'll want to do subsequent updated builds using:

    docker-compose build
    docker-compose up --force-recreate

If you are running any other linux flavor as your docker host, this repository is not going to work for you as-is.

Why? There are two docker phases to be concerned with here.

- "build" time includes the `Dockerfile` and whatever is included in the docker image
- "run" time includes the build image above, and the `run.sh` script that is included inside that image.

Both the `Dockerfile` and the `run.sh` script will attempt to build a DKMS kernel module for rtpengine based on `uname -r`.

## At build time

Whatever the `uname -r` is at "build" time, the kernel version headers and kernel module for whatever docker host was used to build this image will try and use that version.

The `FROM` line of the `Dockerfile` in this project is `centos7`, which means that any build host that is not also Centos7 will silently skip including that as part of the docker build (see the "`|| true`" in the `Dockerfile` for that step).

All this is really doing is pre-building a kernel module for you to use at docker run time. This is a time-saver, but is not necessary.

## At run time

Regardless of the linux docker host flavor you _build_ this on, you should still be able to _run_ this on any same Ubuntu or Debian flavor derivative host version, and it should properly build the DKMS kernel before loading it and running the rtpengine daemon. This does take a little time.

Because the `Dockerfile` and `run.sh` script assume Ubuntu/Debian tooling, this will not work for any other linux docker host flavor.


