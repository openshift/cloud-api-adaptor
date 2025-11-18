# NOTE for hermetic build: any change to the RPM packages installed during build
# must be reflected in the rpms.in.yaml file.
# Also make sure to re-generate the rpms.lock.yaml file when doing so.
# See https://konflux.pages.redhat.com/docs/users/building/prefetching-dependencies.html#rpm
#
# WARNING - jrope@redhat.com - 2025/05/06:
# This Dockerfile makes multiple builds using different images.
# I don't see in the RPM lockfile mechanism whether it can handle different images.
# At this point I'm not sure what would happen if we use builder images that
# are not using the same versions of RPMs.
# Let's keep it safe and ensure we keep the same base image/repos for all builders.


## GOLANG ##
FROM registry.access.redhat.com/ubi10:10.1-1763341459 as go_builder
ARG ARCH
ENV ARCH=${ARCH}

RUN mkdir -p /artifacts/usr/local/bin

COPY src/cloud-api-adaptor /workdir

RUN dnf clean packages && dnf install -y golang

# binary: agent-protocol-forwarder, proccess-user-data (golang)
WORKDIR /workdir
# openshift-golang-builder: GOFLAGS is set to "-mod=vendor" by default in our builder image.
# We need to disable that to keep the build running.
# Taking this opportunity to set our downstream build options
ENV GOFLAGS="-tags=strictfipsruntime,aws,azure,ibmcloud,vsphere,libvirt,gcp"
RUN CGO_ENABLED=1 GOOS=linux go build \
-ldflags=-X=github.com/openshift/cloud-api-adaptor/cmd.VERSION=${CI_CLOUD_API_ADAPTOR_UPSTREAM_VERSION} \
-ldflags=-X=github.com/openshift/cloud-api-adaptor/cmd.COMMIT=${CI_CLOUD_API_ADAPTOR_UPSTREAM_COMMIT} \
-o /artifacts/usr/local/bin/agent-protocol-forwarder cmd/agent-protocol-forwarder/main.go

RUN CGO_ENABLED=1 GOOS=linux go build \
-ldflags=-X=github.com/openshift/cloud-api-adaptor/cmd.VERSION=${CI_CLOUD_API_ADAPTOR_UPSTREAM_VERSION} \
-ldflags=-X=github.com/openshift/cloud-api-adaptor/cmd.COMMIT=${CI_CLOUD_API_ADAPTOR_UPSTREAM_COMMIT} \
-o /artifacts/usr/local/bin/process-user-data cmd/process-user-data/*.go

# config files and scripts
RUN cp -r podvm/files/* /artifacts

## RUST ##
FROM registry.access.redhat.com/ubi10:10.1-1763341459 as rust_builder
USER root
# This is registering RHEL when building on an unsubscribed system
# If you are running a UBI container on a registered and subscribed RHEL host, 
# the main RHEL Server repository is enabled inside the standard UBI container.
# Uncomment this and provide the associated ARG variables to register.
#RUN if command -v subscription-manager; then \
#      REPO_ARCH=$(uname -m) && \
#      subscription-manager register --org "$(cat /activation-key/org)" --activationkey "$(cat /activation-key/activationkey)" && \
#      subscription-manager repos --enable rhel-9-for-${REPO_ARCH}-appstream-rpms --enable codeready-builder-for-rhel-9-${REPO_ARCH}-rpms; \
#    else \
#      dnf -y install 'dnf-command(config-manager)' && dnf config-manager --enable crb; \
#    fi
RUN dnf clean packages && dnf install -y git rust cargo perl-File-Compare perl-FindBin cmake gcc-c++ perl protobuf-compiler clang-devel device-mapper-devel tpm2-tss-devel

RUN mkdir -p /artifacts/usr/local/bin

COPY podvm-payload/kata-containers /workdir/kata-containers
COPY podvm-payload/guest-components /workdir/guest-components

# binary: kata-agent (rust)
WORKDIR /workdir/kata-containers/src/agent
RUN make src/version.rs
RUN RUST_MIN_STACK=16777216 cargo build --verbose --release --features "agent-policy"
RUN cp /workdir/kata-containers/src/agent/target/release/kata-agent /artifacts/usr/local/bin

# binary: attestation-agent (rust)
WORKDIR /workdir/guest-components/attestation-agent/attestation-agent
RUN ARCH=$(uname -m) && \
  if [ "$ARCH" = "s390x" ]; then \
        cargo build --verbose --release --no-default-features --features "coco_as,kbs,se-attester,bin,ttrpc,openssl"; \
  else \
        cargo build --verbose --release --no-default-features --features "coco_as,kbs,az-snp-vtpm-attester,az-tdx-vtpm-attester,snp-attester,tdx-attester,bin,ttrpc,openssl"; \
  fi
RUN cp /workdir/guest-components/target/release/ttrpc-aa /artifacts/usr/local/bin/attestation-agent

# binary: api-server-rest (rust)
WORKDIR /workdir/guest-components/api-server-rest
RUN cargo build --verbose --release
RUN cp /workdir/guest-components/target/release/api-server-rest /artifacts/usr/local/bin

# binary: confidential-data-hub (rust)
WORKDIR /workdir/guest-components/confidential-data-hub/hub
RUN ARCH=$(uname -m) && \
    if [[ "$ARCH" == "s390x" ]]; then \
        dnf install clang -y && \
        export CC=clang CXX=clang++; \
    fi && \
    cargo build --verbose --release --no-default-features --features "kbs,bin,ttrpc"
RUN cp /workdir/guest-components/target/release/ttrpc-cdh /artifacts/usr/local/bin/confidential-data-hub

# build k8s pause image
FROM registry.access.redhat.com/ubi10:10.1-1763341459 as pause_builder
RUN dnf install -y gcc glibc-static crun jq
RUN mkdir -p /pause_bundle/rootfs
COPY podvm-payload/pause/pause.c .
RUN gcc -static -o /pause_bundle/rootfs/pause pause.c
RUN crun spec --rootless && \
    jq '.process.args = ["/pause"] | .root.path = "rootfs"' config.json > /pause_bundle/config.json && \
    rm -f config.json
RUN tar czvf /pause-bundle.tar.gz -C / pause_bundle/


## FINAL IMAGE ##
FROM registry.access.redhat.com/ubi10:10.1-1763341459

COPY --from=go_builder /artifacts /artifacts
COPY --from=rust_builder /artifacts /artifacts

RUN dnf update -y && dnf install -y tar gzip && dnf clean all

# Create the symlink for the policy in the artifact folder
# This is a problem introduced by our build system, and only required for our
# downstream builds - in upstream, the symlink pre-exists in the podvm sources folder.
RUN mkdir -p /artifacts/etc/kata-opa/ && ln -s /run/peerpod/policy.rego /artifacts/etc/kata-opa/default-policy.rego

# Make tmpfile to copy osc-policy.rego as the default policy instead of the allow-all one.
COPY podvm-payload/osc-agent-policy.rego /artifacts/etc/kata-opa/
RUN sed -i -E 's|/etc/kata-opa/[a-z0-9_-]+\.rego$|/etc/kata-opa/osc-agent-policy.rego|' /artifacts/etc/tmpfiles.d/policy.conf

# Create the final tarball and remove /artifacts to save space
RUN tar czvf /podvm-binaries.tar.gz -C /artifacts usr/ etc/ && \
    rm -rf /artifacts

# add also the pause tarball
COPY --from=pause_builder /pause-bundle.tar.gz /pause-bundle.tar.gz

# Red Hat labels
LABEL name="openshift-sandboxed-containers/osc-podvm-payload-rhel9" \
cpe="cpe:/a:redhat:confidential_compute_attestation:1.10::el9" \
version="1.11" \
com.redhat.component="osc-podvm-payload-container" \
summary="Container image containing podvm artefacts that is required for creating Pod VM images" \
maintainer="redhat@redhat.com" \
description="Container image containing podvm artefacts that is required for creating Pod VM images" \
io.k8s.display-name="openshift-sandboxed-containers-podvm-payload" \
io.k8s.description="Container image containing podvm artefacts that is required for creating Pod VM images" \
io.openshift.tags=""
