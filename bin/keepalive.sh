#!/bin/bash
while true; do
    ps -o pid,comm --no-headers -p $$ > /dev/null
    sleep 300
done
