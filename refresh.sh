#!/bin/bash

# Install curl before we do anything else
echo "Installing curl and jq..."
sudo apt-get install -y curl jq

ASSETS=$(curl -s https://api.github.com/repos/vulcanocrypto/vulcano/releases/latest | jq '.assets')

BOOTSTRAPURL=$(echo "$ASSETS" | jq -r '.[] | select(.name == "bootstrap.dat.xz").browser_download_url')
BOOTSTRAPARCHIVE="bootstrap.dat.xz"
PEERSURL=$(echo "$ASSETS" | jq -r '.[] | select(.name|test("peers.dat.xz")).browser_download_url')
PEERSARCHIVE="peers.dat.xz"

# Make sure curl and jq are installed
apt -qqy install curl jq
clear

clear
echo "This script will refresh your wallet."
read -pr "Press Ctrl-C to abort or any other key to continue. " -n1 -s
clear

USER=vulcano
USERHOME=/home/vulcano

sudo systemctl stop vulcanod

echo "Refreshing node, please wait."

sleep 5

sudo rm -Rf "$USERHOME/.vulcanocore/blocks"
sudo rm -Rf "$USERHOME/.vulcanocore/database"
sudo rm -Rf "$USERHOME/.vulcanocore/chainstate"
sudo rm -Rf "$USERHOME/.vulcanocore/peers.dat"

echo "Installing bootstrap file..."
sudo wget "$BOOTSTRAPURL" && sudo xz -d $BOOTSTRAPARCHIVE && sudo mv "./bootstrap.dat"  "$USERHOME/.vulcanocore/bootstrap.dat" && rm $BOOTSTRAPARCHIVE
sudo wget "$PEERSURL" && sudo xz -d "$PEERSARCHIVE" && sudo mv "peers.dat" "/home/vulcano/.vulcanocore/"

sudo systemctl start vulcanod

clear

echo "Your wallet is syncing. Please wait for this process to finish."
echo "This can take up to a few hours. Do not close this window." && echo ""

until [ -n "$(vulcano-cli getconnectioncount 2>/dev/null)"  ]; do
  sleep 1
done

until sudo su -c "vulcano-cli mnsync status 2>/dev/null" vulcano | jq '.IsBlockchainSynced' | grep true &>/dev/null; do
  echo -ne "Current block: $(sudo su -c "vulcano-cli getinfo" vulcano | jq '.blocks')\\r"
  sleep 1
done

clear

echo "" && echo "Wallet refresh completed. Do not forget to unlock your wallet!" && echo ""
