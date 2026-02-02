constants = import_module("../../package_io/constants.star")
shared_utils = import_module("../../shared_utils/shared_utils.star")
reth_launcher_module = import_module("../../el/reth/reth_launcher.star")
el_context_module = import_module("../../el/el_context.star")
input_parser = import_module("../../package_io/input_parser.star")

BUILDOOR_SERVICE_NAME = "buildoor"
BUILDOOR_BUILDER_API_PORT = 9000
BUILDOOR_EL_SERVICE_NAME = "buildoor-el-reth"

HTTP_PORT_ID = "http"

USED_PORTS = {
    HTTP_PORT_ID: shared_utils.new_port_spec(
        BUILDOOR_BUILDER_API_PORT,
        shared_utils.TCP_PROTOCOL,
        shared_utils.HTTP_APPLICATION_PROTOCOL,
    ),
}

# The min/max CPU/memory that buildoor can use
MIN_CPU = 100
MAX_CPU = 2000
MIN_MEMORY = 256
MAX_MEMORY = 2048

# The min/max CPU/memory that buildoor EL client can use
EL_MIN_CPU = 100
EL_MAX_CPU = 2000
EL_MIN_MEMORY = 512
EL_MAX_MEMORY = 4096


def launch_buildoor(
    plan,
    mev_params,
    beacon_uri,
    jwt_file,
    port_publisher,
    index,
    global_node_selectors,
    global_tolerations,
    el_cl_genesis_data,
    existing_el_clients,
    network_params,
    global_log_level,
    persistent,
    bootnodoor_enode=None,
):
    """
    Launch buildoor builder service with dedicated reth EL client.
    
    Args:
        plan: Kurtosis plan
        mev_params: MEV parameters containing mev_relay_image (buildoor image)
        beacon_uri: Consensus layer beacon node HTTP URL
        jwt_file: JWT secret file artifact
        port_publisher: Port publisher for public ports
        index: Service index for port allocation
        global_node_selectors: Node selectors
        global_tolerations: Tolerations
        el_cl_genesis_data: EL/CL genesis data artifact
        existing_el_clients: List of existing EL client contexts for bootnode configuration
        network_params: Network parameters
        global_log_level: Global log level
        persistent: Whether to use persistent storage
        bootnodoor_enode: Optional bootnode enode override
    
    Returns:
        Builder API endpoint URL in format: http://{pubkey}@{ip}:{port}
    """
    tolerations = shared_utils.get_tolerations(global_tolerations=global_tolerations)
    node_selectors = global_node_selectors
    
    # Create a minimal participant structure for the buildoor EL client
    # Use mev_builder_image for the reth EL client image
    reth_image = mev_params.mev_builder_image
    
    buildoor_el_participant = struct(
        el_type=constants.EL_TYPE.reth,
        el_image=reth_image,
        el_log_level="",
        el_storage_type="archive",
        el_extra_params=[],
        el_extra_env_vars={},
        el_extra_mounts=[],
        el_volume_size="0",
        el_min_cpu=0,
        el_max_cpu=0,
        el_min_mem=0,
        el_max_mem=0,
        el_devices=[],
        el_extra_labels={},
        el_force_restart=False,
        supernode=False,
    )
    
    # Launch dedicated reth EL client for buildoor
    plan.print("Launching dedicated reth EL client for buildoor")
    # Create el_cl_genesis_data struct from the UUID
    # el_cl_genesis_data is just the UUID string, we need to wrap it in a struct
    el_cl_genesis_data_struct = struct(
        files_artifact_uuid=el_cl_genesis_data,
        genesis_validators_root="",  # Not needed for reth launcher
    )
    reth_launcher = reth_launcher_module.new_reth_launcher(
        el_cl_genesis_data_struct,
        jwt_file,
        builder_type=False,
        mev_params=None,
    )
    
    buildoor_el_context = reth_launcher_module.launch(
        plan,
        reth_launcher,
        BUILDOOR_EL_SERVICE_NAME,
        buildoor_el_participant,
        global_log_level,
        existing_el_clients,
        persistent,
        tolerations,
        node_selectors,
        port_publisher,
        len(existing_el_clients),  # Use next available index
        network_params,
        {},  # extra_files_artifacts
        bootnodoor_enode,
        None,  # el_binary_artifact
    )
    
    # Build EL engine API URI from the dedicated EL client
    el_engine_api_uri = "http://{0}:{1}".format(
        buildoor_el_context.dns_name,
        buildoor_el_context.engine_rpc_port_num,
    )
    
    public_ports = shared_utils.get_mev_public_port(
        port_publisher,
        constants.HTTP_PORT_ID,
        index,
        0,
    )
    
    # Build command for buildoor
    cmd = [
        "run",
        "--builder-privkey", constants.DEFAULT_MEV_SECRET_KEY,
        "--cl-client", beacon_uri,
        "--el-engine-api", el_engine_api_uri,
        "--el-jwt-secret", constants.JWT_MOUNT_PATH_ON_CONTAINER,
        "--builder-api-enabled",
        "--builder-api-port", str(BUILDOOR_BUILDER_API_PORT),
    ]
    
    buildoor_service = plan.add_service(
        name=BUILDOOR_SERVICE_NAME,
        config=ServiceConfig(
            image=mev_params.mev_relay_image,
            ports=USED_PORTS,
            public_ports=public_ports,
            cmd=cmd,
            files={
                constants.JWT_MOUNTPOINT_ON_CLIENTS: jwt_file,
            },
            min_cpu=MIN_CPU,
            max_cpu=MAX_CPU,
            min_memory=MIN_MEMORY,
            max_memory=MAX_MEMORY,
            node_selectors=node_selectors,
            tolerations=tolerations,
        ),
    )
    
    # Return endpoint URL in the same format as other relays
    return "http://{0}@{1}:{2}".format(
        constants.DEFAULT_MEV_PUBKEY,
        buildoor_service.ip_address,
        BUILDOOR_BUILDER_API_PORT,
    )
