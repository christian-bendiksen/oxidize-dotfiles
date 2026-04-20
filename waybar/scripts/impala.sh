#!/usr/bin/env bash
exec xdg-terminal-exec bash -c 'printf "\033]0;Impala\007"; exec impala'
