# Build the manager binary
FROM brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_9_golang_1.24 AS builder

WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Copy the go source
COPY main.go main.go
#COPY api/ api/
#COPY controllers/ controllers/
COPY pkg/ pkg/

# Build
ARG TARGETARCH
ENV GOFLAGS="-tags=strictfipsruntime"

RUN CGO_ENABLED=1 GOOS=linux GOARCH=$TARGETARCH go build -mod=readonly -a -o manager main.go

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7-1763362218
WORKDIR /
COPY --from=builder /workspace/manager .
USER 65532:65532

# Red Hat labels
LABEL name="openshift-sandboxed-containers/osc-cloud-api-adaptor-webhook-rhel9" \
cpe="cpe:/a:redhat:confidential_compute_attestation:1.11::el9" \
version="1.11" \
com.redhat.component="osc-cloud-api-adaptor-webhook-container" \
summary="This mutating webhook modifies a POD spec using specific runtimeclass to remove all resources entries and replace it with peer-pod extended resource." \
maintainer="redhat@redhat.com" \
description="This mutating webhook modifies a POD spec using specific runtimeclass to remove all resources entries and replace it with peer-pod extended resource." \
io.k8s.display-name="openshift-sandboxed-containers-cloud-api-adaptor-webhook" \
io.k8s.description="This mutating webhook modifies a POD spec using specific runtimeclass to remove all resources entries and replace it with peer-pod extended resource." \
io.openshift.tags=""

ENTRYPOINT ["/manager"]
