#/bin/sh

# Intialized writefreely as a single user blog and setup DB
alias writefreely='/go/cmd/writefreely/writefreely'

# Must use an config.ini where the database file ins't in a folder
# other wise writefreely db init does not initialize the sqliteDB
cat << EOF
[server]
port                 = 8080
bind                 = localhost

[database]
type     = sqlite3
filename = writefreely.db
EOF > /go/config.ini

# Initialize the DB and create the admin user
if [[ ! -f /go/data/writefreely.db ]]; then
  writefreely db init
  writefreely user create --admin "${WF_ADMIN_USER}:${WF_ADMIN_PASSWORD}"
  cp ./writefreely.db ./data/writefreely.db
else
  echo "DB already initialized"
fi

# Generate encryption keys if it doesn't exist yet
if [[ ! -f /go/keys/email.aes256 ]]; then
  writefreely keys generate
else
  echo "Keys already generated"
fi


# Switch to using the actual config.ini to start the app
rm -f /go/config.ini
eval "cat << EOF
$(cat template.ini)
EOF" > /go/config.ini

writefreely serve
