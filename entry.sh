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
  if ! [ -e ./ssl.cfg ]; then
    cat >./ssl.cfg <<EOF
[ req ]
prompt             = no
default_bits       = 2048
distinguished_name = req_distinguished_name

[ req_distinguished_name ]
CN = *
EOF
    [ -e ./ssl.key ] && touch -r ssl.key ssl.cfg
  fi
  if [ ./ssl.cfg -nt ./ssl.key ] || ! [ -e ./ssl.key ]; then
    echo "Generating private key and certificate request"
    openssl req -config ./ssl.cfg -new -nodes \
      -keyout ./ssl.key -out ./ssl.csr
  fi
  if ! [ -e ./ssl.crt ]; then
    echo "Generating self-signed certificate"
    openssl x509 -req -days 3650 -in ./ssl.csr -signkey ./ssl.key -out ./ssl.crt
    echo "SSL certificate $(openssl x509 -in ./ssl.crt -noout -fingerprint)"
  fi
  chown root:ssl ./ssl.key ./ssl.csr ./ssl.crt
  chmod g+r ./ssl.key
  [ -e exim.user.conf ]    || touch exim.user.conf
  [ -e dovecot.user.conf ] || touch dovecot.user.conf
  [ -e users ]             || touch users
)

die(){
  echo "$@" >&2
  exit 1
}

setup(){
  local local=$(grep LOCAL_DOMAINS /var/mail/exim.user.conf 2>/dev/null | cut -d= -f3 | tr -d ': ')
  local relay=$(grep RELAY_DOMAINS /var/mail/exim.user.conf 2>/dev/null | cut -d= -f3 | tr -d ': ')
  if [ -n "$LOCAL_DOMAINS" ]; then
    [ -n "$local" ] && die "Cannot overwrite LOCAL_DOMAINS ($local) with environment variable (LOCAL_DOMAINS=$LOCAL_DOMAINS)"
    exim_replace_list LOCAL_DOMAINS $LOCAL_DOMAINS
  fi
  if [ -n "$RELAY_DOMAINS" ]; then
    [ -n "$relay" ] && die "Cannot overwrite RELAY_DOMAINS ($relay) with environment variable (RELAY_DOMAINS=$RELAY_DOMAINS)"
    exim_replace_list LOCAL_DOMAINS $RELAY_DOMAINS
  fi
}

case "${1:=init}" in
  info)
    echo "$(wc -l /var/mail/users | cut -d' ' -f1) users in database"
    echo "SMTP configuration:"
    sed "s/^/    /" /var/mail/exim.user.conf
    ;;
  domain|domains)
    local=$(grep LOCAL_DOMAINS /var/mail/exim.user.conf 2>/dev/null | cut -d= -f3 | tr -d ':')
    relay=$(grep RELAY_DOMAINS /var/mail/exim.user.conf 2>/dev/null | cut -d= -f3 | tr -d ':')
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
    if ! tty >/dev/null 2>&1; then
      echo "Must be run with -t (--tty) option"
      exit 1
    fi
    setup
    exec bash
    ;;
  init)
    setup
    exec /usr/bin/svscanboot
    ;;
  debug)
    if ! tty >/dev/null 2>&1; then
      echo "Must be run with -t (--tty) option"
      exit 1
    fi

    exim_replace_list LOCAL_DOMAINS test
    echo "test@test:$(printf 'test\ntest\n' | doveadm pw -s SHA512-CRYPT):vmail:vmail::/var/mail/home/test::" >/var/mail/users
    setup
    
    /usr/bin/svscanboot &
    sleep 1
    tail -F /var/log/dovecot/current /var/log/exim/current
    
    echo "Local domain added: test"
    echo "User test@test created with password test"
    echo "AUTH PLAIN $(printf "\0%s\0%s" test@test test | base64)"
    echo "tail -F /var/log/dovecot/current /var/log/exim/current"

    exec bash
    ;;
  *)
    echo "export LOCAL_DOMAINS=..."
    echo "export RELAY_DOMAINS=..."
    echo "docker run --rm --volumes-from=CONTAINER -i -t IMAGE ..."
    echo "... info"
    echo "... domain|domains local|relay"
    echo "... domain|domains local|relay add [DOMAIN]"
    echo "... user|users"
    echo "... user|users add       [EMAIL@HOST [CRYPTED_PASSWORD]]"
    echo "... user|users add-alias [ALIAS@HOST [EMAIL@HOST]]"
    echo "... bash"
    echo "docker run -d -p 4190:4190 -p 993:993 -p 143:143 -p 25:25 -p 465:465 -p 587:587 IMAGE"
    echo "... init"
    exit 1
    ;;
esac
