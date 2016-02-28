FROM ubuntu:14.04
MAINTAINER Ian Blenke <ian@blenke.com>

RUN apt-get update
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get install -y dpkg-dev

ADD rtpengine/ /rtpengine
WORKDIR /rtpengine
RUN touch ./debian/flavors/no_ngcp

RUN cd /rtpengine ; \
    export DEBIAN_FRONTEND=noninteractive ; \
    apt-get install -y debhelper iptables-dev libcurl4-openssl-dev libglib2.0-dev libhiredis-dev libpcre3-dev libssl-dev libxmlrpc-core-c3-dev markdown zlib1g-dev module-assistant dkms gettext && \
    dpkg-checkbuilddeps && \
    dpkg-buildpackage -b -us -uc
RUN export DEBIAN_FRONTEND=noninteractive ; \
    dpkg -i /*.deb

# Optionally build the kernel module for the docker build host if we can
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update -y && \
    apt-get install -y linux-headers-$(uname -r) linux-image-$(uname -r) && \
    ( \
      module-assistant update && \
      module-assistant auto-install ngcp-rtpengine-kernel-source ) || true

ADD run.sh /run.sh
RUN chmod 755 /run.sh

CMD /run.sh

