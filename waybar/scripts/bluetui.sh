#!/usr/bin/env bash
exec xdg-terminal-exec bash -c 'printf "\033]0;Bluetui\007"; exec bluetui'
