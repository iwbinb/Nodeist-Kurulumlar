#!/bin/bash
echo "=================================================="
echo -e "\033[0;35m"
echo " | \ | |         | |    (_)   | |  ";
echo " |  \| | ___   __| | ___ _ ___| |_ ";
echo " |     |/ _ \ / _  |/ _ \ / __| __| ";
echo " | |\  | (_) | (_| |  __/ \__ \ |_ ";
echo " |_| \_|\___/ \__,_|\___|_|___/\__| ";
echo -e "\e[0m"
echo "=================================================="                                                            
sleep 2
# set vars
if [ ! $NODENAME ]; then
	read -p "Node ismi yaziniz: " NODENAME
	echo 'export NODENAME='$NODENAME >> $HOME/.bash_profile
fi
echo "export WALLET=wallet" >> $HOME/.bash_profile
echo "export CHAIN_ID=defund-private-1" >> $HOME/.bash_profile
source $HOME/.bash_profile

echo '================================================='
echo 'Node isminiz: ' $NODENAME
echo 'Cüzdan isminiz: ' $WALLET
echo 'Chain ismi: ' $CHAIN_ID
echo '================================================='
sleep 2
echo -e "\e[1m\e[32m1. Paketler güncelleniyor... \e[0m" && sleep 1
# update
sudo apt update && sudo apt upgrade -y
echo -e "\e[1m\e[32m2. Bagliliklar yukleniyor... \e[0m" && sleep 1

# packages
sudo apt install curl tar wget clang pkg-config libssl-dev jq build-essential git make ncdu -y

# install go
ver="1.17.2"
cd $HOME
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
rm "go$ver.linux-amd64.tar.gz"
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile
source ~/.bash_profile
go version

echo -e "\e[1m\e[32m3. kutuphaneler indirilip yukleniyor... \e[0m" && sleep 1
# download and build binary
cd $HOME
rm -rf celestia-app
git clone https://github.com/celestiaorg/celestia-app.git
cd celestia-app
APP_VERSION=$(curl -s https://api.github.com/repos/celestiaorg/celestia-app/releases/latest | jq -r ".tag_name")
git checkout tags/$APP_VERSION -b $APP_VERSION
make install

# setup p2p networks
cd $HOME
rm -rf networks
git clone https://github.com/celestiaorg/networks.git

# config
celestia-appd config chain-id $CHAIN_ID
celestia-appd config keyring-backend file

# init
celestia-appd init $NODENAME --chain-id $CHAIN_ID

# update genesis
cp $HOME/networks/$CHAIN_ID/genesis.json $HOME/.celestia-app/config

# set minimum gas price
sed -i -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0utia\"/" $HOME/.celestia-app/config/app.toml

# set peers and seeds
BOOTSTRAP_PEERS=$(curl -sL https://raw.githubusercontent.com/celestiaorg/networks/master/mamaki/bootstrap-peers.txt | tr -d '\n')
PEERS="d0b19e4d133441fd41b4d74ac8de2138313ad49e@195.201.41.137:26656,6c076056fc80a813b26e24ba8d28fa374cd72777@149.102.153.197:26656,f7b68a491bae4b10dbab09bb3a875781a01274a5@65.108.199.79:20356,853a9fbb633aed7b6a8c759ba99d1a7674b706a3@38.242.216.151:26656,42b331adaa9ece4c455b92f0d26e3382e46d43f0@161.97.180.20:36656,180378bab87c9cecea544eb406fcd8fcd2cbc21b@168.119.122.78:26656"
sed -i.bak -e "s/^bootstrap-peers *=.*/bootstrap-peers = \"$BOOTSTRAP_PEERS\"/" $HOME/.celestia-app/config/config.toml
sed -i.bak -e "s/^persistent-peers *=.*/persistent-peers = \"$PEERS\"/" $HOME/.celestia-app/config/config.toml

# enable prometheus
sed -i -e "s/prometheus = false/prometheus = true/" $HOME/.celestia-app/config/config.toml

# config pruning
pruning="custom"
pruning_keep_recent="100"
pruning_keep_every="5000"
pruning_interval="10"

sed -i -e "s/^pruning *=.*/pruning = \"$pruning\"/" $HOME/.celestia-app/config/app.toml
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"$pruning_keep_recent\"/" $HOME/.celestia-app/config/app.toml
sed -i -e "s/^pruning-keep-every *=.*/pruning-keep-every = \"$pruning_keep_every\"/" $HOME/.celestia-app/config/app.toml
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"$pruning_interval\"/" $HOME/.celestia-app/config/app.toml

# set timeouts
sed -i.bak -e "s/^timeout-commit *=.*/timeout-commit = \"25s\"/" $HOME/.celestia-app/config/config.toml
sed -i.bak -e "s/^skip-timeout-commit *=.*/skip-timeout-commit = false/" $HOME/.celestia-app/config/config.toml

# set validator mode
sed -i.bak -e "s/^mode *=.*/mode = \"validator\"/" $HOME/.celestia-app/config/config.toml

# set quicksync
function quickSync {
cd $HOME
rm -rf ~/.celestia-app/data
mkdir -p ~/.celestia-app/data
SNAP_NAME=$(curl -s https://snaps.qubelabs.io/celestia/ | egrep -o ">mamaki.*tar" | tr -d ">")
wget -O - https://snaps.qubelabs.io/celestia/${SNAP_NAME} | tar xf - -C ~/.celestia-app/data/
}

# let uset choose sync mode
while true; do
read -p "Do you want use Quick Sync for rapid data synchronization? (y/n) " yn
case $yn in 
	[yY] ) echo -e '\n\e[31mDownloading data using Quick Sync...\e[39m' && sleep 1
	quickSync
	    break;;
	[nN] ) echo -e '\n\e[31mSkipping Quick Sync...\e[39m' && sleep 1
		break;;
	* ) echo invalid response;;
esac
done

echo -e "\e[1m\e[32m4. Servisler başlatılıyor... \e[0m" && sleep 1
# create service
tee $HOME/celestia-appd.service > /dev/null <<EOF
[Unit]
Description=celestia-appd
After=network.target
[Service]
Type=simple
User=$USER
ExecStart=$(which celestia-appd) start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

sudo mv $HOME/celestia-appd.service /etc/systemd/system/

# start service
sudo systemctl daemon-reload
sudo systemctl enable celestia-appd
sudo systemctl restart celestia-appd

echo -e "\e[1m\e[32m5. köprü node kütüphaneleri indiriliyor... \e[0m" && sleep 1
# download and build binary
cd $HOME
rm -rf celestia-node
git clone https://github.com/celestiaorg/celestia-node.git
cd celestia-node
make install

# init bridge node to localhost
celestia bridge init --core.remote tcp://localhost:26657 --core.grpc tcp://localhost:9090

echo -e "\e[1m\e[32m6. köprü servisleri başlatılıyor... \e[0m" && sleep 1
# create service
tee /etc/systemd/system/celestia-bridge.service > /dev/null <<EOF
[Unit]
Description=celestia-bridge Cosmos daemon
After=network.target
[Service]
Type=simple
User=$USER
ExecStart=$HOME/go/bin/celestia bridge start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

# start service
sudo systemctl daemon-reload
sudo systemctl enable celestia-bridge
sudo systemctl restart celestia-bridge

echo '=============== SETUP FINISHED ==================='
echo -e 'To check validator logs: \e[1m\e[32mjournalctl -u celestia-appd -f -o cat \e[0m'
echo -e 'To check bridge logs: \e[1m\e[32mjournalctl -u celestia-bridge -f -o cat \e[0m'
echo -e 'To check sync status: \e[1m\e[32mcurl -s localhost:26657/status | jq .result.sync_info \e[0m'
