#!/bin/bash

# Start Nitro dev node in the background
echo "Starting Nitro dev node..."
docker run --rm --name nitro-dev -p 8547:8547 offchainlabs/nitro-node:v3.2.1-d81324d --dev --http.addr 0.0.0.0 --http.api=net,web3,eth,debug --http.corsdomain="*" &

# Wait for the node to initialize
echo "Waiting for the Nitro node to initialize..."

until [[ "$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  http://127.0.0.1:8547)" == *"result"* ]]; do
    sleep 0.1
done

# Check if node is running
curl_output=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  http://127.0.0.1:8547)

if [[ "$curl_output" == *"result"* ]]; then
  echo "Nitro node is running!"
else
  echo "Failed to start Nitro node."
  exit 1
fi

# Make the caller a chain owner
echo "Setting chain owner to pre-funded dev account..."
cast send 0x00000000000000000000000000000000000000FF "becomeChainOwner()" \
  --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
  --rpc-url http://127.0.0.1:8547

# Deploy Cache Manager Contract
echo "Deploying Cache Manager contract..."
deploy_output=$(cast send --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
  --rpc-url http://127.0.0.1:8547 \
  --create 0x60a06040523060805234801561001457600080fd5b50608051611d1c61003060003960006105260152611d1c6000f3fe)

# Extract contract address using awk from plain text output
cache_manager_address=$(echo "$deploy_output" | awk '/contractAddress/ {print $2}')

if [[ -z "$cache_manager_address" ]]; then
  echo "Error: Failed to extract Cache Manager contract address. Full output:"
  echo "$deploy_output"
  exit 1
fi

echo "Cache Manager contract deployed at address: $cache_manager_address"

# Register the deployed Cache Manager contract
echo "Registering Cache Manager contract as a WASM cache manager..."
registration_output=$(cast send --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
  --rpc-url http://127.0.0.1:8547 \
  0x0000000000000000000000000000000000000070 \
  "addWasmCacheManager(address)" "$cache_manager_address")

if [[ "$registration_output" == *"error"* ]]; then
  echo "Failed to register Cache Manager contract. Registration output:"
  echo "$registration_output"
  exit 1
fi

echo "Cache Manager deployed and registered successfully."

# Deploy the contract using cargo stylus
# Deploy the contract using cargo stylus
echo "Deploying the contract using cargo stylus..."
deploy_output=$(cargo stylus deploy -e http://127.0.0.1:8547 --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659)

# Check if deployment was successful
if [[ $? -ne 0 ]]; then
    echo "Error: Contract deployment failed"
    echo "Deploy output: $deploy_output"
    exit 1
fi

# Extract deployment transaction hash from the output
# Assuming the output contains a transaction hash in the format 0x...
deployment_tx=$(echo "$deploy_output" | grep -oE '0x[a-fA-F0-9]{64}')

if [[ -z "$deployment_tx" ]]; then
    echo "Error: Could not extract deployment transaction hash from output"
    echo "Deploy output: $deploy_output"
    exit 1
fi

echo "Deployment transaction hash: $deployment_tx"

# Extract contract address from deploy output (if available)
contract_address=$(echo "$deploy_output" | grep -oE '0x[a-fA-F0-9]{40}')
if [[ ! -z "$contract_address" ]]; then
    echo "Contract address: $contract_address"
fi

# Wait for deployment transaction to be confirmed by verifying with cargo stylus
# echo "Waiting for deployment verification..."
# max_attempts=30  # Maximum number of attempts (30 * 2 seconds = 1 minute timeout)
# attempt=1

# while [ $attempt -le $max_attempts ]; do
#     verify_output=$(cargo stylus verify -e http://127.0.0.1:8547 --deployment-tx "$deployment_tx" 2>&1)
#     echo "verify_output: $verify_output"
#     verify_status=$?
    
#     if [ $verify_status -eq 0 ]; then
#         echo "Contract verification successful!"
#         break
#     else
#         echo "Attempt $attempt of $max_attempts: Waiting for contract to be verifiable..."
#         if [ $attempt -eq $max_attempts ]; then
#             echo "Error: Contract verification timed out after $max_attempts attempts"
#             echo "Last verification attempt output: $verify_output"
#             exit 1
#         fi
#         ((attempt++))
#         sleep 2
#     fi
# done

############################################
# Generate the ABI for the deployed contract
echo "Generating ABI for the deployed contract..."
cargo stylus export-abi

# Verify if ABI generation was successful
if [[ $? -ne 0 ]]; then
  echo "Error: ABI generation failed."
  exit 1
fi

echo "ABI generated successfully. Nitro node is running..."

# Keep the script running but also monitor the Nitro node
while true; do
  if ! docker ps | grep -q nitro-dev; then
    echo "Nitro node container stopped unexpectedly"
    exit 1
  fi
  sleep 5
done