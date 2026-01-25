load("ext://dotenv", "dotenv")

try:
    dotenv(fn=".env.local")
except:
    pass

local_resource(
    "install",
    cmd="bun install",
    labels=["setup"],
)

local_resource(
    "build",
    cmd="anchor build",
    deps=["programs"],
    labels=["build"],
    resource_deps=["install"],
)

local_resource(
    "validator",
    serve_cmd="./scripts/start-validator.sh",
    labels=["solana"],
    resource_deps=["build"],
)

local_resource(
    "init-config",
    cmd="bun run scripts/init-config.ts",
    labels=["setup"],
    resource_deps=["validator"],
    auto_init=False,
)
