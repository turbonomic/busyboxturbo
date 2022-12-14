#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM debian:bullseye-slim

RUN set -eux; \
	apt-get update; \
	apt-get install -y \
		bzip2 \
		curl \
		gcc \
		gnupg dirmngr \
		make \
		patch \
		git \
	; \
	rm -rf /var/lib/apt/lists/*

RUN set -eux; \
	git clone https://github.com/turbonomic/busyboxturbo.git busybox; \
	mkdir -p /usr/src/busybox; \
	cp -rf busybox/* /usr/src/busybox/ 

WORKDIR /usr/src/busybox

RUN set -eux; \
	\
	setConfs=' \
		CONFIG_AR=y \
		CONFIG_FEATURE_AR_CREATE=y \
		CONFIG_FEATURE_AR_LONG_FILENAMES=y \
# CONFIG_LAST_SUPPORTED_WCHAR: see https://github.com/docker-library/busybox/issues/13 (UTF-8 input)
		CONFIG_LAST_SUPPORTED_WCHAR=0 \
# As long as we rely on libnss (see below), we have to have libc.so anyhow, so we've removed CONFIG_STATIC here... :cry:
	'; \
	\
	unsetConfs=' \
		CONFIG_FEATURE_SYNC_FANCY \
	'; \
	\
	make defconfig; \
	\
	for conf in $unsetConfs; do \
		sed -i \
			-e "s!^$conf=.*\$!# $conf is not set!" \
			.config; \
	done; \
	\
	for confV in $setConfs; do \
		conf="${confV%=*}"; \
		sed -i \
			-e "s!^$conf=.*\$!$confV!" \
			-e "s!^# $conf is not set\$!$confV!" \
			.config; \
		if ! grep -q "^$confV\$" .config; then \
			echo "$confV" >> .config; \
		fi; \
	done; \
	\
	make oldconfig; \
	\
# trust, but verify
	for conf in $unsetConfs; do \
		! grep -q "^$conf=" .config; \
	done; \
	for confV in $setConfs; do \
		grep -q "^$confV\$" .config; \
	done

RUN set -eux; \
	nproc="$(nproc)"; \
	make -j "$nproc" busybox; \
	./busybox --help; \
	mkdir -p rootfs/bin; \
	ln -vL busybox rootfs/bin/; \
	\
# copy "getconf" from Debian
	getconf="$(which getconf)"; \
	ln -vL "$getconf" rootfs/bin/getconf; \
	\
# hack hack hack hack hack
# with glibc, busybox (static or not) uses libnss for DNS resolution :(
	mkdir -p rootfs/etc; \
	cp /etc/nsswitch.conf rootfs/etc/; \
	mkdir -p rootfs/lib; \
	ln -sT lib rootfs/lib64; \
	gccMultiarch="$(gcc -print-multiarch)"; \
	set -- \
		rootfs/bin/busybox \
		rootfs/bin/getconf \
		/lib/"$gccMultiarch"/libnss*.so.* \
# libpthread is part of glibc: https://stackoverflow.com/a/11210463/433558
		/lib/"$gccMultiarch"/libpthread*.so.* \
	; \
	while [ "$#" -gt 0 ]; do \
		f="$1"; shift; \
		fn="$(basename "$f")"; \
		if [ -e "rootfs/lib/$fn" ]; then continue; fi; \
		if [ "${f#rootfs/}" = "$f" ]; then \
			if [ "${fn#ld-}" = "$fn" ]; then \
				ln -vL "$f" "rootfs/lib/$fn"; \
			else \
				cp -v "$f" "rootfs/lib/$fn"; \
			fi; \
		fi; \
		ldd="$(ldd "$f" | awk ' \
			$1 ~ /^\// { print $1; next } \
			$2 == "=>" && $3 ~ /^\// { print $3; next } \
		')"; \
		set -- "$@" $ldd; \
	done; \
	chroot rootfs /bin/getconf _NPROCESSORS_ONLN; \
	\
	chroot rootfs /bin/busybox --install /bin

# create missing home directories
RUN set -eux; \
	cd rootfs; \
	for userHome in $(awk -F ':' '{ print $3 ":" $4 "=" $6 }' etc/passwd); do \
		user="${userHome%%=*}"; \
		home="${userHome#*=}"; \
		home="./${home#/}"; \
		if [ ! -d "$home" ]; then \
			mkdir -p "$home"; \
			chown "$user" "$home"; \
			chmod 755 "$home"; \
		fi; \
	done

# test and make sure it works
RUN chroot rootfs /bin/sh -xec 'true'

# ensure correct timezone (UTC)
RUN set -eux; \
	ln -vL /usr/share/zoneinfo/UTC rootfs/etc/localtime; \
	[ "$(chroot rootfs date +%Z)" = 'UTC' ]

