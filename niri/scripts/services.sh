#!/bin/bash
awww-daemon &
elephant &
walker --gapplication-service &
until awww query 2>/dev/null; do sleep 0.2; done
awww img ~/.config/oxidize/themes/background --transition-type=none
