#!/usr/bin/env bash
[[ $UID -ne 0 ]] && exec sudo "$0" "$@"
die() { echo "$*" 1>&2 ; exit 1; }

defaults="${BKIT_DEFAULTS:-/etc/bkit/defaults}"

source "$defaults" || die "Can't source '$defaults'"

[[ ${BKIT_API_CONFDIR+isset} == isset ]] || die "BKIT_API_CONFDIR is not set"

pushd "$(dirname "$0")" >/dev/null

secret="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32})"

read -p "Administrator name (Default: $BKIT_API_ADMIN): " admin
admin=${admin:-$BKIT_API_ADMIN}

read -p "$admin password: " -s pass
echo
[[ -z $pass ]] && die "The password must be set"

read -p "Alerts dir (Default: alerts)" alerts
alerts=${alerts:-alerts}

clients="$BKIT_CLIENTS"

[[ -d $clients ]] && while true
do
    read -p "I found bkit clients area at '$clients'. Is this correct [Y/n]?" yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) unset clients && break;;
        * ) echo "Assume Yes by default!" && break;;
    esac
done

until test -d "$clients"
do 
  read -p "Where is the clients area? Please give a fullpath: " -r clients
done

read -p "Databases (Default: $BKIT_API_DB)" db
db=${db:-$BKIT_API_DB}

read -p "Logs (Default: $BKIT_API_LOGS)" log
log=${log:-$BKIT_API_LOGS}

mimetypes=$(find . -type f -name 'mimetypes.json' -prune -print -quit)
[[ -f $mimetypes ]] && read -p "I found mimetypes at $mimetypes. Is this correct [Y/n/ignore]?" yni &&
  case $yni in
      [Yy]* ) ;;
      [Nn]* ) mimetypes="";;
      [Ii]* ) unset mimetypes;;
      * ) echo "Assume Yes by default!";;
  esac

[[ -z ${mimetypes+x} ]] || until test -f "$mimetypes"
do
  read -p "Give the path to a mimetypes.json file (blank => ignore): " -r mimetypes
  [[ -z $mimetypes ]] && echo Dont use mimetypes && break
done

[[ -d "$BKIT_API_CONFDIR" ]] || mkdir -pv "$BKIT_API_CONFDIR"

[[ -e $mimetypes ]] && rsync "$mimetypes" $BKIT_API_CONFDIR/mimetypes.json && mimetypes="$BKIT_API_CONFDIR/mimetypes.json"
 

confile="$BKIT_API_CONFDIR/bkit.conf"

touch "$confile" && chmod 600 "$confile"

cat >"$confile" <<EOT
{
  Title => "bKit App",
  secret => '$secret',
  admin => {
    name => '$admin',
    pass => '$pass'
  },
  alerts => app->home->child('$alerts'),
  clients => '$clients',
  log => '$log',
  DB => '$db',
  ${mimetypes:+"mimetypes => '$mimetypes',"}
  hypnotoad => {
    listen  => ['http://*:$BKIT_API_PORT'],
    pid_file => '$BKIT_API_PID',
    workers => 3,
    spare => 3
  }
}
EOT

chmod 400 "$confile"
chown rsyncd:rsyncd "$confile"
[[ -d "$db" ]] || mkdir -pv "$db"
[[ -d "$log" ]] || mkdir -pv "$log"
chmod 750 "$db"
chmod 755 "$log"
chown -R rsyncd:rsyncd "$db" "$log" "$BKIT_API_CONFDIR"

popd >> /dev/null
