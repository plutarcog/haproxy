FROM centos:centos7

ENV   HAPROXY_MJR_VERSION=2.1 \
      HAPROXY_VERSION=2.1.4 \
      HAPROXY_CONFIG='/usr/local/etc/haproxy/haproxy.cfg' \
      HAPROXY_ADDITIONAL_CONFIG='' \
      HAPROXY_PRE_RESTART_CMD='' \
      HAPROXY_POST_RESTART_CMD=''

RUN set -eux; \
  yum install -y epel-release; \
  yum update -y
  # Install build tools. Note: perl needed to compile openssl...
RUN set -eux; \
  yum install -y inotify-tools wget tar gzip make gcc perl pcre2-devel zlib-devel glibc-devel openssl-devel ca-certificates

  # Install newest openssl...
RUN set -eux; \
  wget -O /tmp/openssl.tgz https://www.openssl.org/source/openssl-1.1.1g.tar.gz; \
  tar -zxf /tmp/openssl.tgz -C /tmp; \
  cd /tmp/openssl-*; \
  ./config --prefix=/usr \
    --openssldir=/etc/ssl \
    --libdir=lib          \
    no-shared zlib-dynamic; \
  make -j$(getconf _NPROCESSORS_ONLN) V= && make install_sw; \
  cd && rm -rf /tmp/openssl*

  # Install Lua 5.3
RUN set -eux; \
  yum install -y readline-devel; \
  wget https://www.lua.org/ftp/lua-5.3.5.tar.gz; \
  tar -xzf lua-5.3.5.tar.gz; \
  cd lua-5.3.5; \
  make INSTALL_TOP=/opt/lua-5.3.5 linux install

  # Install HAProxy...
RUN set -eux; \
  wget -O haproxy.tar.gz http://www.haproxy.org/download/${HAPROXY_MJR_VERSION}/src/haproxy-${HAPROXY_VERSION}.tar.gz; \
  mkdir -p /usr/src/haproxy \
	&& tar -xzf haproxy.tar.gz -C /usr/src/haproxy --strip-components=1 \
	&& rm haproxy.tar.gz \
	\
	&& makeOpts=' \
		TARGET=linux-glibc \
		USE_GETADDRINFO=1 \
		USE_LUA=1 LUA_INC=/opt/lua-5.3.5/include LUA_LIB=/opt/lua-5.3.5/lib \
		USE_OPENSSL=1 \
		USE_PCRE2=1 USE_PCRE2_JIT=1 \
		USE_ZLIB=1 \
		ADDLIB=-lpthread \
		\
		EXTRA_OBJS=" \
# see https://github.com/docker-library/haproxy/issues/94#issuecomment-505673353 for more details about prometheus support
			contrib/prometheus-exporter/service-prometheus.o \
		" \
	' \
	&& nproc="$(nproc)" \
	&& eval "make -C /usr/src/haproxy -j '$nproc' all $makeOpts" \
	&& eval "make -C /usr/src/haproxy install-bin $makeOpts" \
	\
	&& mkdir -p /usr/local/etc/haproxy \
	&& cp -R /usr/src/haproxy/examples/errorfiles /usr/local/etc/haproxy/errors \
	&& rm -rf /usr/src/haproxy
	
# Generate dummy SSL cert for HAProxy...
RUN set -eux; \
  openssl genrsa -out /etc/ssl/dummy.key 2048; \
  openssl req -new -config /etc/pki/tls/openssl.cnf -key /etc/ssl/dummy.key -out /etc/ssl/dummy.csr -subj "/C=GB/L=London/O=Company Ltd/CN=haproxy"; \
  openssl x509 -req -days 3650 -in /etc/ssl/dummy.csr -signkey /etc/ssl/dummy.key -out /etc/ssl/dummy.crt; \
  cat /etc/ssl/dummy.crt /etc/ssl/dummy.key > /etc/ssl/dummy.pem; \
  # Clean up: build tools...
  yum remove -y make gcc pcre2-devel; \
  yum clean all && rm -rf /var/cache/yum

# https://www.haproxy.org/download/1.8/doc/management.txt
# "4. Stopping and restarting HAProxy"
# "when the SIGTERM signal is sent to the haproxy process, it immediately quits and all established connections are closed"
# "graceful stop is triggered when the SIGUSR1 signal is sent to the haproxy process"
STOPSIGNAL SIGUSR1

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
