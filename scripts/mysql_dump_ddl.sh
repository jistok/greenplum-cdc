#!/bin/bash

user="root"
pass="music"
#user="music"
#pass="music"
db="music"
host="localhost"

# NOTES:
# - Column names will be double quoted
# - Some types might not match; e.g. "INT(11)" will have to become "INT"

#mysqldump -d -u $user -p$pass -h $host $db
#mysqldump --compatible=postgresql --default-character-set=utf8 -d -u $user -p$pass -h $host $db
mysqldump --compatible=postgresql --default-character-set=utf8 -d -u $user -p -h $host $db
#mysqldump --compatible=postgresql --default-character-set=utf8 -d -u $user -p -h $host --all-databases

