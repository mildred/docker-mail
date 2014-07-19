FROM debian:stable
MAINTAINER mildred

RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y daemontools
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y dovecot-core dovecot-imapd dovecot-lmtpd dovecot-managesieved dovecot-sieve
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y exim4 exim4-daemon-heavy
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y daemontools-run
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y acl

VOLUME /var/mail
VOLUME /var/log/exim
VOLUME /var/log/dovecot
WORKDIR /

RUN { \
  ln -s /var/mail/users /etc/dovecot/users; \
  setfacl -m u:Debian-exim:r /etc/dovecot/private/dovecot.pem /etc/dovecot/dovecot.pem; \
  }

COPY dovecot-local.conf /etc/dovecot/local.conf
COPY dovecot.service    /etc/service/dovecot
COPY exim.service       /etc/service/exim
COPY exim.conf          /etc/exim/exim.conf
COPY entry.sh           /entry.sh

# sieve=4190 imaps=993 imap2=143 smtp=25 smtps=465 submission=587
EXPOSE 4190 993 143 25 465 587

ENTRYPOINT ["/bin/bash", "/entry.sh"]

