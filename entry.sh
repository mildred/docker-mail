#!/bin/bash

exim_replace_list(){
  local f=/var/mail/exim.user.conf
  local v=$1
  shift 1
  var="$v == $1"
  shift
  for e in "$@"; do
    var="$var : $e"
  done
  [ -s "$f" ] || echo >> "$f"
  ls -l $f
  sed -i -e "/^$v/ d" -e "$ a $var" "$f"
  #echo sed -i -e "/^$v/ d" -e "$ a $var" "$f"
  cat "$f"
}

(
  cd /var/mail
  if ! [ -e /var/mail/ssl.cfg ]; then
    cat >/var/mail/ssl.cfg <<EOF
[ req ]
distinguished_name = req_distinguished_name
prompt             = no
EOF
  fi
  if ! [ /var/mail/ssl.csr -nt /var/mail/ssl.cfg ] || ! [ -e /var/mail/ssl.key ]; then
    openssl req -config /var/mail/ssl.cfg -new -newkey rsa:2048 -nodes \
      -keyout /var/mail/ssl.key -out /var/mail/ssl.csr
  fi
  if ! [ -e /var/mail/ssl.crt ]; then
    openssl x509 -req -days 3650 -in /var/mail/ssl.csr -signkey /var/mail/ssl.key -out /var/mail/ssl.crt
  fi
  chown root:ssl /var/mail/ssl.key /var/mail/ssl.csr /var/mail/ssl.crt
  chmod g+r /var/mail/ssl.key
)

case "$1" in
  info)
    echo "$(wc -l /var/mail/users | cut -d' ' -f1) users in database"
    echo "SMTP configuration:"
    sed "s/^/    /" /var/mail/exim.user.conf
    ;;
  domain|domains)
    local=$(grep LOCAL_DOMAINS /var/mail/exim.user.conf | cut -d= -f2 | tr -d ':')
    relay=$(grep RELAY_DOMAINS /var/mail/exim.user.conf | cut -d= -f2 | tr -d ':')
    case "$2" in
      local)
        case "$3" in
          add)
            domain="$4"
            if [ -z "$domain" ]; then
              echo -n "Domain: "
              read domain
            fi
            local="$local $domain"
            exim_replace_list LOCAL_DOMAINS $local
            ;;
          *)
            echo $local
            ;;
        esac
        ;;
      relay)
        case "$3" in
          add)
            domain="$4"
            if [ -z "$domain" ]; then
              echo -n "Domain: "
              read domain
            fi
            relay="$relay $domain"
            exim_replace_list RELAY_DOMAINS $relay
            ;;
          *)
            echo $relay
            ;;
        esac
        ;;
      *)
        echo "Local domains: $local"
        echo "Relay domains: $relay"
        ;;
    esac
  ;;
  user|users)
    case "$2" in
      add)
        user="$3"
        pass="$4"
        if [ -z "$user" ]; then
          echo -n "User E-Mail: "
          read user
        fi
        if [ -z "$pass" ]; then
          if ! pass="$(doveadm pw -s SHA512-CRYPT)"; then
            exit 1
          fi
        fi
        if grep -G "^$user:" /var/mail/users; then
          echo "User $user already exists"
          exit 1
        fi
        echo "$user:$pass:vmail:vmail::/var/mail/home/${user%@*}::" >> /var/mail/users
        ;;
      add-alias)
        alias="$3"
        user="$4"
        if [ -z "$alias" ]; then
          echo -n "Alias E-Mail: "
          read alias
        fi
        if [ -z "$user" ]; then
          echo -n "User E-Mail: "
          read user
        fi
        if grep -G "^$alias:" /var/mail/users; then
          echo "User $alias already exists"
          exit 1
        fi
        pass="$(grep -G "^$user:" /var/mail/users | cut -d':' -f2)"
        echo "$alias:$pass:vmail:vmail::/var/mail/home/${user%@*}::" >> /var/mail/users
        ;;
      *)
        cat /var/mail/users
        ;;
      esac
    ;;
  bash)
    exec bash
    ;;
  init)
    # FIXME: generate certificates in docker VOLUME
    exec /usr/bin/svscanboot
    ;;
  *)
    echo "docker run --rm --volumes-from=CONTAINER -i -t IMAGE ..."
    echo "... info"
    echo "... domain|domains local|relay"
    echo "... domain|domains local|relay add [DOMAIN]"
    echo "... user|users"
    echo "... user|users add       [EMAIL@HOST [CRYPTED_PASSWORD]]"
    echo "... user|users add-alias [ALIAS@HOST [EMAIL@HOST]]"
    echo "... bash"
    echo "docker run -i -t IMAGE ..."
    echo "... init"
    exit 1
    ;;
esac
