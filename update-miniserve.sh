#!/usr/bin/env bash

# Get the latest release version from the GitHub API
VERSION=$(curl --silent "https://api.github.com/repos/svenstaro/miniserve/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

# Remove the 'v' prefix from the version number
FILE_VERSION=${VERSION#v}

# Notify the user which version is being downloaded
echo "Downloading miniserve version ${VERSION}..."

# Define the URL of the latest release
URL="https://github.com/svenstaro/miniserve/releases/download/${VERSION}/miniserve-${FILE_VERSION}-x86_64-unknown-linux-gnu"

# Download the file
wget $URL

# Rename the downloaded file to miniserve
mv miniserve-${FILE_VERSION}-x86_64-unknown-linux-gnu miniserve
