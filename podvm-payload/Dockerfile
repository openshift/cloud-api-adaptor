## GOLANG ##
FROM brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_9_golang_1.23 as go_builder
ARG ARCH
ENV ARCH=${ARCH}

RUN mkdir -p /artifacts/usr/local/bin

COPY src/cloud-api-adaptor /workdir

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
FROM registry.access.redhat.com/ubi9/ubi:latest as rust_builder
USER root
# This is registering RHEL when building on an unsubscribed system
# If you are running a UBI container on a registered and subscribed RHEL host, 
# the main RHEL Server repository is enabled inside the standard UBI container.
# Uncomment this and provide the associated ARG variables to register.
RUN if command -v subscription-manager; then \
      REPO_ARCH=$(uname -m) && \
      subscription-manager register --org "$(cat /activation-key/org)" --activationkey "$(cat /activation-key/activationkey)" && \
      subscription-manager repos --enable rhel-9-for-${REPO_ARCH}-appstream-rpms --enable codeready-builder-for-rhel-9-${REPO_ARCH}-rpms; \
    else \
      dnf -y install 'dnf-command(config-manager)' && dnf config-manager --enable crb; \
    fi
RUN dnf clean packages && dnf install -y git rust cargo perl-File-Compare perl-FindBin cmake gcc-c++ perl protobuf-compiler clang-devel device-mapper-devel tpm2-tss-devel

RUN mkdir -p /artifacts/usr/local/bin

COPY podvm-payload/kata-containers /workdir/kata-containers
COPY podvm-payload/guest-components /workdir/guest-components

# binary: kata-agent (rust)
WORKDIR /workdir/kata-containers/src/agent
RUN make src/version.rs
RUN cargo build --verbose --release --features "guest-pull agent-policy"
RUN cp /workdir/kata-containers/src/agent/target/release/kata-agent /artifacts/usr/local/bin

# binary: attestation-agent (rust)
WORKDIR /workdir/guest-components/attestation-agent/attestation-agent
RUN ARCH=$(uname -m) && \
  if [ "$ARCH" = "s390x" ]; then \
        cargo build --verbose --release --no-default-features --features "coco_as,kbs,se-attester,bin,ttrpc,openssl"; \
  else \
        cargo build --verbose --release --no-default-features --features "coco_as,kbs,az-snp-vtpm-attester,az-tdx-vtpm-attester,bin,ttrpc,openssl"; \
  fi
RUN cp /workdir/guest-components/target/release/ttrpc-aa /artifacts/usr/local/bin/attestation-agent

# binary: api-server-rest (rust)
WORKDIR /workdir/guest-components/api-server-rest
RUN cargo build --verbose --release
RUN cp /workdir/guest-components/target/release/api-server-rest /artifacts/usr/local/bin

# binary: confidential-data-hub (rust)
WORKDIR /workdir/guest-components/confidential-data-hub/hub
RUN cargo build --verbose --release --no-default-features --features "kbs,bin,ttrpc"
RUN cp /workdir/guest-components/target/release/ttrpc-cdh /artifacts/usr/local/bin/confidential-data-hub


## FINAL IMAGE ##
FROM registry.access.redhat.com/ubi9/ubi:latest

COPY --from=go_builder /artifacts /artifacts
COPY --from=rust_builder /artifacts /artifacts

RUN dnf update -y && dnf install -y tar gzip && dnf clean all

# Create the final tarball and remove /artifacts to save space
RUN tar czvf /podvm-binaries.tar.gz -C /artifacts usr/ etc/ && \
    rm -rf /artifacts

# Red Hat labels
LABEL name="openshift-sandboxed-containers-podvm-payload" \
version="1.9.0" \
com.redhat.component="osc-podvm-payload-container" \
summary="Container image containing podvm artefacts that is required for creating Pod VM images" \
maintainer="redhat@redhat.com" \
description="Container image containing podvm artefacts that is required for creating Pod VM images" \
io.k8s.display-name="openshift-sandboxed-containers-podvm-payload" \
io.k8s.description="Container image containing podvm artefacts that is required for creating Pod VM images" \
io.openshift.tags=""
