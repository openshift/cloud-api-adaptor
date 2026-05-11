package agent_policy

default AddARPNeighborsRequest := true
default AddSwapRequest := true
default CloseStdinRequest := true
default CopyFileRequest := true
default CreateSandboxRequest := true
default DestroySandboxRequest := true
default GetMetricsRequest := true
default GetOOMEventRequest := true
default GuestDetailsRequest := true
default ListInterfacesRequest := true
default ListRoutesRequest := true
default MemHotplugByProbeRequest := true
default OnlineCPUMemRequest := true
default PauseContainerRequest := true
default PullImageRequest := true
default RemoveContainerRequest := true
default RemoveStaleVirtiofsShareMountsRequest := true
default ReseedRandomDevRequest := true
default ResumeContainerRequest := true
default SetGuestDateTimeRequest := true
default SignalProcessRequest := true
default StartContainerRequest := true
default StartTracingRequest := true
default StatsContainerRequest := true
default StopTracingRequest := true
default TtyWinResizeRequest := true
default UpdateContainerRequest := true
default UpdateEphemeralMountsRequest := true
default UpdateInterfaceRequest := true
default UpdateRoutesRequest := true
default WaitProcessRequest := true
default WriteStreamRequest := true
default CreateContainerRequest := true

default SetPolicyRequest := false
default ExecProcessRequest := false
default ReadStreamRequest := false

#
# CopyFile filtering to ensure the host can only
# write to the guest shared directory. Symlink
# targets are checked as well.
#
CopyFileRequest if {
    print("CopyFileRequest: input =", input)

    allow_copy_file

    print("CopyFileRequest: true")
}

allow_copy_file if {
    print("allow_copy_file regular")

    input.file_type == "Regular"
    allow_copy_file_path(input.path, "")

    print("allow_copy_file regular: true")
}

allow_copy_file if {
    print("allow_copy_file directory")

    input.file_type == "Directory"
    allow_copy_file_path(input.path, "")

    print("allow_copy_file directory: true")
}

allow_copy_file if {
    print("allow_copy_file symlink")

    input.file_type == "Symlink"
    # Symlinks are not allowed on the top-level of the shared directory, from which we mount.
    allow_copy_file_path(input.path, ".*/.+")
    # Symlinks must be normalized.
    check_directory_traversal(input.symlink_target)
    # Symlinks must be relative.
    not startswith(input.symlink_target, "/")

    print("allow_copy_file symlink: true")
}

allow_copy_file_path(path, regex_suffix) if {
    check_directory_traversal(path)

    some regex1 in policy_data.request_defaults.CopyFileRequest
    regex2 := replace(regex1, "$(sfprefix)", policy_data.common.sfprefix)
    regex3 := replace(regex2, "$(cpath)", policy_data.common.cpath)
    regex4 := replace(regex3, "$(bundle-id)", "[a-z0-9]{64}")
    regex5 := concat("", [regex4, regex_suffix])
    print("allow_copy_file_path: regex5 =", regex5)
    regex.match(regex5, path)
}

check_directory_traversal(i_path) if {
    not regex.match("(^|/)\\.\\.($|/)", i_path)
}

policy_data := {
  "common": {
    "cpath": "/run/kata-containers/shared/containers(?:/passthrough)?",
    "sfprefix": "^$(cpath)/(watchable/)?$(bundle-id)-[a-z0-9]{16}-"
  },
  "request_defaults": {
    "CopyFileRequest": [
      "$(sfprefix)"
    ]
  }
}
