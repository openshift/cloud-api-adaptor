#!/bin/bash

CLOUD_PROVIDER=${1:-$CLOUD_PROVIDER}
# Enabling dynamically loaded cloud provider external plugin feature, disabled by default
ENABLE_CLOUD_PROVIDER_EXTERNAL_PLUGIN=${ENABLE_CLOUD_PROVIDER_EXTERNAL_PLUGIN:-false}

CRI_RUNTIME_ENDPOINT=${CRI_RUNTIME_ENDPOINT:-/run/cri-runtime.sock}
optionals+=""

# Ensure you add a space before the closing quote (") when updating the optionals
# example:
# following is the correct method: optionals+="-option val "
# following is the incorrect method: optionals+="-option val"

[[ "${PAUSE_IMAGE}" ]] && optionals+="-pause-image ${PAUSE_IMAGE} "
[[ "${TUNNEL_TYPE}" ]] && optionals+="-tunnel-type ${TUNNEL_TYPE} "
[[ "${VXLAN_PORT}" ]] && optionals+="-vxlan-port ${VXLAN_PORT} "
[[ "${CACERT_FILE}" ]] && optionals+="-ca-cert-file ${CACERT_FILE} "
[[ "${CERT_FILE}" ]] && [[ "${CERT_KEY}" ]] && optionals+="-cert-file ${CERT_FILE} -cert-key ${CERT_KEY} "
[[ "${TLS_SKIP_VERIFY}" ]] && optionals+="-tls-skip-verify "
[[ "${PROXY_TIMEOUT}" ]] && optionals+="-proxy-timeout ${PROXY_TIMEOUT} "
[[ "${INITDATA}" ]] && optionals+="-initdata ${INITDATA} "
[[ "${FORWARDER_PORT}" ]] && optionals+="-forwarder-port ${FORWARDER_PORT} "
[[ "${CLOUD_CONFIG_VERIFY}" == "true" ]] && optionals+="-cloud-config-verify "
[[ "${SECURE_COMMS}" == "true" ]] && optionals+="-secure-comms "
[[ "${SECURE_COMMS_NO_TRUSTEE}" == "true" ]] && optionals+="-secure-comms-no-trustee "
[[ "${SECURE_COMMS_INBOUNDS}" ]] && optionals+="-secure-comms-inbounds ${SECURE_COMMS_INBOUNDS} "
[[ "${SECURE_COMMS_OUTBOUNDS}" ]] && optionals+="-secure-comms-outbounds ${SECURE_COMMS_OUTBOUNDS} "
[[ "${SECURE_COMMS_PP_INBOUNDS}" ]] && optionals+="-secure-comms-pp-inbounds ${SECURE_COMMS_PP_INBOUNDS} "
[[ "${SECURE_COMMS_PP_OUTBOUNDS}" ]] && optionals+="-secure-comms-pp-outbounds ${SECURE_COMMS_PP_OUTBOUNDS} "
[[ "${SECURE_COMMS_KBS_ADDR}" ]] && optionals+="-secure-comms-kbs ${SECURE_COMMS_KBS_ADDR} "
[[ "${PEERPODS_LIMIT_PER_NODE}" ]] && optionals+="-peerpods-limit-per-node ${PEERPODS_LIMIT_PER_NODE} "

test_vars() {
    for i in "$@"; do
        [ -z "${!i}" ] && echo "\$$i is NOT set" && EXT=1
    done
    [[ -n $EXT ]] && exit 1
}

one_of() {
    for i in "$@"; do
        [ -n "${!i}" ] && echo "\$$i is SET" && EXIST=1
    done
    [[ -z $EXIST ]] && echo "At least one of these must be SET: $*" && exit 1
}

aws() {
    test_vars AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

    [[ "${PODVM_LAUNCHTEMPLATE_NAME}" ]] && optionals+="-use-lt -aws-lt-name ${PODVM_LAUNCHTEMPLATE_NAME} " # has precedence if set
    [[ "${AWS_SG_IDS}" ]] && optionals+="-securitygroupids ${AWS_SG_IDS} "                                  # MUST if template is not used
    [[ "${PODVM_AMI_ID}" ]] && optionals+="-imageid ${PODVM_AMI_ID} "                                       # MUST if template is not used
    [[ "${PODVM_INSTANCE_TYPE}" ]] && optionals+="-instance-type ${PODVM_INSTANCE_TYPE} "                   # default m6a.large
    [[ "${PODVM_INSTANCE_TYPES}" ]] && optionals+="-instance-types ${PODVM_INSTANCE_TYPES} "
    [[ "${SSH_KP_NAME}" ]] && optionals+="-keyname ${SSH_KP_NAME} "                    # if not retrieved from IMDS
    [[ "${AWS_SUBNET_ID}" ]] && optionals+="-subnetid ${AWS_SUBNET_ID} "               # if not set retrieved from IMDS
    [[ "${AWS_REGION}" ]] && optionals+="-aws-region ${AWS_REGION} "                   # if not set retrieved from IMDS
    [[ "${TAGS}" ]] && optionals+="-tags ${TAGS} "                                     # Custom tags applied to pod vm
    [[ "${USE_PUBLIC_IP}" == "true" ]] && optionals+="-use-public-ip "                 # Use public IP for pod vm
    [[ "${ROOT_VOLUME_SIZE}" ]] && optionals+="-root-volume-size ${ROOT_VOLUME_SIZE} " # Specify root volume size for pod vm
    [[ "${DISABLECVM}" == "true" ]] && optionals+="-disable-cvm "

    set -x
    exec cloud-api-adaptor aws \
        -pods-dir /run/peerpod/pods \
        ${optionals} \
        -socket /run/peerpod/hypervisor.sock
}

azure() {
    test_vars AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID AZURE_RESOURCE_GROUP AZURE_SUBNET_ID AZURE_IMAGE_ID

    [[ "${SSH_USERNAME}" ]] && optionals+="-ssh-username ${SSH_USERNAME} "
    [[ "${DISABLECVM}" == "true" ]] && optionals+="-disable-cvm "
    [[ "${AZURE_INSTANCE_SIZES}" ]] && optionals+="-instance-sizes ${AZURE_INSTANCE_SIZES} "
    [[ "${TAGS}" ]] && optionals+="-tags ${TAGS} " # Custom tags applied to pod vm
    [[ "${ENABLE_SECURE_BOOT}" == "true" ]] && optionals+="-enable-secure-boot "
    [[ "${USE_PUBLIC_IP}" == "true" ]] && optionals+="-use-public-ip "

    set -x
    exec cloud-api-adaptor azure \
        -subscriptionid "${AZURE_SUBSCRIPTION_ID}" \
        -region "${AZURE_REGION}" \
        -instance-size "${AZURE_INSTANCE_SIZE}" \
        -resourcegroup "${AZURE_RESOURCE_GROUP}" \
        -vxlan-port 8472 \
        -subnetid "${AZURE_SUBNET_ID}" \
        -securitygroupid "${AZURE_NSG_ID}" \
        -imageid "${AZURE_IMAGE_ID}" \
        ${optionals}
}

gcp() {
    test_vars GCP_CREDENTIALS GCP_PROJECT_ID GCP_ZONE PODVM_IMAGE_NAME

    [[ "${PODVM_IMAGE_NAME}" ]] && optionals+="-image-name ${PODVM_IMAGE_NAME} "
    [[ "${GCP_PROJECT_ID}" ]] && optionals+="-gcp-project-id ${GCP_PROJECT_ID} "
    [[ "${GCP_ZONE}" ]] && optionals+="-zone ${GCP_ZONE} "                                         # if not set retrieved from IMDS
    [[ "${GCP_MACHINE_TYPE}" ]] && optionals+="-machine-type ${GCP_MACHINE_TYPE} "                 # default e2-medium
    [[ "${GCP_NETWORK}" ]] && optionals+="-network ${GCP_NETWORK} "                                # defaults to 'default'
    [[ "${GCP_DISK_TYPE}" ]] && optionals+="-disk-type ${GCP_DISK_TYPE} "                          # defaults to 'pd-standard'
    [[ "${ROOT_VOLUME_SIZE}" ]] && optionals+="-root-volume-size ${ROOT_VOLUME_SIZE} "             # Specify root volume size for pod vm

    set -x

    # Avoid using node's metadata service credentials for GCP authentication
    echo "$GCP_CREDENTIALS" > /tmp/gcp-creds.json
    export GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp-creds.json

    exec cloud-api-adaptor gcp \
        -pods-dir /run/peerpod/pods \
        ${optionals}
}

ibmcloud() {
    one_of IBMCLOUD_API_KEY IBMCLOUD_IAM_PROFILE_ID

    set -x
    exec cloud-api-adaptor ibmcloud \
        -iam-service-url "${IBMCLOUD_IAM_ENDPOINT}" \
        -vpc-service-url "${IBMCLOUD_VPC_ENDPOINT}" \
        -resource-group-id "${IBMCLOUD_RESOURCE_GROUP_ID}" \
        -key-id "${IBMCLOUD_SSH_KEY_ID}" \
        -image-id "${IBMCLOUD_PODVM_IMAGE_ID}" \
        -profile-name "${IBMCLOUD_PODVM_INSTANCE_PROFILE_NAME}" \
        -profile-list "${IBMCLOUD_PODVM_INSTANCE_PROFILE_LIST}" \
        -zone-name "${IBMCLOUD_ZONE}" \
        -primary-subnet-id "${IBMCLOUD_VPC_SUBNET_ID}" \
        -primary-security-group-id "${IBMCLOUD_VPC_SG_ID}" \
        -vpc-id "${IBMCLOUD_VPC_ID}" \
        -pods-dir /run/peerpod/pods \
        ${optionals} \
        -socket /run/peerpod/hypervisor.sock
}

ibmcloud_powervs() {
    test_vars IBMCLOUD_API_KEY

    [[ "${POWERVS_MEMORY}" ]] && optionals+="-memory ${POWERVS_MEMORY} "
    [[ "${POWERVS_PROCESSORS}" ]] && optionals+="-cpu ${POWERVS_PROCESSORS} "
    [[ "${POWERVS_PROCESSOR_TYPE}" ]] && optionals+="-proc-type ${POWERVS_PROCESSOR_TYPE} "
    [[ "${POWERVS_SYSTEM_TYPE}" ]] && optionals+="-sys-type ${POWERVS_SYSTEM_TYPE} "
    [[ "${USE_PUBLIC_IP}" == "true" ]] && optionals+="-use-public-ip " # Use public IP for pod vm

    set -x
    exec cloud-api-adaptor ibmcloud-powervs \
        -service-instance-id ${POWERVS_SERVICE_INSTANCE_ID} \
        -zone ${POWERVS_ZONE} \
        -image-id ${POWERVS_IMAGE_ID} \
        -network-id ${POWERVS_NETWORK_ID} \
        -ssh-key ${POWERVS_SSH_KEY_NAME} \
        -pods-dir /run/peerpod/pods \
        ${optionals} \
        -socket /run/peerpod/hypervisor.sock
}

libvirt() {
    test_vars LIBVIRT_URI

    [[ "${DISABLECVM}" = "true" ]] && optionals+="-disable-cvm "
    set -x
    exec cloud-api-adaptor libvirt \
        -uri "${LIBVIRT_URI}" \
        -data-dir /opt/data-dir \
        -pods-dir /run/peerpod/pods \
        -network-name "${LIBVIRT_NET:-default}" \
        -pool-name "${LIBVIRT_POOL:-default}" \
        ${optionals} \
        -socket /run/peerpod/hypervisor.sock
}

vsphere() {
    test_vars GOVC_USERNAME GOVC_PASSWORD GOVC_URL GOVC_DATACENTER

    [[ "${GOVC_TEMPLATE}" ]] && optionals+="-template ${GOVC_TEMPLATE} "
    [[ "${GOVC_VCLUSTER}" ]] && optionals+="-cluster ${GOVC_VCLUSTER} "
    [[ "${GOVC_FOLDER}" ]] && optionals+="-deploy-folder ${GOVC_FOLDER} "
    [[ "${GOVC_HOST}" ]] && optionals+="-host ${GOVC_HOST} "
    [[ "${GOVC_DRS}" ]] && optionals+="-drs ${GOVC_DRS} "
    [[ "${GOVC_DATASTORE}" ]] && optionals+="-data-store ${GOVC_DATASTORE} "

    set -x
    exec cloud-api-adaptor vsphere \
        -vcenter-url ${GOVC_URL} \
        -data-center ${GOVC_DATACENTER} \
        ${optionals} \
        -socket /run/peerpod/hypervisor.sock
}

docker() {
    [[ "${DOCKER_HOST}" ]] && optionals+="-docker-host ${DOCKER_HOST} "
    [[ "${DOCKER_TLS_VERIFY}" ]] && optionals+="-docker-tls-verify ${DOCKER_TLS_VERIFY} "
    [[ "${DOCKER_CERT_PATH}" ]] && optionals+="-docker-cert-path ${DOCKER_CERT_PATH} "
    [[ "${DOCKER_API_VERSION}" ]] && optionals+="-docker-api-version ${DOCKER_API_VERSION} "
    [[ "${DOCKER_PODVM_IMAGE}" ]] && optionals+="-podvm-docker-image ${DOCKER_PODVM_IMAGE} "
    [[ "${DOCKER_NETWORK_NAME}" ]] && optionals+="-docker-network-name ${DOCKER_NETWORK_NAME} "

    set -x
    exec cloud-api-adaptor docker \
        -pods-dir /run/peerpod/pods \
        ${optionals} \
        -socket /run/peerpod/hypervisor.sock

}

help_msg() {
    cat <<EOF
Usage:
	CLOUD_PROVIDER=aws|azure|gcp|ibmcloud|ibmcloud-powervs|libvirt|vsphere|docker $0
or
	$0 aws|azure|gcp|ibmcloud|ibmcloud-powervs|libvirt|vsphere|docker

in addition all cloud provider specific env variables must be set and valid
(CLOUD_PROVIDER is currently set to "$CLOUD_PROVIDER")
EOF
}

if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
    aws
elif [[ "$CLOUD_PROVIDER" == "azure" ]]; then
    azure
elif [[ "$CLOUD_PROVIDER" == "gcp" ]]; then
    gcp
elif [[ "$CLOUD_PROVIDER" == "ibmcloud" ]]; then
    ibmcloud
elif [[ "$CLOUD_PROVIDER" == "ibmcloud-powervs" ]]; then
    ibmcloud_powervs
elif [[ "$CLOUD_PROVIDER" == "libvirt" ]]; then
    libvirt
elif [[ "$CLOUD_PROVIDER" == "vsphere" ]]; then
    vsphere
elif [[ "$CLOUD_PROVIDER" == "docker" ]]; then
    docker
else
    help_msg
fi
