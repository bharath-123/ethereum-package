shared_utils = import_module("../../shared_utils/shared_utils.star")
input_parser = import_module("../../package_io/input_parser.star")
cl_context = import_module("../../cl/cl_context.star")
cl_node_ready_conditions = import_module("../../cl/cl_node_ready_conditions.star")
cl_shared = import_module("../cl_shared.star")
node_metrics = import_module("../../node_metrics_info.star")
constants = import_module("../../package_io/constants.star")
static_files = import_module("../../static_files/static_files.star")

PRYSM_ENTRYPOINT_COMMAND = "/beacon-chain"

# Builder whitelist config
BUILDER_WHITELIST_FILENAME = "builder-whitelist.yaml"
BUILDER_WHITELIST_MOUNT_DIRPATH = "/builder-config/"

#  ---------------------------------- Beacon client -------------------------------------
BEACON_DATA_DIRPATH_ON_SERVICE_CONTAINER = "/data/prysm/beacon-data/"

# Port nums
DISCOVERY_TCP_PORT_NUM = 13000
DISCOVERY_UDP_PORT_NUM = 12000
DISCOVERY_QUIC_PORT_NUM = 13000
BEACON_HTTP_PORT_NUM = 3500
RPC_PORT_NUM = 4000
BEACON_MONITORING_PORT_NUM = 8080
PROFILING_PORT_NUM = 6060

METRICS_PATH = "/metrics"

VERBOSITY_LEVELS = {
    constants.GLOBAL_LOG_LEVEL.error: "error",
    constants.GLOBAL_LOG_LEVEL.warn: "warn",
    constants.GLOBAL_LOG_LEVEL.info: "info",
    constants.GLOBAL_LOG_LEVEL.debug: "debug",
    constants.GLOBAL_LOG_LEVEL.trace: "trace",
}


def launch(
    plan,
    launcher,
    beacon_service_name,
    participant,
    global_log_level,
    bootnode_contexts,
    el_context,
    full_name,
    node_keystore_files,
    snooper_el_engine_context,
    persistent,
    tolerations,
    node_selectors,
    checkpoint_sync_enabled,
    checkpoint_sync_url,
    port_publisher,
    participant_index,
    network_params,
    extra_files_artifacts,
    backend,
    tempo_otlp_grpc_url=None,
    bootnode_enr_override=None,
    cl_binary_artifact=None,
):
    beacon_config = get_beacon_config(
        plan,
        launcher,
        beacon_service_name,
        participant,
        global_log_level,
        bootnode_contexts,
        el_context,
        full_name,
        node_keystore_files,
        snooper_el_engine_context,
        persistent,
        tolerations,
        node_selectors,
        checkpoint_sync_enabled,
        checkpoint_sync_url,
        port_publisher,
        participant_index,
        network_params,
        extra_files_artifacts,
        backend,
        tempo_otlp_grpc_url,
        bootnode_enr_override,
        cl_binary_artifact,
    )

    beacon_service = plan.add_service(beacon_service_name, beacon_config)

    cl_context_obj = get_cl_context(
        plan,
        beacon_service_name,
        beacon_service,
        participant,
        snooper_el_engine_context,
        node_keystore_files,
        node_selectors,
    )

    return cl_context_obj


def get_beacon_config(
    plan,
    launcher,
    beacon_service_name,
    participant,
    global_log_level,
    bootnode_contexts,
    el_context,
    full_name,
    node_keystore_files,
    snooper_el_engine_context,
    persistent,
    tolerations,
    node_selectors,
    checkpoint_sync_enabled,
    checkpoint_sync_url,
    port_publisher,
    participant_index,
    network_params,
    extra_files_artifacts,
    backend,
    tempo_otlp_grpc_url,
    bootnode_enr_override=None,
    cl_binary_artifact=None,
):
    log_level = input_parser.get_client_log_level_or_default(
        participant.cl_log_level, global_log_level, VERBOSITY_LEVELS
    )

    # If snooper is enabled use the snooper engine context, otherwise use the execution client context
    if participant.snooper_enabled:
        EXECUTION_ENGINE_ENDPOINT = "http://{0}:{1}".format(
            snooper_el_engine_context.ip_addr,
            snooper_el_engine_context.engine_rpc_port_num,
        )
    else:
        EXECUTION_ENGINE_ENDPOINT = "http://{0}:{1}".format(
            el_context.dns_name,
            el_context.engine_rpc_port_num,
        )

    public_ports = {}
    public_ports_for_component = None
    if port_publisher.cl_enabled:
        public_ports_for_component = shared_utils.get_public_ports_for_component(
            "cl", port_publisher, participant_index
        )
        public_ports = cl_shared.get_general_cl_public_port_specs(
            public_ports_for_component
        )

        public_ports.update(
            shared_utils.get_port_specs(
                {constants.QUIC_DISCOVERY_PORT_ID: public_ports_for_component[0]}
            )
        )
        public_ports.update(
            shared_utils.get_port_specs(
                {constants.UDP_DISCOVERY_PORT_ID: public_ports_for_component[1]}
            )
        )
        public_ports.update(
            shared_utils.get_port_specs(
                {constants.RPC_PORT_ID: public_ports_for_component[5]}
            )
        )
        public_ports.update(
            shared_utils.get_port_specs(
                {constants.PROFILING_PORT_ID: public_ports_for_component[6]}
            )
        )

    discovery_port_tcp = (
        public_ports_for_component[0]
        if public_ports_for_component
        else DISCOVERY_TCP_PORT_NUM
    )
    discovery_port_udp = (
        public_ports_for_component[1]
        if public_ports_for_component
        else DISCOVERY_UDP_PORT_NUM
    )
    discovery_port_quic = (
        public_ports_for_component[0]
        if public_ports_for_component
        else DISCOVERY_QUIC_PORT_NUM
    )  # use the same port for quic and tcp

    used_port_assignments = {
        constants.TCP_DISCOVERY_PORT_ID: discovery_port_tcp,
        constants.UDP_DISCOVERY_PORT_ID: discovery_port_udp,
        constants.HTTP_PORT_ID: BEACON_HTTP_PORT_NUM,
        constants.METRICS_PORT_ID: BEACON_MONITORING_PORT_NUM,
        constants.QUIC_DISCOVERY_PORT_ID: discovery_port_quic,
        constants.RPC_PORT_ID: RPC_PORT_NUM,
        constants.PROFILING_PORT_ID: PROFILING_PORT_NUM,
    }
    # Disable port checks if skip_start is enabled
    if participant.skip_start:
        used_ports = shared_utils.get_port_specs(used_port_assignments, wait=None)
    else:
        used_ports = shared_utils.get_port_specs(used_port_assignments)

    cmd = [
        PRYSM_ENTRYPOINT_COMMAND,
        "--accept-terms-of-use=true",  # it's mandatory in order to run the node
        "--datadir=" + BEACON_DATA_DIRPATH_ON_SERVICE_CONTAINER,
        "--execution-endpoint=" + EXECUTION_ENGINE_ENDPOINT,
        "--rpc-host=0.0.0.0",
        "--rpc-port={0}".format(RPC_PORT_NUM),
        "--http-host=0.0.0.0",
        "--http-cors-domain=*",
        "--http-port={0}".format(BEACON_HTTP_PORT_NUM),
        "--p2p-host-ip={0}".format(
            "${K8S_POD_IP}"
            if backend == "kubernetes"
            else port_publisher.cl_nat_exit_ip
        ),
        "--p2p-tcp-port={0}".format(discovery_port_tcp),
        "--p2p-udp-port={0}".format(discovery_port_udp),
        "--p2p-quic-port={0}".format(discovery_port_quic),
        "--min-sync-peers={0}".format(constants.MIN_PEERS),
        "--verbosity=" + log_level,
        "--slots-per-archive-point={0}".format(32 if constants.ARCHIVE_MODE else 8192),
        "--suggested-fee-recipient=" + constants.VALIDATING_REWARDS_ACCOUNT,
        "--jwt-secret=" + constants.JWT_MOUNT_PATH_ON_CONTAINER,
        # vvvvvvvvv METRICS CONFIG vvvvvvvvvvvvvvvvvvvvv
        "--disable-monitoring=false",
        "--monitoring-host=0.0.0.0",
        "--monitoring-port={0}".format(BEACON_MONITORING_PORT_NUM),
        # vvvvvvvvv PROFILING CONFIG vvvvvvvvvvvvvvvvvvvvv
        "--pprof",
        "--pprofaddr=0.0.0.0",
        "--pprofport={0}".format(PROFILING_PORT_NUM),
    ]

    supernode_cmd = [
        "--subscribe-all-data-subnets=true",
    ]

    if network_params.perfect_peerdas_enabled and participant_index < 16:
        cmd.append(
            "--p2p-priv-key="
            + constants.NODE_KEY_MOUNTPOINT_ON_CLIENTS
            + "/node-key-file-{0}".format(participant_index + 1)
        )

    if participant.supernode:
        cmd.extend(supernode_cmd)

    if checkpoint_sync_enabled:
        cmd.append("--checkpoint-sync-url=" + checkpoint_sync_url)
        cmd.append("--genesis-beacon-api-url=" + checkpoint_sync_url)

    if network_params.preset == "minimal":
        cmd.append("--minimal-config=true")

    if bootnode_enr_override != None:
        cmd.append("--bootstrap-node=" + bootnode_enr_override)

    if network_params.network not in constants.PUBLIC_NETWORKS:
        cmd.append("--p2p-static-id=true")
        cmd.append(
            "--chain-config-file="
            + constants.GENESIS_CONFIG_MOUNT_PATH_ON_CONTAINER
            + "/config.yaml"
        )
        cmd.append(
            "--genesis-state="
            + constants.GENESIS_CONFIG_MOUNT_PATH_ON_CONTAINER
            + "/genesis.ssz",
        )
        cmd.append("--contract-deployment-block=0")
        if (
            network_params.network == constants.NETWORK_NAME.kurtosis
            or constants.NETWORK_NAME.shadowfork in network_params.network
        ):
            if bootnode_enr_override == None and bootnode_contexts != None:
                for ctx in bootnode_contexts[: constants.MAX_ENR_ENTRIES]:
                    cmd.append("--bootstrap-node=" + ctx.enr)
        elif network_params.network == constants.NETWORK_NAME.ephemery:
            cmd.append(
                "--genesis-beacon-api-url="
                + constants.CHECKPOINT_SYNC_URL[network_params.network]
            )
            if bootnode_enr_override == None:
                cmd.append(
                    "--bootstrap-node="
                    + constants.GENESIS_CONFIG_MOUNT_PATH_ON_CONTAINER
                    + "/bootstrap_nodes.yaml"
                )
        else:  # Devnets
            if bootnode_enr_override == None:
                cmd.append(
                    "--bootstrap-node="
                    + constants.GENESIS_CONFIG_MOUNT_PATH_ON_CONTAINER
                    + "/bootstrap_nodes.yaml"
                )
    else:  # Public network
        cmd.append("--{}".format(network_params.network))

    # Check if MEV relay is configured and use builder whitelist instead
    builder_whitelist_artifact = None
    if len(participant.cl_extra_params) > 0:
        relay_url, filtered_params = extract_mev_relay_url_from_params(
            participant.cl_extra_params
        )
        if relay_url:
            # Generate builder whitelist config
            builder_whitelist_artifact = generate_builder_whitelist_config(
                plan, beacon_service_name, [relay_url]
            )
            # Add the builder whitelist file flag instead of --http-mev-relay
            builder_whitelist_path = shared_utils.path_join(
                BUILDER_WHITELIST_MOUNT_DIRPATH, BUILDER_WHITELIST_FILENAME
            )
            cmd.append("--builder-whitelist-file=" + builder_whitelist_path)
            # Add the remaining params (without --http-mev-relay)
            cmd.extend([param for param in filtered_params])
        else:
            # No MEV relay, just add all extra params
            cmd.extend([param for param in participant.cl_extra_params])

    files = {
        constants.GENESIS_DATA_MOUNTPOINT_ON_CLIENTS: launcher.el_cl_genesis_data.files_artifact_uuid,
        constants.JWT_MOUNTPOINT_ON_CLIENTS: launcher.jwt_file,
    }
    
    # Mount builder whitelist config if generated
    if builder_whitelist_artifact:
        files[BUILDER_WHITELIST_MOUNT_DIRPATH] = builder_whitelist_artifact
    if network_params.perfect_peerdas_enabled and participant_index < 16:
        files[constants.NODE_KEY_MOUNTPOINT_ON_CLIENTS] = Directory(
            artifact_names=["node-key-file-{0}".format(participant_index + 1)]
        )
    if persistent:
        volume_size_key = (
            "devnets" if "devnet" in network_params.network else network_params.network
        )
        files[BEACON_DATA_DIRPATH_ON_SERVICE_CONTAINER] = Directory(
            persistent_key="data-{0}".format(beacon_service_name),
            size=int(participant.cl_volume_size)
            if int(participant.cl_volume_size) > 0
            else constants.VOLUME_SIZE[volume_size_key][
                constants.CL_TYPE.prysm + "_volume_size"
            ],
        )

    # Add extra mounts - automatically handle file uploads
    processed_mounts = shared_utils.process_extra_mounts(
        plan, participant.cl_extra_mounts, extra_files_artifacts
    )
    for mount_path, artifact in processed_mounts.items():
        files[mount_path] = artifact

    # Binary injection - mount custom binary directory if provided
    if cl_binary_artifact != None:
        files["/opt/bin"] = cl_binary_artifact.artifact

    # Build the command string, copying injected binary if provided
    cmd_str = " ".join(cmd)
    if cl_binary_artifact != None:
        cmd_str = (
            "cp /opt/bin/{0} /beacon-chain && exec ".format(cl_binary_artifact.filename)
            + cmd_str
        )
    else:
        cmd_str = "exec " + cmd_str

    config_args = {
        "image": participant.cl_image,
        "ports": used_ports,
        "public_ports": public_ports,
        "entrypoint": ["sh", "-c"],
        "cmd": [cmd_str],
        "files": files,
        "env_vars": participant.cl_extra_env_vars,
        "private_ip_address_placeholder": constants.PRIVATE_IP_ADDRESS_PLACEHOLDER,
        "labels": shared_utils.label_maker(
            client=constants.CL_TYPE.prysm,
            client_type=constants.CLIENT_TYPES.cl,
            image=participant.cl_image[-constants.MAX_LABEL_LENGTH :],
            connected_client=el_context.client_name,
            extra_labels=participant.cl_extra_labels
            | {constants.NODE_INDEX_LABEL_KEY: str(participant_index + 1)},
            supernode=participant.supernode,
        ),
        "tolerations": tolerations,
        "node_selectors": node_selectors,
        "tty_enabled": True,
    }

    if len(participant.cl_devices) > 0:
        config_args["devices"] = participant.cl_devices
    # Only add ready_conditions if not skipping start (port checks are already disabled via wait="disable")
    if not participant.skip_start:
        config_args["ready_conditions"] = cl_node_ready_conditions.get_ready_conditions(
            constants.HTTP_PORT_ID
        )

    if int(participant.cl_min_cpu) > 0:
        config_args["min_cpu"] = int(participant.cl_min_cpu)
    if int(participant.cl_max_cpu) > 0:
        config_args["max_cpu"] = int(participant.cl_max_cpu)
    if int(participant.cl_min_mem) > 0:
        config_args["min_memory"] = int(participant.cl_min_mem)
    if int(participant.cl_max_mem) > 0:
        config_args["max_memory"] = int(participant.cl_max_mem)
    return ServiceConfig(**config_args)


def get_cl_context(
    plan,
    service_name,
    service,
    participant,
    snooper_el_engine_context,
    node_keystore_files,
    node_selectors,
):
    beacon_http_port = service.ports[constants.HTTP_PORT_ID]

    beacon_http_url = "http://{0}:{1}".format(service.name, BEACON_HTTP_PORT_NUM)
    beacon_grpc_url = "{0}:{1}".format(service.name, RPC_PORT_NUM)

    # Skip HTTP requests if skip_start is enabled (service won't be running)
    if participant.skip_start:
        beacon_node_enr = ""
        beacon_multiaddr = ""
        beacon_peer_id = ""
    else:
        # TODO(old) add validator availability using the validator API: https://ethereum.github.io/beacon-APIs/?urls.primaryName=v1#/ValidatorRequiredApi | from eth2-merge-kurtosis-module
        beacon_node_identity_recipe = GetHttpRequestRecipe(
            endpoint="/eth/v1/node/identity",
            port_id=constants.HTTP_PORT_ID,
            extract={
                "enr": ".data.enr",
                "multiaddr": ".data.p2p_addresses[0]",
                "peer_id": ".data.peer_id",
            },
            headers={"Accept-Encoding": "identity"},
        )
        response = plan.request(
            recipe=beacon_node_identity_recipe, service_name=service_name
        )
        beacon_node_enr = response["extract.enr"]
        beacon_multiaddr = response["extract.multiaddr"]
        beacon_peer_id = response["extract.peer_id"]

    beacon_metrics_port = service.ports[constants.METRICS_PORT_ID]
    beacon_metrics_url = "{0}:{1}".format(service.name, beacon_metrics_port.number)
    beacon_node_metrics_info = node_metrics.new_node_metrics_info(
        service_name, METRICS_PATH, beacon_metrics_url
    )
    nodes_metrics_info = [beacon_node_metrics_info]

    return cl_context.new_cl_context(
        client_name="prysm",
        enr=beacon_node_enr,
        ip_addr=service.name,
        http_port=beacon_http_port.number,
        beacon_http_url=beacon_http_url,
        cl_nodes_metrics_info=nodes_metrics_info,
        beacon_service_name=service_name,
        beacon_grpc_url=beacon_grpc_url,
        multiaddr=beacon_multiaddr,
        peer_id=beacon_peer_id,
        snooper_enabled=participant.snooper_enabled,
        snooper_el_engine_context=snooper_el_engine_context,
        validator_keystore_files_artifact_uuid=node_keystore_files.files_artifact_uuid
        if node_keystore_files
        else "",
        supernode=participant.supernode,
    )


def new_prysm_launcher(
    el_cl_genesis_data,
    jwt_file,
):
    return struct(
        el_cl_genesis_data=el_cl_genesis_data,
        jwt_file=jwt_file,
    )


def get_blobber_config(
    plan,
    participant,
    beacon_service_name,
    beacon_http_url,
    node_keystore_files,
    node_selectors,
):
    blobber_config = None
    if participant.blobber_enabled:
        blobber_config = struct(
            service_name="{0}-{1}".format("blobber", beacon_service_name),
            beacon_http_url=beacon_http_url,
            node_keystore_files=node_keystore_files,
            node_selectors=node_selectors,
        )
    return blobber_config


def generate_builder_whitelist_config(plan, service_name, relay_urls):
    """Generate builder whitelist config file for Prysm.
    
    Args:
        plan: The Kurtosis plan
        service_name: Name of the beacon service
        relay_urls: List of relay URLs to add to the whitelist
    
    Returns:
        The artifact name containing the builder whitelist config
    """
    builders = []
    for url in relay_urls:
        builders.append({
            "URL": url,
            "MinBid": 0,  # Set to 0 for testing
        })
    
    template_data = {"Builders": builders}
    
    builder_whitelist_template = read_file(static_files.PRYSM_BUILDER_WHITELIST_FILEPATH)
    template_and_data = shared_utils.new_template_and_data(
        builder_whitelist_template, template_data
    )
    
    template_and_data_by_rel_dest_filepath = {}
    template_and_data_by_rel_dest_filepath[BUILDER_WHITELIST_FILENAME] = template_and_data
    
    config_files_artifact_name = plan.render_templates(
        template_and_data_by_rel_dest_filepath,
        "prysm-builder-whitelist-{0}".format(service_name),
    )
    
    return config_files_artifact_name


def extract_mev_relay_url_from_params(cl_extra_params):
    """Extract the MEV relay URL from cl_extra_params if present.
    
    Args:
        cl_extra_params: List of extra CL parameters
    
    Returns:
        Tuple of (relay_url or None, filtered_params without the --http-mev-relay flag)
    """
    relay_url = None
    filtered_params = []
    
    for param in cl_extra_params:
        if param.startswith("--http-mev-relay="):
            relay_url = param.split("=", 1)[1]
        else:
            filtered_params.append(param)
    
    return relay_url, filtered_params
