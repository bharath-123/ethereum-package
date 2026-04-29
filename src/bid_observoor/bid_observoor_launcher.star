shared_utils = import_module("../shared_utils/shared_utils.star")
constants = import_module("../package_io/constants.star")

SERVICE_NAME = "bid-observoor"

HTTP_PORT_ID = "http"
HTTP_PORT_NUMBER = 8080

USED_PORTS = {
    HTTP_PORT_ID: shared_utils.new_port_spec(
        HTTP_PORT_NUMBER,
        shared_utils.TCP_PROTOCOL,
        shared_utils.HTTP_APPLICATION_PROTOCOL,
    )
}


def launch_bid_observoor(
    plan,
    all_cl_contexts,
    bid_observoor_params,
    global_node_selectors,
    global_tolerations,
    port_publisher,
    additional_service_index,
):
    tolerations = shared_utils.get_tolerations(global_tolerations=global_tolerations)

    public_ports = shared_utils.get_additional_service_standard_public_port(
        port_publisher,
        constants.HTTP_PORT_ID,
        additional_service_index,
        0,
    )

    # The container's entrypoint is the bid-observoor Go binary. It serves
    # the static UI plus a websocket endpoint, and consumes the beacon node
    # SSE stream server-side, so the URL only needs to be reachable from
    # inside the Kurtosis network (in-cluster DNS works).
    if bid_observoor_params.beacon_url != "":
        beacon_url = bid_observoor_params.beacon_url
    elif len(all_cl_contexts) > 0:
        beacon_url = all_cl_contexts[0].beacon_http_url
    else:
        fail(
            "bid_observoor: no CL participants available and no beacon_url override provided"
        )

    cmd = [
        "--beacon-url",
        beacon_url,
        "--port",
        "{0}".format(HTTP_PORT_NUMBER),
    ]

    for extra_arg in bid_observoor_params.extra_args:
        cmd.append(extra_arg)

    config = ServiceConfig(
        image=bid_observoor_params.image,
        ports=USED_PORTS,
        public_ports=public_ports,
        cmd=cmd,
        env_vars=bid_observoor_params.extra_env_vars,
        min_cpu=bid_observoor_params.min_cpu,
        max_cpu=bid_observoor_params.max_cpu,
        min_memory=bid_observoor_params.min_mem,
        max_memory=bid_observoor_params.max_mem,
        node_selectors=global_node_selectors,
        tolerations=tolerations,
    )
    plan.add_service(SERVICE_NAME, config)
