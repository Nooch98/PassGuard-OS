#!/bin/bash
clear

if [ -z "$1" ]; then
    echo -e "\e[33mDrag and drop your .json file here or paste the path and press Enter:\e[0m"
    read -r JsonPath
else
    JsonPath=$1
fi

JsonPath=$(echo "$JsonPath" | sed "s/['\"]//g")

if [ ! -f "$JsonPath" ]; then
    echo -e "\e[31mError: File not found at $JsonPath\e[0m"
    exit 1
fi

HostName=$(grep -oP '"name":\s*"\K[^"]+' "$JsonPath")

if [ -z "$HostName" ]; then
    echo -e "\e[31mError: Could not read 'name' field from JSON.\e[0m"
    exit 1
fi

echo -e "\e[36m--- Native Messaging Host Manager: $HostName ---\e[0m"
echo "1) Register Host"
echo "2) Remove Host"
echo "3) Exit"
read -p "Select an action (1-3): " action

if [ "$action" == "3" ]; then exit 0; fi

echo -e "\nSelect the browser:"
echo "1) Google Chrome"
echo "2) Mozilla Firefox"
echo "3) Brave Browser"
echo "4) Chromium / Vivaldi"
echo "5) Microsoft Edge"
echo "6) ALL OF THE ABOVE"
read -p "Choose an option (1-6): " browserOption

declare -A paths
paths["1"]="$HOME/.config/google-chrome/NativeMessagingHosts"
paths["2"]="$HOME/.mozilla/native-messaging-hosts"
paths["3"]="$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
paths["4"]="$HOME/.config/chromium/NativeMessagingHosts"
paths["5"]="$HOME/.config/microsoft-edge/NativeMessagingHosts"

register_host() {
    local destination=$1
    if [ -z "$destination" ]; then return; fi
    mkdir -p "$destination"
    ln -sf "$JsonPath" "$destination/$HostName.json"
    echo -e "\e[32mRegistered in: $destination\e[0m"
}

unregister_host() {
    local destination=$1
    if [ -z "$destination" ]; then return; fi
    if [ -f "$destination/$HostName.json" ]; then
        rm "$destination/$HostName.json"
        echo -e "\e[33mRemoved from: $destination\e[0m"
    else
        echo -e "\e[90mNot found in: $destination\e[0m"
    fi
}

if [ "$browserOption" == "6" ]; then
    for p in "${paths[@]}"; do
        [ "$action" == "1" ] && register_host "$p"
        [ "$action" == "2" ] && unregister_host "$p"
    done
else
    target="${paths[$browserOption]}"
    [ "$action" == "1" ] && register_host "$target"
    [ "$action" == "2" ] && unregister_host "$target"
fi

echo -e "\n\e[36mOperation completed. Please restart your browser.\e[0m"
