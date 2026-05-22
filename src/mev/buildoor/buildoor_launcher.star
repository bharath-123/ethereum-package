constants = import_module("../../package_io/constants.star")
shared_utils = import_module("../../shared_utils/shared_utils.star")
static_files = import_module("../../static_files/static_files.star")

BUILDOOR_SERVICE_NAME = "buildoor"
BUILDOOR_API_PORT = 8080
BUILDOOR_BUILDER_API_PORT = 9000

BUILDOOR_CONFIG_FILENAME = "config.yaml"
BUILDOOR_CONFIG_MOUNT_DIRPATH = "/config"
BUILDOOR_CONFIG_ARTIFACT_NAME = "buildoor-config"

MIN_CPU = 100
MAX_CPU = 1000
MIN_MEMORY = 128
MAX_MEMORY = 1024


def launch_buildoor(
    plan,
    beacon_uri,
    el_rpc_uri,
    engine_rpc_uri,
    jwt_file,
    prefunded_key,
    buildoor_params,
    global_node_selectors,
    global_tolerations,
    builder_bls_secret_key=None,
):
    tolerations = shared_utils.get_tolerations(global_tolerations=global_tolerations)

    # Strip 0x prefix if present since keys are expected as hex-only
    wallet_key = prefunded_key
    if wallet_key.startswith("0x"):
        wallet_key = wallet_key[2:]

    # Use injected builder BLS key if provided, otherwise fall back to default
    if builder_bls_secret_key != None:
        builder_bls_key = builder_bls_secret_key
    else:
        builder_bls_key = constants.DEFAULT_MEV_SECRET_KEY[2:]

    config_template = read_file(static_files.BUILDOOR_CONFIG_FILEPATH)
    template_data = {
        "CLClient": beacon_uri,
        "ELEngineAPI": engine_rpc_uri,
        "ELJWTSecret": constants.JWT_MOUNT_PATH_ON_CONTAINER,
        "ELRPC": el_rpc_uri,
        "BuilderPrivkey": builder_bls_key,
        "WalletPrivkey": wallet_key,
        "APIPort": BUILDOOR_API_PORT,
        "EPBSEnabled": buildoor_params.epbs_builder,
        "LifecycleEnabled": buildoor_params.lifecycle_enabled,
        "BuilderAPIEnabled": buildoor_params.builder_api,
        "BuilderAPIPort": BUILDOOR_BUILDER_API_PORT,
    }

    config_artifact = plan.render_templates(
        {BUILDOOR_CONFIG_FILENAME: shared_utils.new_template_and_data(config_template, template_data)},
        BUILDOOR_CONFIG_ARTIFACT_NAME,
    )

    config_file_path = shared_utils.path_join(
        BUILDOOR_CONFIG_MOUNT_DIRPATH, BUILDOOR_CONFIG_FILENAME
    )

    buildoor_service = plan.add_service(
        name=BUILDOOR_SERVICE_NAME,
        config=ServiceConfig(
            image=buildoor_params.image,
            ports={
                "api": PortSpec(
                    number=BUILDOOR_API_PORT,
                    transport_protocol="TCP",
                    application_protocol="http",
                ),
                "builder-api": PortSpec(
                    number=BUILDOOR_BUILDER_API_PORT, transport_protocol="TCP"
                ),
            },
            cmd=["run", "--config", config_file_path],
            files={
                constants.JWT_MOUNTPOINT_ON_CLIENTS: jwt_file,
                BUILDOOR_CONFIG_MOUNT_DIRPATH: config_artifact,
            },
            min_cpu=MIN_CPU,
            max_cpu=MAX_CPU,
            min_memory=MIN_MEMORY,
            max_memory=MAX_MEMORY,
            node_selectors=global_node_selectors,
            tolerations=tolerations,
        ),
    )
    return "http://{0}@{1}:{2}".format(
        constants.DEFAULT_MEV_PUBKEY, BUILDOOR_SERVICE_NAME, BUILDOOR_BUILDER_API_PORT
    )
