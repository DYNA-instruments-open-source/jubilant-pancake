ARG BSPINPUT_TAG
FROM ${BSPINPUT_TAG}
LABEL maintainer="Johannes Lode (at) dynainstruments.com"
ARG MERGE_JOBS

ENV TARGET_KERNEL_VERSION=4.19.72-gentoo

COPY bsp-utilities/ /

# install missing gcc libs, create kernel directories and links, configure system
RUN mkdir -p /usr/${TARGET}/mnt/gentoo/$(head -n1 /usr/${TARGET}/etc/ld.so.conf.d/??gcc-${TARGET}.conf) && \
    cp -a /usr/${TARGET}/$(head -n1 /usr/${TARGET}/etc/ld.so.conf.d/??gcc-${TARGET}.conf)/lib*.so* /usr/${TARGET}/mnt/gentoo/$(head -n1 /usr/${TARGET}/etc/ld.so.conf.d/??gcc-${TARGET}.conf)/ && \
    head -n1 /usr/${TARGET}/etc/ld.so.conf.d/??gcc-${TARGET}.conf >/usr/${TARGET}/mnt/gentoo/etc/ld.so.conf.d/05gcc-${TARGET}.conf && \
    mkdir -p /usr/${TARGET}/usr/src/build-${TARGET}-imx6ull-colibri && \
    mkdir -p /usr/${TARGET}/usr/src/bsp-kernel-patches-${TARGET_KERNEL_VERSION} && \
    ln -sfT /usr/${TARGET}/usr/src/build-${TARGET}-imx6ull-colibri /usr/${TARGET}/usr/src/build && \
    ln -sfT /usr/${TARGET}/usr/src/build-${TARGET}-imx6ull-colibri /usr/src/build-${TARGET}-imx6ull-colibri && \
    ln -sfT /usr/${TARGET}/usr/src/build /usr/src/build && \
    ln -sfT /usr/${TARGET}/usr/src/linux-${TARGET_KERNEL_VERSION} /usr/src/linux && \
    ln -sfT ../bsp-kernel-patches-${TARGET_KERNEL_VERSION} /usr/${TARGET}/usr/src/linux-${TARGET_KERNEL_VERSION}/patches && \
    echo YES | etc-update --automode -9 && \
    mkdir -p /usr/src/build-${TARGET}-imx6ull-colibri && \
    chmod +x /usr/local/bin/create-reduced-rootfs /sbin/installkernel && \
    ln -sfT /usr/${TARGET}/mnt/gentoo /mnt/gentoo && \
    ln -sfT /usr/${TARGET}/mnt/reduced-rootfs /mnt/reduced-rootfs && \
    mkdir -p /usr/${TARGET}/mnt/images && \
    ln -sfT /usr/${TARGET}/mnt/images /mnt/images && \
    ln -sfT /bin/bash /usr/${TARGET}/mnt/gentoo/bin/sh && \
    mkdir -p /usr/${TARGET}/mnt/gentoo/{boot/dtbs,opt,dev,dev/shm,sys,proc,root,mnt} /usr/${TARGET}/mnt/reduced-rootfs && \
    mkdir -p /tmp/screen /usr/${TARGET}/tmp/screen && chmod 777 /tmp/screen /usr/${TARGET}/tmp/screen && \
    mkdir -p /usr/${TARGET}/mnt/gentoo/tmp/screen && chmod 777 /usr/${TARGET}/mnt/gentoo/tmp/screen && \
    rm -f /usr/${TARGET}/mnt/gentoo/etc/runlevels/boot/{save-keymaps,keymaps,save-termencoding,termencoding,binfmt} && \
    rm -f /usr/${TARGET}/mnt/gentoo/etc/runlevels/default/netmount && \
    sed -i -E -e 's/^#+(PermitRootLogin *.*)/#\1/g' -e '/^#PermitRootLogin *.*/a PermitRootLogin yes' /mnt/gentoo/etc/ssh/sshd_config && \
    sed -i -E 's/^#rc_need *= *"!rpc.idmapd" */rc_need="!rpc.idmapd"/g' /mnt/gentoo/etc/conf.d/nfsclient && \
    sed -i -E -e's/^.*rc_interactive *= *".*" */rc_interactive="YES"/g' -e's/^.*rc_sys *= *".*".*/rc_sys=""/g' -e's/^.*rc_parallel *= *".*" */rc_parallel="YES"/g' /mnt/gentoo/etc/rc.conf && \
    sed -i -e '/grep --colour=auto/d' /etc/bash/bashrc && \
    groupadd -P /mnt/gentoo -r -g 22 sshd && \
    useradd -P /mnt/gentoo -r -u 22 -g 22 -c "Privilege separation user" -d /var/empty -s /sbin/nologin sshd && \
    rm -f /usr/${TARGET}/mnt/gentoo/etc/runlevels/boot/hwclock && \
    rm -f /usr/${TARGET}/mnt/gentoo/sbin/ip && \
    ln -sf /etc/init.d/swclock /usr/${TARGET}/mnt/gentoo/etc/runlevels/boot/ && \
    ln -sfT net.lo /usr/${TARGET}/mnt/gentoo/etc/init.d/net.eth0 && \
    ln -sf /etc/init.d/mdev /usr/${TARGET}/mnt/gentoo/etc/runlevels/sysinit/ && \
    ln -sf /etc/init.d/{net.eth0,sshd,rngd,dcron,busybox-syslogd} /usr/${TARGET}/mnt/gentoo/etc/runlevels/default/ && \
    ln -sfT target-xkmake /usr/local/bin/${TARGET}-xkmake && \
    chmod +x /usr/local/bin/*-xkmake /usr/local/bin/create-* && \
    echo -e '\nextra_commands="save_now"' >>/usr/${TARGET}/mnt/gentoo/etc/init.d/swclock && \
    echo -e 'description_save_now="save the current kernel time"\n' >>/usr/${TARGET}/mnt/gentoo/etc/init.d/swclock && \
    echo -e 'save_now()\n{\n        ebegin "Saving current time"' >>/usr/${TARGET}/mnt/gentoo/etc/init.d/swclock && \
    echo -e '        swclock --save' >>/usr/${TARGET}/mnt/gentoo/etc/init.d/swclock && \
    echo -e '        eend $?\n}\n' >>/usr/${TARGET}/mnt/gentoo/etc/init.d/swclock

COPY ubiconfig.ini empty /usr/${TARGET}/mnt/images/
COPY kernelconfig-imx6ull-colibri /usr/${TARGET}/usr/src/build-${TARGET}-imx6ull-colibri/.config
COPY bsp-kernel-patches-${TARGET_KERNEL_VERSION} /usr/${TARGET}/usr/src/bsp-kernel-patches-${TARGET_KERNEL_VERSION}
RUN cd /usr/${TARGET}/usr/src/linux && quilt push -a

# put some preconfigured files into the target directory
COPY bsp-target-files/ /usr/${TARGET}/mnt/gentoo

# make the build directory a volume for performance reasons
VOLUME /usr/${TARGET}/usr/src/build-${TARGET}-imx6ull-colibri

# do this just before the volume declaration for /mnt/gentoo, to have the generated modules in the tree
RUN cd /usr/${TARGET}/usr/src/linux && \
    ${TARGET}-xkmake -j ${MERGE_JOBS:-2} zImage modules dtbs && \
    ${TARGET}-xkmake modules_install

# set root password, create fstab, set the hostname, disable colors for OpenRC, start local services verbose
RUN echo "root:" | chpasswd -R /usr/${TARGET}/mnt/gentoo && \
    cp /usr/${TARGET}/mnt/gentoo/etc/fstab-nandflash /usr/${TARGET}/mnt/gentoo/etc/fstab && \
    sed -i -E 's/^hostname=.*/hostname="DYNAcolibri"/g' /mnt/gentoo/etc/conf.d/hostname && \
    sed -i -E 's/^ *# *rc_nocolor=.*$/rc_nocolor=YES/g' /mnt/gentoo/etc/rc.conf && \
    echo -e 'rc_verbose=yes\noutput_logger="logger -e"\nerror_logger="logger -e"' >>/mnt/gentoo/etc/conf.d/local

VOLUME /usr/${TARGET}/mnt/gentoo
VOLUME /usr/${TARGET}/mnt/reduced-rootfs
VOLUME /usr/${TARGET}/mnt/images

CMD /bin/bash -il
