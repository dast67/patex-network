#!/usr/bin/env bash

# This script starts a local devnet using Docker Compose. We have to use
# this more complicated Bash script rather than Compose's native orchestration
# tooling because we need to start each service in a specific order, and specify
# their configuration along the way. The order is:
#
# 4. Start L2
# 5. Get the genesis
# 6. Generate the rollup driver's config using the genesis hashes and the
#    timestamps recovered in step 4 as well as the address of the PatexPortal
#    contract deployed in step 3.
# 7. Start the rollup driver.
# 8. Start the L2 output submitter.
#
# The timestamps are critically important here, since the rollup driver will fill in
# empty blocks if the tip of L1 lags behind the current timestamp. This can lead to
# a perceived infinite loop. To get around this, we set the timestamp to the current
# time in this script.
#
# This script is safe to run multiple times. It stores state in `.devnet`, and
# contracts-bedrock/deployments/devnetL1.
#
# Don't run this script directly. Run it using the makefile, e.g. `make devnet-up`.
# To clean up your devnet, run `make devnet-clean`.

set -eu

L1_URL="https://ethereum-sepolia-archive.allthatnode.com"
L2_URL="http://localhost:9545"

PT_NODE="$PWD/pt-node"
CONTRACTS_BEDROCK="$PWD/packages/contracts-bedrock"
NETWORK=devnetL1
TESTNET="$PWD/.patex-sepolia"
set L2OO_ADDRESS="0x6812B7b79E66a32D5f763cAaca592a692eA10698"

PT_GETH_GENESIS_URL="https://sepolia.patex.io/genesis.json"
PT_NODE_ROLLUP_URL="https://sepolia.patex.io/rollup.json"

# Helper method that waits for a given URL to be up. Can't use
# cURL's built-in retry logic because connection reset errors
# are ignored unless you're using a very recent version of cURL
function wait_up {
  echo -n "Waiting for $1 to come up..."
  i=0
  until curl -s -f -o /dev/null "$1"
  do
    echo -n .
    sleep 0.25

    ((i=i+1))
    if [ "$i" -eq 300 ]; then
      echo " Timeout!" >&2
      exit 1
    fi
  done
  echo "Done!"
}

mkdir -p ./.patex-sepolia

# Download genesis file if not exists
if [ ! -f "$TESTNET/genesis.json" ]; then
  wget -O "$TESTNET"/genesis.json "$PT_GETH_GENESIS_URL"
fi
# Download rollup file if not exists
if [ ! -f "$TESTNET/rollup.json" ]; then
  wget -O "$TESTNET"/rollup.json "$PT_NODE_ROLLUP_URL"
fi

# Generate jwt if not exists
if [ ! -f "$TESTNET/jwt.txt" ]; then
  openssl rand -hex 32 > "$TESTNET"/jwt.txt
fi

# Bring up L2.
(
  cd ops-bedrock/patex-sepolia
  echo "Bringing up L2..."
  DOCKER_BUILDKIT=1 docker-compose build --progress plain
  docker-compose up -d l2
  wait_up $L2_URL
)



# Bring up pt-node
(
  cd ops-bedrock/patex-sepolia
  echo "Bringing up pt-node..."
  docker-compose up -d pt-node
)

echo "Patex Testnet ready."