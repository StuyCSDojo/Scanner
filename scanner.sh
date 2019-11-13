#!/bin/bash

# ANSI Escape Codes
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
MAGENTA="$(tput setaf 5)"
RESET="$(tput setaf 7)"

# First pull the git repo
echo "Pulling repo..."
git pull
# If the pull failed for whatever reason, exit
if (( $? )); then echo "${RED}Failed to pull repo!${RESET}"; exit 1; fi

# Get some constants for the Date, Log Filename, and the length of a valid
# barcode
DATE=$(date +"%Y_%m_%d")
LOG=logs/${DATE}.csv
VALID_BARCODE_LENGTH=9

# Login variables
ADMIN_NAME=""
ADMIN_PWORD=""

SERVER_ADDR="http://162.243.115.175:11235"

#Scanner
strike=false
# Define a method to show a prompt
function show_prompt() {
    echo "============================="
    echo -n "Swipe card: "
}

# Sort list, removing duplicates in the process.
function cleanup() {
    echo "Cleaning up..."
    sort -u -o "$1" "$1"
}

# Add the log. Prompt user to commit and push repo
function push() {
    git add "${LOG}"
    # Read input from user and store in variable REPLY
    # First unset REPLY in case it was previously set
    unset REPLY
    # Use regex to check if REPLY is set to either 'y', 'n', 'Y', 'N', or a newline character
    # If not, prompt again until user gives valid input
    until [[ "$REPLY" =~ [ynYN$'\r'$'\n'] ]]; do
        # This reads in 1 character from stdin and stores it in variable REPLY
        read -r -N 1 -p "Push to github [Y/n]: "
        echo
    done
    # If the input was not no, push the repo
    if [[ ! "$REPLY" =~ [nN] ]]; then
        git commit -m "Added logs for ${DATE}"
        git push
    fi
}

function traphook() {
    cleanup "$LOG"
    push
}

# Add a shutdown hook so the log is cleaned when script exits
trap traphook EXIT

function login() {
    # Read login credentials and validate with server
    echo "Admin login:"
    if [[ $ADMIN_EMAIL == "" ]]; then
        echo -n "Username: "
        read -r name
        ADMIN_NAME=$name
    fi
    echo -n "Password: "
    read -r -s pass
    echo ""
    response=$(curl -# -X GET $SERVER_ADDR"?username=${ADMIN_NAME}&pword=${pass}")
    if [[ $response =~ "bad_login" ]]; then
        printf "%sERROR: Could not contact server%s\n" "${RED}" "${RESET}"
        exit
    elif [[ $response =~ "no_osis" ]]; then
        printf "%sValidation successful%s\n" "${GREEN}" "${RESET}"
        ADMIN_PWORD=$pass
    else
        # Print out error message
        local error=$(echo "$response" | grep 'title')
        echo "$error"
        #printf "%s${response}%s\n" "${RED}" "${RESET}"
        exit
    fi
}

function scan() {
    # Update log name if dates were overridden
    printf "%sEnter \"exit\" or \"quit\" to cleanup duplicates and exit%s\n" "${YELLOW}" "${RESET}"
    while true; do
        # Display the prompt
        show_prompt
        # Keep reading a barcode from stdin
        read -r barcode
        # The conditionals should be self explanatory
        if [[ $barcode == "exit" || $barcode == "quit" ]]; then
            exit
        elif [[ $barcode == "help" ]]; then
            helpMenu
        elif [[ $barcode == "strike add" ]]; then
            printf "%sADDING STRIKES ====================================%s\n" "${GREEN}" "${RESET}"
            strike=1
        elif [[ $barcode == "strike subtract" ]]; then
            printf "%sSUBTRACTING STRIKES ====================================%s\n" "${GREEN}" "${RESET}"
            strike=2
        elif [[ $barcode == "strike off" ]]; then
            printf "%sSTRIKE SYSTEM OFF ====================================%s\n" "${GREEN}" "${RESET}"
            strike=0
        elif [[ ${#barcode} != "$VALID_BARCODE_LENGTH" ]]; then
            # tput bel 'displays' the ASCII bell character, which invokes a
            # sound
            tput bel
            printf "%sERROR: Invalid barcode%s\n" "${RED}" "${RESET}"
        elif echo "$barcode" | grep "[^0-9]\+" > /dev/null; then
            tput bel
            printf "%sERROR: Invalid barcode%s\n" "${RED}" "${RESET}"
        elif [[ $strike == 1 ]]; then
            printf "%sStrike added to %s%s\n" "${GREEN}" "${barcode}" "${RESET}"
            python2 strike.py 1 "$barcode"
            python2 strike_print.py "$barcode"
        elif [[ $strike == 2 ]]; then
            printf "%sStrike subtracted from %s%s\n" "${GREEN}" "${barcode}" "${RESET}"
            python2 strike.py -1 "$barcode"
            python2 strike_print.py "$barcode"
        else
            # Create the log file if it doesn't exist yet.
            if [[ ! -f $LOG ]]; then
                touch "$LOG"
            fi
            # Only send barcodes that haven't been logged yet
            if [[ $(grep "$barcode" "$LOG") == ""  ]]; then
                printf "%sGot barcode: %s%s\n" "${GREEN}" "${barcode}" "${RESET}"
                python2 strike_print.py "$barcode"
                # Append barcode to log
                echo "$barcode, $(date +'%H:%M:%S')" >> "$LOG"
                # Curl the server
                # curl --silent -X GET "${SERVER_ADDR}?username=${ADMIN_NAME}&pword=${ADMIN_PWORD}&osis=${barcode}&date=${DATE}" > /dev/null&
            else
                printf "%sYou already scanned in%s\n" "${YELLOW}" "${RESET}"
                python2 strike_print.py "$barcode"
            fi
        fi
    done
}

function helpMenu(){
    printf "%sHELP MENU ============================================================================================================%s\n" "${GREEN}" "${RESET}"
    printf "%sstrike add%s\t\t---\t\tone strike will be added to any ID scanned after \"strike on\" is entered%s\n" "${YELLOW}" "${MAGENTA}" "${RESET}"
    printf "%sstrike subtract%s\t\t---\t\tone strike will be subtracted to any ID scanned after \"strike on\" is entered%s\n" "${YELLOW}" "${MAGENTA}" "${RESET}"
    printf "%sstrike off%s\t\t---\t\t\"strike add\" or \"strike subtract\" will stop running%s\n" "${YELLOW}" "${MAGENTA}" "${RESET}"
    printf "%sexit/quit%s\t\t---\t\tcleanup duplicates and exit%s\n"  "${YELLOW}" "${MAGENTA}" "${RESET}"
    printf "%shelp%s\t\t\t---\t\tdisplay the help menu%s\n"  "${YELLOW}" "${MAGENTA}" "${RESET}"
    printf "%s======================================================================================================================%s\n\n" "${GREEN}" "${RESET}"
}
# function custom_upload() {
#     curl --silent -X GET "${SERVER_ADDR}?username=${ADMIN_NAME}&pword=${ADMIN_PWORD}&osis=$2&date=$1" > /dev/null
# }

# function dump_csv() {
#     while IFS= read -r num; do
#         custom_upload "${1%%.*}" "$num"
#     done < "$1"
# }

# Admin Login
#login
# Invoke the scan function
helpMenu
scan
