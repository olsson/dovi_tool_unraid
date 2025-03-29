#!/bin/sh

# Set up DNS configuration
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf

# Run the main entrypoint script
exec /usr/local/bin/entrypoint.sh "$@" 