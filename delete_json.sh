#! /bin/bash
dir=$1
read -p "Delete all .json files in '$dir'? (y/N): " answer
[ "$answer" = "y" ] && rm -v "$1"/*.json || echo "Canceled."
