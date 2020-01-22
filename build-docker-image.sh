#!/bin/bash

docker_dir=$(dirname $(readlink -f $0))

: "${MERGE_JOBS:="--jobs=16"}"
: "${REPO:=dynainstrumentsoss}"
: "${IMAGE:=$(basename $docker_dir | tr "A-Z" "a-z")}"
: "${TAG:=2019.11}"
STAGE6_TAG=${REPO}/${IMAGE}-stage6:${TAG}
STAGE7_TAG=${REPO}/${IMAGE}-stage7:${TAG}
STAGE8_TAG=${REPO}/${IMAGE}-stage8:${TAG}
DATETIME=$(date '+%Y%m%d%H%M%S')

test -r $docker_dir/bsp-stage6.Dockerfile || { echo "missing bsp-stage6.Dockerfile beside $0"; exit -1; }
test -r $docker_dir/bsp-stage8.Dockerfile || { echo "missing bsp-stage8.Dockerfile beside $0"; exit -1; }

test -r $docker_dir/.dockerignore || {
cat >$docker_dir/.dockerignore <<EOM
$(basename $(readlink -f $0))
log/*
EOM

}

mkdir -p ${docker_dir}/log
echo "Build image, write log to : ${docker_dir}/log/docker-build-stage1.${DATETIME}.log"
docker build -f bsp-stage6.Dockerfile --build-arg "BSPINPUT_TAG=dynainstrumentsoss/crossdev-armv7a-unknown-linux-gnueabihf-stage5:${TAG}" --build-arg "MERGE_JOBS=${MERGE_JOBS}" --build-arg http_proxy=$http_proxy --build-arg https_proxy=${https_proxy:-$http_proxy} --tag ${STAGE6_TAG}  $docker_dir 2>&1 | tee ${docker_dir}/log/docker-build-stage6.${DATETIME}.log  || exit $?

# build stage7 in privileged container, mimic caching
mkdir -p  ${docker_dir}/build-cache

# cleaup build cmd cache by removing all cache tags with missing image
IMAGES_LIST=$(docker images -aq --no-trunc)
for h in ${docker_dir}/build-cache/*; do
  echo $h | egrep -q '\.txt$' && continue
  test -e $h && { echo "${IMAGES_LIST}" | grep -q $(cat $h) || { rm -f $h; rm -f $h.txt; } ; }
done

# run sequence of privileged build commands
INTERMEDIATE_IMAGE=$(docker image ls -q --no-trunc ${STAGE6_TAG})
for BUILD_CMD in "target-chroot emerge --depclean sys-devel/binutils sys-devel/gcc sys-libs/glibc" \
                 "target-chroot chmod ug-s /usr/sbin/ssmtp\; emerge --keep-going $MERGE_JOBS @preserved-rebuild\; echo YES \| etc-update --automode -9" \
                 "target-chroot emerge --noreplace --keep-going $MERGE_JOBS @embedded-minimal-root @embedded-fs-utils @embedded-libs-tools\; echo YES \| etc-update --automode -9" \
                 "target-chroot ACCEPT_KEYWORDS='**' emerge -v '=sys-apps/9mount-1.3'" \
                 "target-chroot quickpkg-all-parallel" \
                 "target-chroot emerge --root=/mnt/gentoo -1K sys-apps/busybox \; mkdir -p /mnt/gentoo/usr/bin \; cp /usr/bin/qemu-arm /mnt/gentoo/usr/bin \; chroot /mnt/gentoo busybox --install -s" \
                 "target-chroot emerge --root=/mnt/gentoo --noreplace -K @embedded-minimal-root @embedded-libs-tools" \
                 "target-chroot ACCEPT_KEYWORDS='**' emerge --root=/mnt/gentoo --noreplace -K '=sys-apps/9mount-1.3'" \
                 ; do 
  BUILD_HASH=$(echo -n ${INTERMEDIATE_IMAGE}:${BUILD_CMD} | md5sum - | cut -c -32)
  echo "${INTERMEDIATE_IMAGE}:${BUILD_CMD}" >${docker_dir}/build-cache/${BUILD_HASH}.txt
  if [ -e ${docker_dir}/build-cache/${BUILD_HASH} ]; then
    echo "image '"${INTERMEDIATE_IMAGE}"' takes '"${BUILD_CMD}"' from cache" 2>&1 | tee -a ${docker_dir}/log/docker-build-stage7.${DATETIME}.log
    INTERMEDIATE_IMAGE=$(cat ${docker_dir}/build-cache/${BUILD_HASH})
  else
    echo "image '"${INTERMEDIATE_IMAGE}"' runs '"${BUILD_CMD}"'" 2>&1 | tee -a ${docker_dir}/log/docker-build-stage7.${DATETIME}.log
    INTERMEDIATE_CONTAINER=$(docker run --detach --privileged -e http_proxy=${http_proxy} -e https_proxy=${https_proxy:-$http_proxy} ${INTERMEDIATE_IMAGE} /bin/bash -l -c "${BUILD_CMD}") || exit $?
    docker logs --follow $INTERMEDIATE_CONTAINER 2>&1 | tee -a ${docker_dir}/log/docker-build-stage7.${DATETIME}.log || { docker stop $INTERMEDIATE_CONTAINER; exit $(docker wait $INTERMEDIATE_CONTAINER); }
    INTERMEDIATE_RESULT=$(docker wait $INTERMEDIATE_CONTAINER)
    test ${INTERMEDIATE_RESULT:--256} -eq 0 || exit $INTERMEDIATE_RESULT
    INTERMEDIATE_IMAGE=$(docker commit --change 'LABEL maintainer="linuxer (at) quantentunnel.de"' --message "RUNP ${BUILD_CMD}" $INTERMEDIATE_CONTAINER) || exit $?
    docker rm ${INTERMEDIATE_CONTAINER} || exit $?
    echo ${INTERMEDIATE_IMAGE} >${docker_dir}/build-cache/${BUILD_HASH}
  fi
done

docker tag ${INTERMEDIATE_IMAGE} ${STAGE7_TAG} || exit $?

# build bsp stage8
docker build -f bsp-stage8.Dockerfile --build-arg BSPINPUT_TAG=${STAGE7_TAG} --build-arg "MERGE_JOBS=${MERGE_JOBS}" --build-arg http_proxy=$http_proxy --build-arg https_proxy=${https_proxy:-$http_proxy} --tag ${STAGE8_TAG} $docker_dir 2>&1 | tee ${docker_dir}/log/docker-build-stage8.${DATETIME}.log

# final tag
docker tag ${STAGE8_TAG} ${REPO}/${IMAGE}-final:${TAG}
