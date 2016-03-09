#! /bin/sh
set -x
RUNTIME=${1:-rtpengine}

if [ -n "${FLUSH_IPTABLES}" ] ; then
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  iptables -t nat -F
  iptables -t mangle -F
  iptables -F
  iptables -X
fi

if [ -n "${UNLOAD_MODULE}" ] ; then
  rmmod xt_RTPENGINE
fi

if lsmod | grep xt_RTPENGINE || modprobe xt_RTPENGINE; then
  echo "rtpengine kernel module already loaded."
else
  if which apt-get ; then
    # Build the kernel module for the docker run host
    apt-get update -y
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y linux-headers-$(uname -r) linux-image-$(uname -r)

    module-assistant update
    module-assistant auto-install ngcp-rtpengine-kernel-source
    modprobe xt_RTPENGINE
  else
    if which dnf || which yum ; then
      cd /rtpengine/daemon
      make
      cp -u rtpengine /usr/local/bin/
      cd /rtpengine/iptables-extension
      make
      cp -u libxt_RTPENGINE.so /lib64/xtables
      cd /rtpengine/kernel-module
      make
      cp -u xt_RTPENGINE.ko "/lib/modules/$(uname -r)/extra"
      depmod -a
    else
      echo "This script is not running on debian/ubuntu/centus/fedora, cannot attempt to build kernel module"
      exit 1
    fi
  fi
fi

# Gradually fill the options of the command rtpengine which starts the RTPEngine daemon
# The variables used are sourced from the configuration file rtpengine-conf

OPTIONS=""

if [ -z "$INTERFACES" ]; then

  # Discover public and private IP for this instance
  export PRIVATE_IPV4="${PRIVATE_IPV4:-$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)}"
  [ -n "$PUBLIC_IPV4" ] || \
    PUBLIC_IPV4="$(curl --fail -qs whatismyip.akamai.com)"
  #    PUBLIC_IPV4="$(curl --fail -qsH 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)}"
  #    PUBLIC_IPV4="$(curl --fail -qs http://169.254.169.254/2014-11-05/meta-data/public-ipv4)"
  #    PUBLIC_IPV4="$(curl --fail -qs ipinfo.io/ip)"
  #    PUBLIC_IPV4="$(curl --fail -qs ipecho.net/plain)"
  export PUBLIC_IPV4

  export PUBLIC_IPV6="${PUBLIC_IPV6:-$(ip -6 addr show $(ip -6 route show default | grep -e '^default' | awk '{print $5}') | grep inet6 | grep global | awk '{print $2}' | grep -v -e '^::' | cut -d/ -f1)}"

  INTERFACES="${PRIVATE_IPV4}!${PUBLIC_IPV4} ${PUBLIC_IPV6}"
fi

for interface in $INTERFACES; do
	OPTIONS="$OPTIONS --interface=$interface"
done

mkdir -p /etc/default
if [ ! -z "$TABLE" ]; then
	echo "TABLE=$TABLE" > /etc/default/rtpengine-table
fi

[ -z "$LISTEN_TCP" ] || OPTIONS="$OPTIONS --listen-tcp=$LISTEN_TCP"
[ -z "$LISTEN_UDP" ] || OPTIONS="$OPTIONS --listen-udp=$LISTEN_UDP"
[ -z "$LISTEN_NG" ] || OPTIONS="$OPTIONS --listen-ng=$LISTEN_NG"
[ -z "$LISTEN_CLI" ] || OPTIONS="$OPTIONS --listen-cli=$LISTEN_CLI"
[ -z "$TIMEOUT" ] || OPTIONS="$OPTIONS --timeout=$TIMEOUT"
[ -z "$SILENT_TIMEOUT" ] || OPTIONS="$OPTIONS --silent-timeout=$SILENT_TIMEOUT"
[ -z "$PIDFILE" ] || OPTIONS="$OPTIONS --pidfile=$PIDFILE"
[ -z "$TOS" ] || OPTIONS="$OPTIONS --tos=$TOS"
[ -z "$PORT_MIN" ] || OPTIONS="$OPTIONS --port-min=$PORT_MIN"
[ -z "$PORT_MAX" ] || OPTIONS="$OPTIONS --port-max=$PORT_MAX"
[ -z "$REDIS" ] || OPTIONS="$OPTIONS --redis=$REDIS"
[ -z "$REDIS_DB" ] || OPTIONS="$OPTIONS --redis-db=$REDIS_DB"
[ -z "$REDIS_READ" ] || OPTIONS="$OPTIONS --redis-read=$REDIS_READ"
[ -z "$REDIS_READ_DB" ] || OPTIONS="$OPTIONS --redis-read-db=$REDIS_READ_DB"
[ -z "$REDIS_WRITE" ] || OPTIONS="$OPTIONS --redis-write=$REDIS_WRITE"
[ -z "$REDIS_WRITE_DB" ] || OPTIONS="$OPTIONS --redis-write-db=$REDIS_WRITE_DB"
[ -z "$B2B_URL" ] || OPTIONS="$OPTIONS --b2b-url=$B2B_URL"
[ -z "$NO_FALLBACK" -o \( "$NO_FALLBACK" != "1" -a "$NO_FALLBACK" != "yes" \) ] || OPTIONS="$OPTIONS --no-fallback"
OPTIONS="$OPTIONS --table=$TABLE"
[ -z "$LOG_LEVEL" ] || OPTIONS="$OPTIONS --log-level=$LOG_LEVEL"
[ -z "$LOG_FACILITY" ] || OPTIONS="$OPTIONS --log-facility=$LOG_FACILITY"
[ -z "$LOG_FACILITY_CDR" ] || OPTIONS="$OPTIONS --log-facility-cdr=$LOG_FACILITY_CDR"
[ -z "$LOG_FACILITY_RTCP" ] || OPTIONS="$OPTIONS --log-facility-rtcp=$LOG_FACILITY_RTCP"
[ -z "$NUM_THREADS" ] || OPTIONS="$OPTIONS --num-threads=$NUM_THREADS"
[ -z "$DELETE_DELAY" ] || OPTIONS="$OPTIONS --delete-delay=$DELETE_DELAY"
[ -z "$GRAPHITE" ] || OPTIONS="$OPTIONS --graphite=$GRAPHITE"
[ -z "$GRAPHITE_INTERVAL" ] || OPTIONS="$OPTIONS --graphite-interval=$GRAPHITE_INTERVAL"
[ -z "$GRAPHITE_PREFIX" ] || OPTIONS="$OPTIONS --graphite-prefix=$GRAPHITE_PREFIX"
[ -z "$MAX_SESSIONS" ] || OPTIONS="$OPTIONS --max-sessions=$MAX_SESSIONS"

if test "$FORK" = "no" ; then
	OPTIONS="$OPTIONS --foreground"
fi

set +e
if [ -e /proc/rtpengine/control ]; then
	echo "del $TABLE" > /proc/rtpengine/control 2>/dev/null
fi
# Freshly add the iptables rules to forward the udp packets to the iptables-extension "RTPEngine":
# Remember iptables table = chains, rules stored in the chains
# -N (create a new chain with the name rtpengine)
iptables -N rtpengine 2> /dev/null

# -D: Delete the rule for the target "rtpengine" if exists. -j (target): chain name or extension name 
# from the table "filter" (the default -without the option '-t') 
iptables -D INPUT -j rtpengine 2> /dev/null
# Add the rule again so the packets will go to rtpengine chain after the (filter-INPUT) hook point.
iptables -I INPUT -j rtpengine
# Delete and Insert a rule in the rtpengine chain to forward the UDP traffic 	
iptables -D rtpengine -p udp -j RTPENGINE --id "$TABLE" 2>/dev/null
iptables -I rtpengine -p udp -j RTPENGINE --id "$TABLE"
iptables-save > /etc/iptables.rules

# The same for IPv6
ip6tables -N rtpengine 2> /dev/null
ip6tables -D INPUT -j rtpengine 2> /dev/null
ip6tables -I INPUT -j rtpengine
ip6tables -D rtpengine -p udp -j RTPENGINE --id "$TABLE" 2>/dev/null
ip6tables -I rtpengine -p udp -j RTPENGINE --id "$TABLE"
ip6tables-save > /etc/ip6tables.rules

set -x

exec $RUNTIME $OPTIONS
