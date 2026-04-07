#!/usr/bin/env bash
kitty -e bash -c 'echo -ne "\033]0;Impala\007"; exec impala'
