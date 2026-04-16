#!/bin/sh
action=$1

. /lib/functions/gl_util.sh

if [ "$action" = "on" ];then
    echo "on" > /tmp/sim_change_switch
    flock -n /tmp/red-merle-switch.lock  timeout 90  /usr/bin/red-merle-switch-stage1

elif [ "$action" = "off" ];then
    if [ -f /tmp/red-merle-stage1 ]; then
        flock -n /tmp/red-merle-switch.lock  timeout 90  /usr/bin/red-merle-switch-stage2
    fi
    echo "off" > /tmp/sim_change_switch

else
    echo "off" > /tmp/sim_change_switch
fi
sleep 1
