# DYNA Linux for Colibri i.MX6ULL

An all-in-one docker based build system for Toradex Colibri iMX6ULL module Linux kernel, FDT, root-fs and application software.

This is a build system for the DYNA Linux root-FS on Toradex Colibri iMX6ULL 512MB IT.

It can be used for building the kernel and its modules together with the device trees for the
DYNA Instruments base boards.

It can be used for creating the minimal root-FS as a volume.

It can be used for creating the combined UBI flash image for several DYNA Instruments base boards.

It can be used for application build by mounting the project directory into a container, then using the normal build commands.

# Build kernel, dtb and rootfs

Start tftp container:

`docker run -p 0.0.0.0:69:69/udp -v srv-tftp:/var/tftpboot -d pghalliday/tftp`

Start kernel/rootfs build container:

```
docker run --rm -v imx6ull-colibri-kernel-build:/usr/armv7a-unknown-linux-gnueabihf/usr/src/build-armv7a-unknown-linux-gnueabihf-imx6ull-colibri \
                 -v imx6ull-colibri-rootfs-target:/usr/armv7a-unknown-linux-gnueabihf/mnt/reduced-rootfs \
                 -v imx6ull-colibri-rootfs:/usr/armv7a-unknown-linux-gnueabihf/mnt/gentoo \
                 -v imx6ull-colibri-target-images:/usr/armv7a-unknown-linux-gnueabihf/mnt/images \
                 -v srv-tftp:/tftp \
                 --privileged -it dynainstrumentsoss/dyna-linux-imx6ull-colibri-final:2019.11
```

