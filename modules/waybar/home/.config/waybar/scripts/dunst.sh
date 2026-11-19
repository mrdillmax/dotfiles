#!/bin/sh
if [ "$(dunstctl is-paused)" = "true" ]; then
  echo '{"text":"󰂛","class":"paused","tooltip":"Notifications paused"}'
else
  echo '{"text":"󰂚","class":"active","tooltip":"Notifications active"}'
fi
