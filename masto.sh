#!/bin/bash

# Everything we need to initialize our database with 
initialize() {
    local database="$1"

    # Check if the database name is provided
    if [ -z "$database" ]; then
        echo "Error: Database name not provided."
        echo "Usage: $0 init|update <database_name>"
        exit 1
    fi

    # Check if database file already exists, if it does, exit the script
    if [[ -f "${database}" ]]; then
        echo "Error: '${database}' already exists."
        exit 1
    fi

    # Prompt for "instance"
    while [[ -z "$instance" ]]; do
        read -rp "Enter the instance name: " instance
    done

    # Prompt for "access_token"
    while [[ -z "$access_token" ]]; do
        read -rp "Enter the access token: " access_token
    done

    # Perform a curl request to verify the credentials using our access_token
    response=$(curl -s -X GET -H "Authorization: Bearer ${access_token}" "https://${instance}/api/v1/accounts/verify_credentials")

    # Check if the curl command failed in any way
    if [[ $? -ne 0 ]]; then
        echo "Error: Could not verify credentials. Check if you provided the correct instance name and that your access token is set up."
        exit 1
    fi

    # The response contains an "id" field that represents the account_id. Extract it and put it into "account_id"
    account_id=$(echo "$response" | jq -r '.id')

    if [[ -z "$account_id" || ! "$account_id" =~ ^[0-9]+$ ]]; then
        echo "Error: Failed to extract account ID from the JSON response"
        exit 1
    fi

    # Set up the "config" table in our database
    duckdb "${database}" -c "
        CREATE TABLE IF NOT EXISTS config (
            id VARCHAR,
            value VARCHAR
        );
        INSERT INTO config (id, value)
        VALUES
            ('instance', '${instance}'),
            ('access_token', '${access_token}'),
            ('account_id', '${account_id}')
    "

    if [[ $? -eq 0 ]]; then
        echo "Database was set up successfully for account-id [$account_id]"
    else
        echo "Error: Failed to insert values into the 'config' table."
        exit 1
    fi
}


# Everything we need to query the Mastodon API and get our posts
update() {
    local database="$1"
    local force_refresh="$2"

    # Check if the database name was provided
    if [ -z "$database" ]; then
        echo "Error: No database name provided."
        echo "Usage: $0 init|update <database_name>"
        exit 1
    fi

    # Check if the database file actually exists
    if [ ! -f "${database}" ]; then
        echo "Error: Database '${database}' does not exist."
        exit 1
    fi
    
    # If necessary create a posts table to hold the information on our posts
    duckdb "${database}" -c "
        CREATE TABLE IF NOT EXISTS posts (
            id BIGINT PRIMARY KEY,
            content VARCHAR,
            replies_count BIGINT,
            reblogs_count BIGINT,
            favourites_count BIGINT,
            created_at VARCHAR
        );
    "

    # Get the configuration from the config table ... TODO: This feels a bit lazy 
    instance=`duckdb ${database} -noheader -csv -c "select value from config where id='instance'"`
    access_token=`duckdb ${database} -noheader -csv -c "select value from config where id='access_token'"`
    account_id=`duckdb ${database} -noheader -csv -c "select value from config where id='account_id'"`
    api_endpoint="https://$instance/api/v1/accounts/${account_id}/statuses"
    min_id=$(duckdb ${database} -noheader -csv -c "select coalesce(max(id), 0) from posts;")

    # If we started with "force refresh" then forget about the min_id and start from 0 instead
    if [ "$force_refresh" = true ]; then
        min_id=0
    fi

    spinner="/-\\|"
    count=0

    while true; do
        # Show a funny little spinner and status of the last min_id
        printf "\r%c [current id: %s]" "${spinner:count++%${#spinner}:1}" "$min_id"

        # Perform API call
        response=$(curl -s -X GET -H "Authorization: Bearer ${access_token}" "${api_endpoint}?min_id=${min_id}&limit=40")
        if [[ "$response" == "[]" ]]; then
            break;
        fi

        # Extract all required information from the JSON response by creating a new JSON using jq
        statuses=$(jq -r '.[] | {id: .id, content: .content, replies_count: .replies_count, reblogs_count: .reblogs_count, favourites_count: .favourites_count, created_at: .created_at}' <<< "$response")

        # Auto-read the new JSON from stdin and insert it into the posts table
        duckdb ${database} -c "
            insert or replace into posts 
                SELECT id, 
                    content, 
                    replies_count, 
                    reblogs_count, 
                    favourites_count, 
                    created_at 
                FROM read_json_auto('/dev/stdin');
        " <<< $statuses

        # Set the min_in to the last processed response id and start over
        min_id=$(jq -r '[.[] | .id] | max' <<< "$response")
    done    

}

# This script requires curl, duckdb and jq installed. Check if they are available
if ! command -v curl &> /dev/null; then
    echo "curl is not installed or not found in the PATH."
    exit 1
fi

if ! command -v duckdb &> /dev/null; then
    echo "duckdb is not installed or not found in the PATH."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "jq is not installed or not found in the PATH."
    exit 1
fi

# Check the input argument and call respective functions
case "$1" in
    "init")
        database_name="$2"
        initialize "$2"
        ;;
    "update")
        database_name="$2"
        force_refresh=false

        # Check if the flag "-forceRefresh" is provided
        if [[ "$3" == "-forceRefresh" ]]; then
            force_refresh=true
        fi

        update "$database_name" "$force_refresh"
        ;;
    *)
        echo "Usage: $0 [init|update] <database_name>"
        ;;
esac

exit 0
