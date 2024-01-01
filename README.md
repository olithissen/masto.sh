# masto.sh
A bash script to download your Mastodon posts to DuckDB

## Installation

* Clone this repository or copy the contents of `masto.sh`
* Make the script executable: `chmod +x masto.sh`

## Requirements

### Software

* curl
* jq
* [DuckDB](https://duckdb.org/)

### Mastodon API access

* Go to your Mastodon accounts developer settings (i.e. https://mastodon.social/settings/applications)
* Set up a new application
* Make sure that at least `read:accounts` and `read:statuses` are set
* Save your changes and copy the generated `access token`

## Usage

### Initial setup

* Initialize a new database

```bash
./masto.sh init myposts.db
```
* Provide your instance name, i.e. `mastodon.social` or `social.tchncs.de`
* Provide the `access token` you copied earlier

If everything worked, the script will tell you that the database was created successfully for your account.

### Load posts

```bash
./masto.sh update myposts.db
```

This will connect to the Mastodon API and start pulling your posts beginning with the lowest id.
Every consecutive execution of `masto.sh` will start from the last processed id.
This might take a while as the API only returns 40 posts on each call.

If you don't want to add posts incrementally but instead want to start over again, you can force a refresh:

```bash
./masto.sh update myposts.db -forceRefresh
```

## And now what?

Now you can perform all sorts of funny SQL on it using DuckDB!

```bash
duckdb myposts.db -c "<sql>"
```

**What fields are available?**
```sql
DESCRIBE posts;
```

**Count all favs?**
```sql
select sum(favourites_count) from posts;
```
## Known problems

* Reposts are not filtered and are just database rows with no content ...
* I think there is something off with `created_at` regarding the timezone.
