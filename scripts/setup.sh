#!/bin/bash
setup() {
sudo apt update && sudo apt install pigz wget jq curl repo -y
sudo apt upgrade -y
}
echo "Setting Up AOSP Build Environment"
setup
