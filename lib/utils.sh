#!/bin/bash

## Colors
NO_COLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BROWN='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHT_GRAY='\033[0;37m'

# display function echo the text with the desired color.
# 
# Arguments:
#   - First is the color
#   - Second and so on is the text that you want to display
function display {
  if [[ $# -lt 2 ]]; then return 0; fi
  color=$1
  text=${@:2}

  echo -e "${color}${text}${NO_COLOR}"
}

# is_number function checks is the string is a number or not(limited to one character and not 0)
# Negative numbers are not allowed
#
# Arguments:
#   The first and only argument is the string to be checked
function is_number {
  if [[ $# -ne 1 ]]; then return 1; fi
  [[ "$1" =~ ^[1-9]+$ ]]
}

# is_ipv4_address checks if the string is an IPv4 address or not. It just checks if the string contains 4 points and a maximum of 3 numbers
# between each point
#
# Arguments:
#   The first and only argument is the string to be checked
function is_ipv4_address {
  if [[ $# -ne 1 ]]; then return 1; fi
  [[ "$1" =~ ^([1-2]?[0-9]{1,2}\.){3}[1-2]?[0-9]{1,2}$ ]]
}

# is_ipv4_name checks if the ip address is a real name
function is_ipv4_name {
  if [[ $# -ne 1 ]]; then return 1; fi
  addr=$1
  [[ $(ip -4 addr show | grep -E "^[0-9]+" | awk -F':' '{ print $2; }' | cut -d' ' -f2 | grep -c "$addr") -eq 1 ]]
}

# ssh_exec executes a command or a couple of them in a remote host
function ssh_exec {
  if [[ $# -lt 2 ]]; then return 1; fi
  address=$1
  shift
  args=$@

  ssh $address $args
}
