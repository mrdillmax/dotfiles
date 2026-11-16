#!/bin/sh
if [ "$(dunstctl is-paused)" = "true" ]; then
  echo '{"text":"󰂛","class":"paused","tooltip":"Сповіщення вимкнено"}'
else
  echo '{"text":"󰂚","class":"active","tooltip":"Сповіщення увімкнено"}'
fi
