ARG BSPINPUT_TAG
FROM ${BSPINPUT_TAG}
LABEL maintainer="Johannes Lode (at) dynainstruments.com"
ARG MERGE_JOBS

# put some use flags and accept keywords in
COPY bsp-config-files/ /usr/${TARGET}/

# triggerhappy, screen and nfs-utils will fail
RUN mv /var/lib/layman /var/db/repos/layman && \
    ln -sfT /usr/${TARGET}/etc/layman/layman.cfg /etc/layman/layman.cfg && \
    ln -sfT /usr/${TARGET}/etc/portage/repos.conf/layman.conf /etc/portage/repos.conf/layman.conf && \
    layman -f && \
    layman -a salfter kaa booboo && \
    ${TARGET}-emerge --root=/usr/${TARGET} --fetchonly -uDN --noreplace @embedded-minimal-root @embedded-fs-utils @embedded-libs-tools; \
    ${TARGET}-emerge ${MERGE_JOBS} --root=/usr/${TARGET} -uDN --noreplace --keep-going @embedded-minimal-root @embedded-fs-utils @embedded-libs-tools; \
    echo YES | etc-update --automode -9 && \
    true

CMD /bin/bash -il
