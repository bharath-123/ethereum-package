redis_module = import_module("github.com/kurtosis-tech/redis-package/main.star")
postgres_module = import_module("github.com/kurtosis-tech/postgres-package/main.star")
constants = import_module("../../../package_io/constants.star")
shared_utils = import_module("../../../shared_utils/shared_utils.star")
input_parser = import_module("../../../package_io/input_parser.star")
static_files = import_module("../../../static_files/static_files.star")

HELIX_RELAY_NAME="helix-relay"

HELIX_RELAY_CONFIG_FILENAME = "config.yaml"
HELIX_RELAY_MOUNT_DIRPATH_ON_SERVICE = "/config/"

HELIX_RELAY_ENDPOINT_PORT = 9062
HELIX_RELAY_WEBSITE_PORT = 9060
NETWORK_ID_TO_NAME = {
    "1": "mainnet",
    "17000": "holesky",
    "11155111": "sepolia",
    "560048": "hoodi",
}

# The min/max CPU/memory that mev-relay can use
RELAY_MIN_CPU = 500
RELAY_MAX_CPU = 3000
RELAY_MIN_MEMORY = 256
RELAY_MAX_MEMORY = 4096

# The min/max CPU/memory that postgres can use
POSTGRES_MIN_CPU = 10
POSTGRES_MAX_CPU = 1000
POSTGRES_MIN_MEMORY = 32
POSTGRES_MAX_MEMORY = 1024

# The min/max CPU/memory that redis can use
REDIS_MIN_CPU = 500
REDIS_MAX_CPU = 3000
REDIS_MIN_MEMORY = 16
REDIS_MAX_MEMORY = 1024


def launch_helix_relay(
    plan,
    mev_params,
    network_id,
    beacon_uris,
    validator_root,
    genesis_timestamp,
    blocksim_uri,
    network_params,
    persistent,
    port_publisher,
    index,
    global_node_selectors,
    global_tolerations,
):
    tolerations = shared_utils.get_tolerations(global_tolerations=global_tolerations)

    public_ports_for_component = shared_utils.get_public_ports_for_component(
        "mev",
        port_publisher,
        index
    )
    public_port_assignments = {
        constants.HTTP_PORT_ID: public_ports_for_component[0],
        constants.HTTP_PORT_ID: public_ports_for_component[1],
    }
    public_ports = shared_utils.get_port_specs(public_port_assignments)
    

    node_selectors = global_node_selectors
    redis = redis_module.run(
        plan,
        service_name="helix-relay-redis",
        min_cpu=REDIS_MIN_CPU,
        max_cpu=REDIS_MAX_CPU,
        min_memory=REDIS_MIN_MEMORY,
        max_memory=REDIS_MAX_MEMORY,
        node_selectors=node_selectors,
        tolerations=tolerations,
    )
    # making the password postgres as the relay expects it to be postgres
    postgres = postgres_module.run(
        plan,
        password="postgres",
        user="postgres",
        database="postgres",
        service_name="helix-relay-postgres",
        persistent=persistent,
        launch_adminer=mev_params.launch_adminer,
        min_cpu=POSTGRES_MIN_CPU,
        max_cpu=POSTGRES_MAX_CPU,
        min_memory=POSTGRES_MIN_MEMORY,
        max_memory=POSTGRES_MAX_MEMORY,
        node_selectors=node_selectors,
        tolerations=tolerations,
    )

    network_name = NETWORK_ID_TO_NAME.get(network_id, network_id)

    image = mev_params.helix_relay_image

    env_vars = {
        "RELAY_KEY": constants.DEFAULT_MEV_PUBKEY,
    }

    redis_url = "{}:{}".format(redis.hostname, redis.port_number)
    postgres_url = postgres.url + "?sslmode=disable"

    api = plan.add_service(
        name=HELIX_RELAY_NAME,
        config=ServiceConfig(
            image=image,
            cmd=[
                "--config",
                config_file_path,
            ],
            ports={
                "http": PortSpec(
                    number=MEV_RELAY_ENDPOINT_PORT, transport_protocol="TCP"
                ),
                "http": PortSpec(
                    number=MEV_RELAY_WEBSITE_PORT, transport_protocol="TCP"
                ),
            },
            public_ports=public_ports,
            env_vars=env_vars | mev_params.mev_relay_api_extra_env_vars,
            min_cpu=RELAY_MIN_CPU,
            max_cpu=RELAY_MAX_CPU,
            min_memory=RELAY_MIN_MEMORY,
            max_memory=RELAY_MAX_MEMORY,
            node_selectors=node_selectors,
            tolerations=tolerations,
        ),
    )

    return "http://{0}@{1}:{2}".format(
        constants.DEFAULT_MEV_PUBKEY, api.ip_address, MEV_RELAY_ENDPOINT_PORT
    )

def new_helix_relay_config_template_data(
    network,
    genesis_timestamp,
    blocksim_uri,
    beacon_uris,
    validator_root,
):
    return {
        "Network": network,
        "GenesisTimestamp": genesis_timestamp, 
        "BlocksimURI": blocksim_uri,
        "BeaconURIs": beacon_uris,
        "ValidatorRoot": validator_root,
    }