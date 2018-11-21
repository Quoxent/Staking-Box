#!/bin/bash

# Install curl before we do anything else
echo "Installing curl and jq..."
sudo apt-get install -y curl jq

ASSETS=$(curl -s https://api.github.com/repos/vulcanocrypto/vulcano/releases/latest | jq '.assets')

VPSTARBALLURL=$(echo "$ASSETS" | jq -r '.[] | select(.name|test("vulcano.*linux64")).browser_download_url')
VPSTARBALLNAME=$(echo "$VPSTARBALLURL" | cut -d "/" -f 9)
SHNTARBALLURL=$(echo "$ASSETS" | jq -r '.[] | select(.name|test("vulcano.*ARM")).browser_download_url')
SHNTARBALLNAME=$(echo "$SHNTARBALLURL" | cut -d "/" -f 9)

clear
echo "This script will update your wallet to the latest version of Vulcano."
read -rp "Press Ctrl-C to abort or any other key to continue. " -n1 -s
clear

USER="vulcano"
USERHOME="/home/vulcano"

echo "Shutting down wallet..."
if [ -e /etc/systemd/system/vulcanod.service ]; then
  sudo systemctl stop vulcanod
else
  sudo su -c "vulcano-cli stop" "vulcano"
fi

echo "Downloading and installing binaries..."
if grep -q "ARMv7" /proc/cpuinfo; then
  # Install Vulcano daemon for ARMv7 systems
  sudo wget "$SHNTARBALLURL"
  sudo tar -xzvf "$SHNTARBALLNAME" -C /usr/local/bin
  sudo rm "$SHNTARBALLNAME"
else
  # Install Vulcano daemon for x86 systems
  sudo wget "$VPSTARBALLURL"
  sudo tar -xzvf "$VPSTARBALLNAME" -C /usr/local/bin
  sudo rm "$VPSTARBALLNAME"
fi

if [ -e /usr/bin/vulcanod ];then sudo rm -rf /usr/bin/vulcanod; fi
if [ -e /usr/bin/vulcano-cli ];then sudo rm -rf /usr/bin/vulcano-cli; fi
if [ -e /usr/bin/vulcano-tx ];then sudo rm -rf /usr/bin/vulcano-tx; fi

# Add Fail2Ban memory hack if needed
if ! grep -q "ulimit -s 256" /etc/default/fail2ban; then
  echo "ulimit -s 256" | sudo tee -a /etc/default/fail2ban
  sudo systemctl restart fail2ban
fi

# Update vulcano-decrypt
if [  -e /usr/local/bin/vulcano-decrypt ]; then sudo rm /usr/local/bin/vulcano-decrypt; fi

sudo tee &> /dev/null /usr/local/bin/vulcano-decrypt << EOL
#!/bin/bash

# Stop writing to history
set +o history

# Confirm wallet is synced
until sudo su -c "vulcano-cli mnsync status 2>/dev/null" vulcano | jq '.IsBlockchainSynced' | grep -q true; do
  echo -ne "Current block: \$(sudo su -c "vulcano-cli getinfo" vulcano | jq '.blocks')\\r"
  sleep 1
done

# Unlock wallet
until sudo su -c "vulcano-cli getstakingstatus" vulcano | jq '.walletunlocked' | grep -q true; do

  #ask for password and attempt it
  read -e -s -p "Please enter a password to decrypt your staking wallet. Your password will not show as you type : " ENCRYPTIONKEY
  sudo su -c "vulcano-cli walletpassphrase '\$ENCRYPTIONKEY' 0 true" vulcano
done

# Tell user all was successful
echo "Wallet successfully unlocked!"
echo " "
sudo su -c "vulcano-cli getstakingstatus" vulcano

# Restart history
set -o history
EOL

sudo chmod a+x /usr/local/bin/vulcano-decrypt

echo "Restarting Vulcano daemon..."
if [ -e /etc/systemd/system/vulcanod.service ]; then
  sudo systemctl disable vulcanod
  sudo rm /etc/systemd/system/vulcanod.service
fi

sudo tee &> /dev/null /etc/systemd/system/vulcanod.service << EOL
[Unit]
Description=Vulcano's distributed currency daemon
After=network.target
[Service]
Type=forking
User=${USER}
WorkingDirectory=${USERHOME}
ExecStart=/usr/local/bin/vulcanod -conf=${USERHOME}/.vulcanocore/vulcano.conf -datadir=${USERHOME}/.vulcanocore
ExecStop=/usr/local/bin/vulcano-cli -conf=${USERHOME}/.vulcanocore/vulcano.conf -datadir=${USERHOME}/.vulcanocore stop
Restart=on-failure
RestartSec=1m
StartLimitIntervalSec=5m
StartLimitInterval=5m
StartLimitBurst=3
[Install]
WantedBy=multi-user.target
EOL
sudo systemctl enable vulcanod
sudo systemctl start vulcanod

echo "Waiting for vulcanod to connect..."

until [ -n "$(sudo su -c 'vulcano-cli getconnectioncount' vulcano 2>/dev/null)"  ]; do
  sleep 1
done

clear

echo "Your wallet is syncing. Please wait for this process to finish."

until sudo su -c "vulcano-cli mnsync status 2>/dev/null" vulcano | jq '.IsBlockchainSynced' | grep -q true; do
  echo -ne "Current block: $(sudo su -c "vulcano-cli getinfo" vulcano | jq '.blocks')\\r"
  sleep 1
done

clear

echo "Vulcano is now up to date. Do not forget to unlock your wallet!"
