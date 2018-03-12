#!/bin/bash

PATH=/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin

# periodically checks /home/user/switcheroo.txt for changes
# and uses display-settings to switch to the other graphics card,
# first allowing for safe termination of the user's session.
# NOTE: should be run as root inside a screen or by graphics-switch-daemon
# from init.d.

# vgaswitcheroo location.
switcheroo=/proc/acpi/bbswitch
# Wait for termination of this before acting.
SESSION="/usr/bin/gnome-shell gnome-session"
# How often to check for switcheroo.txt changes.
INTERVAL=60

dm=$( cat  /etc/X11/default-display-manager )
dm=$( basename "$dm" )

function switch {
    if [ -f /etc/init.d/gdm3 ]; then
        /etc/init.d/gdm3 stop
    else
        /etc/init.d/gdm stop
    fi
    if [ -f /etc/init.d/"$dm" ]
    then
      /etc/init.d/"$dm" stop
    fi

    sleep 1
    /etc/init.d/display-settings autodetect
    sleep 1
    if [ -f /etc/init.d/gdm3 ]; then
        /etc/init.d/gdm3 start
    else
        /etc/init.d/gdm start
    fi

    if [ -f /etc/init.d/"$dm" ]
    then
      /etc/init.d/"$dm" start
    fi
}

function read_switcheroo {
    if [ -n "${target}" ]; then
        old=${target}
    fi
    target=$( cat /opt/switcheroo.txt )
    if [ -n "${old}" -a "${target}" != "${old}" ]; then
        changed=true
    else
        unset changed
    fi
    # Now, if the target is different than what the switch file says
    if [ -f "${switcheroo}" ]
    then
      isIntel=$( cat "${switcheroo}" | grep "OFF" )
    else
      unset changed
      return
    fi
    # only switch if not on intel yet
    if [ "${target}" == "intel" -a -z "${isIntel}" ]; then
      changed=true
    else
	# either already intel, or nvidia wanted
	# only switch if not on nvidia (i.e. on intel)
	if [ "${target}" == "nvidia" -a -n "${isIntel}" ]; then
          changed=true
	else
           unset changed
        fi
    fi
}

function notify_user {
    env DISPLAY=:0 notify-send "Scheduled switch to ${target}" \
    "Switch will be performed after your session is closed" \
    -i system-log-out
}

function checkx {
  xrunning=""
  for k in $SESSION
  do
    if [ -z "$xrunning" ]
    then
      xrunning=$( ps -ef | awk -v SESSION="$k" '$0 !~ "LoginWindow" { if ( $8 == SESSION ) print $8}' )
      #echo "xrunning=$xrunning"
    fi
  done
}

function stuff {
    #echo "user=$U interval=$INTERVAL session=$SESSION"

    # Actions
    while true; do
        read_switcheroo
        echo "target=$target changed=$changed old=$old"
        if [ -z "${changed}" ]; then
            sleep ${INTERVAL}
            continue;
        fi
        echo "changed=$changed isIntel=${isIntel} old=$old target=$target"
        # changed
        notify_user
        checkx
        while [ -n "${xrunning}" ]; do
            sleep ${INTERVAL}
            checkx
        done
        # User session has been closed, switch now
        switch "${target}"
        sleep ${INTERVAL}
        # So we do not switch again too soon in case of errors
    done
}

# Do stuff!
if [ "$1" != "DEBUG" ]
then
  if [ "$1" == "firsttime" ]
  then
    stuff firsttime
  else
    stuff
  fi
fi

