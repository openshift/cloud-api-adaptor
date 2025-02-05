## GOLANG ##
FROM registry.access.redhat.com/ubi9/go-toolset:1.22.9-1737480393 as go_builder
USER root
ARG ARCH
ENV ARCH=${ARCH}

RUN mkdir -p /artifacts/usr/local/bin

COPY src/cloud-api-adaptor /workdir

# binary: agent-protocol-forwarder, proccess-user-data (golang)
WORKDIR /workdir
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
ARG ACTIVATION_KEY
ARG ORG_ID
RUN if [[ -n "${ACTIVATION_KEY}" && -n "${ORG_ID}" ]]; then \
        REPO_ARCH=$(uname -m) && \
        subscription-manager register --org=${ORG_ID} --activationkey=${ACTIVATION_KEY} && \
        subscription-manager repos --enable rhel-9-for-${REPO_ARCH}-appstream-rpms --enable codeready-builder-for-rhel-9-${REPO_ARCH}-rpms; \
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

## RUST 1.80 ##

# This part is needed only for confidential data hub
# Building the other components with rust 1.80 causes issues, and building CDH
# with anything before 1.80 fails
# This part of the build uses centos stream 9, which has a newer version of rust
FROM quay.io/centos/centos:stream9 as rust_builder_1_80
USER root
RUN dnf clean packages && dnf --enablerepo=crb install -y git rust cargo perl-File-Compare perl-FindBin cmake gcc-c++ perl protobuf-compiler clang-devel device-mapper-devel tpm2-tss-devel

RUN mkdir -p /artifacts/usr/local/bin

COPY podvm-payload/guest-components /workdir/guest-components

# binary: confidential-data-hub (rust) using the 1.80 rust version
WORKDIR /workdir/guest-components/confidential-data-hub/hub
RUN cargo build --verbose --release --no-default-features --features "kbs,bin,ttrpc"
RUN cp /workdir/guest-components/target/release/ttrpc-cdh /artifacts/usr/local/bin/confidential-data-hub





## FINAL IMAGE ##
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

COPY --from=go_builder /artifacts /artifacts
COPY --from=rust_builder /artifacts /artifacts
COPY --from=rust_builder_1_80 /artifacts /artifacts

RUN microdnf install -y tar gzip && microdnf clean all

# Create the final tarball and remove /artifacts to save space
RUN tar czvf /podvm-binaries.tar.gz -C /artifacts usr/ etc/ && \
    rm -rf /artifacts
