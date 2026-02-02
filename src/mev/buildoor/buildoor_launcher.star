constants = import_module("../../package_io/constants.star")
shared_utils = import_module("../../shared_utils/shared_utils.star")

BUILDOOR_SERVICE_NAME = "buildoor"
BUILDOOR_BUILDER_API_PORT = 9000
BUILDOOR_API_PORT = 8080

HTTP_PORT_ID = "http"
API_PORT_ID = "api"

USED_PORTS = {
    HTTP_PORT_ID: shared_utils.new_port_spec(
        BUILDOOR_BUILDER_API_PORT,
        shared_utils.TCP_PROTOCOL,
        shared_utils.HTTP_APPLICATION_PROTOCOL,
    ),
    API_PORT_ID: shared_utils.new_port_spec(
        BUILDOOR_API_PORT,
        shared_utils.TCP_PROTOCOL,
        shared_utils.HTTP_APPLICATION_PROTOCOL,
    ),
}

# The min/max CPU/memory that buildoor can use
MIN_CPU = 100
MAX_CPU = 2000
MIN_MEMORY = 256
MAX_MEMORY = 2048


def launch_buildoor(
    plan,
    mev_params,
    builder_cl_context,
    builder_el_context,
    jwt_file,
    port_publisher,
    index,
    global_node_selectors,
    global_tolerations,
):
    """
    Launch buildoor builder service with dedicated CL-EL pair.
    
    Args:
        plan: Kurtosis plan
        mev_params: MEV parameters containing mev_relay_image (buildoor image)
        builder_cl_context: Consensus layer context for the builder CL client
        builder_el_context: Execution layer context for the builder EL client
        jwt_file: JWT secret file artifact
        port_publisher: Port publisher for public ports
        index: Service index for port allocation
        global_node_selectors: Node selectors
        global_tolerations: Tolerations
    
    Returns:
        Builder API endpoint URL in format: http://{pubkey}@{ip}:{port}
    """
    tolerations = shared_utils.get_tolerations(global_tolerations=global_tolerations)
    node_selectors = global_node_selectors
    
    # Build CL beacon URI from the builder CL context
    beacon_uri = builder_cl_context.beacon_http_url
    
    # Build EL engine API URI from the builder EL context
    el_engine_api_uri = "http://{0}:{1}".format(
        builder_el_context.dns_name,
        builder_el_context.engine_rpc_port_num,
    )
    
    public_ports = shared_utils.get_mev_public_port(
        port_publisher,
        constants.HTTP_PORT_ID,
        index,
        0,
    )
    
    # Add public port for API port (8080) - use port_index 1 for the second port
    if port_publisher.mev_enabled:
        api_public_ports = shared_utils.get_mev_public_port(
            port_publisher,
            API_PORT_ID,
            index,
            1,
        )
        public_ports.update(api_public_ports)
    
    # Build command for buildoor
    cmd = [
        "run",
        "--builder-privkey", constants.DEFAULT_MEV_SECRET_KEY,
        "--cl-client", beacon_uri,
        "--el-engine-api", el_engine_api_uri,
        "--el-jwt-secret", constants.JWT_MOUNT_PATH_ON_CONTAINER,
        "--builder-api-enabled",
        "--builder-api-port", str(BUILDOOR_BUILDER_API_PORT),
        "--api-port", str(BUILDOOR_API_PORT),
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
