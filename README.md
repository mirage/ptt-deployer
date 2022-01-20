# [PTT][ptt] deployer

This repository contains the skeleton to deploy our SMTP stack. The goal of it
is to provide:
- a SMTP submission service
- a SMTP relay which transfer incoming emails to the true destination

By this way, we provide a full SMTP service where users are able:
- to send an email under an authority (a corporation, a simple domain-name)
- to receive emails from others _via_ this authority

Multiple mechanisms exists under our service:
- the deployement is automatic
  * our deployer launch the service from sources. So it fetches and compiles
    unikernels according to their last version.
  * our deployer watches its repository and as soon as it notifies a change,
    it redeploy the service
  * while our deployer recompile unikernels, we keep active the old version
    of the SMTP service to avoid a down time. When the new version of the
    SMTP is ready, we redirect users to the new service and delete the old
    version one
  * then, the deployment is done by [albatross][albatross] which lets you to
    introspect the _state_ of your unikernels (logs, metrics, etc.)
- we require [KVM][kvm] to virtualize our unikernels
  * by this way, we ensure to restrict the attack surface
  * a unikernel does one job and by this way, some of them don't require all
    information such as users and passwords
  * a unikernel implement only one service - so it exists only one way
    to communicate with it - which restricts side-channel attacks
  * KVM containerizes our unikernels - they communicate together _via_
    expected (and secure) protocols. They does not share anything each other.
- our SMTP service does not require an external resources
  * about storage, we require a Git repository to store users and passwords.
    This one can exists locally into the physical server (or elsewhere)
  * about DNS requests, we use our own DNS resolver. We don't require a service
    such as the Google DNS resolver (8.8.8.8) or the CloudFare DNS resolver
    (1.1.1.1). We trust only on _root_ DNS servers
- we don't store somewhere private information such as incoming emails to
  submit under our authority. Our design just prepend incoming emails with
  some _meta_-information and retransfer it then to the real destination
  * only the user and the password is kept into our service
  * unikernels don't have access to a file-system and they are not able
    to store anything into the server
- communication between unikernels use systematically TLS (_via_ the STARTTLS
  option)
  * for the submission, the SMTP unikernel will ask under your domain,
    a [Let's encrypt][letsencrypt] certificate which is trusted by any users
  * between _internal_ unikernels, we generate _in the fly_ certificates
    and ensure an agreement between them about what certificate is expected
    on one side and what certificate is generated on the other side
  * the synchronization with the Git repository is done _via_ SSH
  * the relay prioritize the STARTTLS communication with external SMTP
    services and an user can decide to not send an email if the destination
    does not provide a secure communication
- our submission service proposes two security things:
  * the [ptt][ptt] distribution comes with an `ptt.spf` tool which can upgrade
    your authority with your public IP address - and let, by this way,
    receivers to verify the origin of your outgoing emails
  * the deployer launches a DKIM signer which signs every incoming emails &
    retransmit them with the signature to a destination. By this way, every
    outgoing emails are signed and can be verified by receivers
- our relay service implements some mechanism to check incoming emails
  * we implemented a simple spam filter which annotes incoming emails if they
    are recognized as a spam or not and we retransfer them to the destination
  * we apply a DMARC verification to ensure the origin of the incoming email,
    if the given DKIM signature is right and if information are _aligned_ to
    the authority of the sender

The goal of PTT is to propose a full SMTP service, easy to deploy and secured.
We mostly want to improve the usage of emails which become more and more
important as a part of your identity on Internet. However, it can be difficult
to:
- deploy such service
- be aware about all security issues
- and verify if we deployed such service in the right way for others

## Development

`ptt-deployer` is a concentration of many pieces which is about the SMTP stack,
MirageOS and how we can deploy unikernels then. This is the exhaustive list of
all libraries used by SMTP stack and the deployer:
- [mrmime][mrmime] as the email analyzer
- [uspf][uspf] to verify the origin of incoming emails
- [ocaml-dkim][ocaml-dkim] to sign and verify emails
- [spamtacus][spamtacus] to filter emails as a spam or not
- [colombe][colombe] which is the implementation of the SMTP protocol
- [ocaml-dmarc][ocaml-dmarc] which verify incoming emails (SPF and DKIM)
- [ocaml-dns][ocaml-dns] which is our DNS implementation used everywhere
- [ptt][ptt] as the implementation of an SMTP server
- [ocurrent][ocurrent] as our Continuous Integration system
- [albatross][albatross] as our daemon to launch unikernels
- [current\_albatross\_deployer][] which synchronize Albatross and OCurrent
- [MirageOS][mirage] as the tool to build unikernels

## TODO

The SMTP service still is experimental and we want to go further about security
concers:
- [ ] our DNS resolver should use the DNSSEC mechanism to get DNS information
- [ ] we should use DNS over TLS between our SMTP relay and our DNS resolver
- [ ] `Return-Path:` is not yet implemented
- [ ] DMARC report is not yet implemented

## Deployment

PTT uses [MirageOS][mirage] to build _unikernels_. That mostly means that our
way to deploy the SMTP service is **not** the only way. For instance, these
unikernels can be deployed into Google Cloud, into some chipset like Raspberry
Pi 4 or, as we do, into an hypervizor such as [KVM][kvm] or [Xen][xen].

For instance, we can imagine that you already deployed many Raspberry Pi 4 and
each of them care about one unikernel. In that case, option needed by
unikernels will change.

Our deployment context requires:
- a bare-metal server with Debian 10
- the virtualization should be enabled (and you should have an access to
  `/dev/kvm`)

We don't require a huge server (many CPUs and huge amount of RAM). A unikernel
needs 64 MB of RAM and only one CPU. In the case of the virtualization, the
kernel is able to schedule unikernels if you have less CPUs than unikernels
launched.

For our example, we assume that you have this server on 147.75.X.Y and you
are the owner of a domain-name: `mirage.ptt`. On your side, you probably need
to add a _Glue record_ to your domain-name provider to give to it your public
address 147.75.X.Y. This is all what you need to deploy our SMTP service.

## Design of [PTT][ptt]

`ptt` consists into 8 unikernels:
1) a DNS primary service synchronized with a Git repository
   This unikernel is available here: [dns-primary-git][dns-primary-git] and
   used, for instance, for `mirage.io`. It will be your DNS primary service for
   your domain-name `mirage.ptt`. Indeed, SMTP must put some _meta_-information
   into your DNS zone file. Of course, you can use your own DNS primary
   service as long as it implements [`nsupdate`][nsupdate]. In our case, we
   will trust on our implementation of the DNS service.
2) a DNS resolver which trust only DNS roots
   SMTP requires a DNS service to solve destination of incoming emails. We
   can use the DNS service proposed by your provider but we prefer to keep
   the control of resources and provide by ourselves our DNS resolver
3) a DNS let's encrypt secondary to get Let's encrypt certificate
   Our submission service initiate a TLS connection and it require a TLS
   certificate. This service will be used by your user so we must have a
   certificate which is trusted by your user. In that case, we provide a
   DNS let's encrypt secondary which challenging Let's encrypt to make a TLS
   certificate for us under your domain-name. It's the same for our verifier
   which is behind `*:25`. It wants to implement STARTTLS.
4) The submission service
   It's a simple SMTP server which implements an authentication mechanism over
   TLS to let your user to send an email under your authority. It will be
   synchronize with a local Git repository which contains users and passwords
5) A DKIM signer
   This unikernel will be the only one to contain your private key to sign
   incoming emails. It will update your DNS primary service to contain the
   public key and let users to verify the signature added into incoming emails
6) The SMTP relay
   This unikernel is the only one which will send incoming emails to Internet.
   It require the DNS resolver to resolve destinations and it's the only one
   able to start a connection with external servers. It requires the store
   which contains users to find the real address of the destination if we want
   to send one of your available user who use `mirage.ptt` as an email address
7) The SMTP receiver
   If someone wants to send an email to `foo@mirage.ptt`, it will communicate
   with this service. This unikernel mostly want to check and verify
   information _via_ the DMARC mechanism (which does the SPF verification and
   the DKIM verification). Then, it stamps the incoming emails with the result
   of this verification and send back to the destination
8) The spam filter
   Incoming emails can be a spam so we did a simple unikernel which annotes
   incoming emails as a spam or not.

This is a graph of the SMTP service:

```
                                         [ Primary DNS server ]
                                                   |
                                                   |
 *:465 [ Submission server ] -- TLS --> *:25 [ DKIM signer ] -.
                |                                             |
                '---------------------- [ SMTP relay ] *:25 <-|
       [ Git Database ]                    |  |               |
                                           |  |       [ Spam filter ]
                                           |  |               |
                                           |  |      [ SMTP receiver ] <--.
                                           |  |                           |
                                           |  |                           |
                         [ DNS Resolver ] -'  `-> *:25 [ Internet ] *:25 -'
```

As you can see, from outside, we provide 3 main services:
- a submission service where users are able to send an email under your
  authority
- a DNS primary service which describes your authority
- a SMTP receiver which handle incoming emails which wants to communicate
  to your users

In this design:
- the DKIM signer (which contains the private key) does not communicate with
  Internet - and Internet can not directly communicate with it
- the Git database is an internal resource shared by unikernels and the
  administrator can close its access to/from Internet - this is why we talk
  about a **local** Git repository
  Even if the Git repository is local (and accessible only from your private
  network), we still use encrypted protocol (SSH) to communicate with it.
- Only the SMTP relay and the DNS resolver is able to allocate a connection to
  Internet
- Only the submission service, the SMTP receiver and the DNS primary service is
  waiting a connection from Internet

With this design, we restrict as much as we can communication to restrict what
is needed for any services. For instance, the DKIM signer does not need to
resolve domain-name (and does not require a DNS resolver). It implements a
simple service which "just" signs the incoming email and restransmit it to an
other destination.

It's exactly the same for the spam filter which just analyze contents and
annote the incoming email as a spam or not.

## How to deploy from scratch `ptt-deployer`?

The ritual to deploy `ptt-deployer` can depend on your machine but let's
start with an [Equinix][]'s `t1.small.x86` machine with Debian 10. It provides
for us a machine on **147.75.X.Y** (this is our public IPv4 address).

### Network topology

As the deployement of any virtual operating systems, we need to make a _bridge_
on the host system. By this way, we are able to plug to it virtual [tap][]
interfaces and connect our unikernels.

To clear a bit our network topology, we will make a bridge `br0` which
corresponds to our **private network** (10.0.0.1/24) and we will use
`iptables` and its `nat` table to allow/deny protocols between our unikernels
and Internet.

**NOTE**: `ptt-deployer` dynamically takes IP addresses for unikernels. It adds
by itself `nat` rules to redirect TCP/IP packets to unikernels too.

This is a graph of the network topology:
```
  [enps0f0]  [enps0f1]
      |__________|            :
            |                 :
         [bond0] 147.75.X.Y <-:-> [br0] 10.0.0.1
                              :     |- tap100 (submission)
                             NAT    |- tap101 (signer)
                                    |- tap10?
                                    `- tap107 (verifier)
```

We need to install some tools and edit `/etc/network/interfaces`:
```shell=bash
root$ apt update
root$ apt upgrade -y
root$ apt install bridge-utils
```

On the `/etc/network/interfaces`, we must add:
```shell=bash
root$ cat >>/etc/network/interfaces <<EOF
>
> auto br0
> iface br0 inet static
>   address 10.0.0.1
>   netmask 255.255.255.0
>   broadcast 10.0.0.255
>   bridge_ports none
>   bridge_stp off
>   bridge_fd 0
>   bridge_maxwait 0
> EOF
```

#### Firewall

We finally need to configure a bit `iptables` to allow our unikernels to
communicate with Internet, at least. Indeed, depending on what you want and
how you want to orchestrate unikernels, `iptables` is required to configure
the network topology on your host system.

At least, and according to our network topology, we must allow
_port forwarding_ with:
```shell=bash
root$ sysctl net.ipv4.ip_forward=1
root$ cat >>/etc/sysctl.conf <<EOF
> net.ipv4.ip_forward = 1
> EOF
```

Finally, we must "MASQUERADE" our private network. Masquerading allows an
entire network of internal IP addresses to operate through one external IP
address and masquerading allows conversion from one protocol to another. In
other words, our unikernels can communicate to Internet and Internet does not
need to know IP addresses of our private network. The firewall care about
remapping TCP/IP packets to our unikernels when they come from Internet.

```shell=bash
root$ iptables -t nat -A POSTROUTING -o bond0 -j MASQUERADE
```

Incoming rules (like, if someone want to talk to our primary DNS service) will
be handled by `current_albatross_deployer` which will adds `iptables` rules
needed an described into our `ptt-deployer`.

### Our `mirage` user

We can create a new user `mirage` and install tools to compile/deploy
unikernels now.
```shell=bash
root$ adduser mirage
root$ usermod -aG sudo mirage
root$ usermod -aG kvm mirage
root$ su mirage
mirage$ cd
mirage$ sudo apt install build-essential binutils unzip bubblewrap git opam
mirage$ opam init
mirage$ opam switch create 4.13.1
mirage$ git clone https://github.com/roburio/albatross
mirage$ cd albatross
mirage$ opam pin add -yn .
mirage$ opam depext albatross
mirage$ opam install --deps-only albatross
```

### Albatross

[Albatross][albatross] is a _daemon_ which handle our unikernels. It does the
ritual to create [tap][] interfaces (and other devices) required for your
unikernels _via_ an [ASN.1][] protocol. We will build it and install it to our
host system:
```shell=bash
mirage$ pwd
/home/mirage/albatross/
mirage$ eval $(opam env)
mirage$ dune build
mirage$ dune subst
mirage$ ./packaging/debian/create_package.sh
mirage$ sudo dpkg -i albatross.deb
mirage$ cd packaging/Linux/
mirage$ ./install.sh
mirage$ opam depext solo5-bindings-hvt
mirage$ opam install solo5-bindings-hvt
mirage$ sudo cp $(which solo5-hvt) /var/lib/albatross
mirage$ sudo cp $(which solo5-elftool) /var/lib/albatross
mirage$ sudo usermod -aG albatross mirage
mirage$ sudo systemctl enable albatross_daemon
mirage$ sudo systemctl enable albatross_console
```

At this stage, `albatross_daemon` can be run as a _daemon_ _via_ `systemd`.

### `current-albatross-deployer`

To help the user to deploy our SMTP stack and mostly because we allocate a
random IP address for our unikernels, we need to have an automatic tool which
set `iptables` to let some unikernels to be reachable from outside. This tool
is `current-iptables-daemon`:

```shell=bash
mirage$ pwd
/home/mirage
mirage$ eval $(opam env)
mirage$ git clone https://github.com/TheLortex/current-albatross-deployer.git
mirage$ cd current-albatross-deployer
mirage$ opam pin add -yn .
mirage$ opam depext current-albatross-deployer
mirage$ opam install --only-deps -t current-albatross-deployer
mirage$ dune build -p current-albatross-deployer
mirage$ cd lib/iptables-daemon/packaging/Linux
mirage$ sudo ./install.sh
mirage$ sudo systemctl enable current-iptables-daemon
```

As `albatross`, we maid a new daemon which is able to call `iptables` to set
some rules.

### `ptt-deployer`

Finally, we can start to configure and deploy our system _via_ `ptt-deployer`.

`ptt-deployer` is a _service_ which will watch some Git repositories. One
of them is `ptt-deployer` itself. Other Git repositories are our
unikernels. Any update on these repositories will notify `ptt-deployer`
to run the _pipeline_ which compiles/deploys our unikernels.

So we must make a Git user:
```shell=bash
mirage$ sudo adduser git
mirage$ su git
git$ cd
git$ mkdir .ssh && chmod 700 .ssh
git$ mkdir ptt-deployer.git
git$ cd ptt-deployer.git
git$ git init --bare
git$ exit
```

You should save your `id_rsa.pub` into `/home/git/.ssh/authorized_keys` to
allow you to push/pull local Git repositories (_via_ `ssh-copy-id`). We must
synchronize our local Git repository with `dinosaure/ptt-deployer`:
```shell=bash
mirage$ who
mirage pts/0 ...
mirage$ pwd
/home/mirage
mirage$ git clone --recursive https://github.com/dinosaure/ptt-deployer
mirage$ cd ptt-deployer
mirage$ git remote add local git@localhost:ptt-deployer.git
mirage$ git checkout -b live
mirage$ git push -u local live:live
```

`ptt-deployer` as a Docker service will actually care about your SMTP service &
unikernels. The service provide a "small" website (usually available on
`*:8080`) which gives you an overview of unikernels and their states (if they
are running, if the build worked, etc.). Of course, you can introspect all of
that with `albatross` too!

## Configuration

`ptt-deployer` requires some values which should be generated by you according
to your context. Indeed we need few Git repositorys and few "keys" to launch
our `ptt-deployer`:
1) A `zone.git` repository to store our `mirage.ptt` zone file
2) A `relay.git` repository to store users and passwords of users
3) An SSH key to let unikernels to synchronize with local Git repositories
4) The domain of your SMTP service (in our example, `mirage.ptt`)
5) A personal DNS key to let unikernels to interact with our primary DNS
   service
6) A DKIM private key
7) And finally an "account seed" for Let's encrypt (to track our certificates)

Let's start to configure our local Git repositories:
```shell=bash
$ su git
git$ cd
git$ mkdir relay.git
git$ cd relay.git
git$ git init --bare
git$ cd ..
git$ mkdir zone.git
git$ cd zone.git
git$ git init --bare
git$ exit
```

Then, we must generate few keys:
```shell=bash
mirage$ who
mirage pts/0 ...
mirage$ opam install awa
mirage$ awa_gen_key
seed is lShNY3l2He27hG3BBPPeyUdmP+hmZ4AppWmrytrm
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDSh9ZPHeLCTein/4a5KRlomTxoTMYgrzVunbndCMJPr2aNmERGF1VHiSLWkQLRhzRPhRdjuiZz55ab6Zt3bGvGbt0IK5spZQZ3/ihsq6VYW+c5l/RPPbSE9D/ghnbxiQA70Ui4mGSx6NweP239e+3waL1A0QfeSjUtI/ohsBUomlJ1TJZfkriSUFiCFQCDf5w9jHN5jl0FIE4KLU85807KWp1d+bc0olxuCbPw/4d7FKOVbYuAj2n9FNb8+k6YmjvDCCkDzT9/YrzIBAjKWK2PDuJgvWzQf21LEWs2iHnsRM/bexxgFhurGSd+egcpsPUqs/g3wfxinEcCU8p6y0Tqs3tfq47BGzdDVwSz+m5/vJfJTFNucY9YIDs+aBRg1/r8c3oLCaB1hrP5tSsuXh4NzQzkUwRq4bbLdn3MpLK26EYvkps+P0jVj2weRzMKh6emyuwPhNwXD24Lob6/KSwiDi9KQfTBFkH7jMAmaecEYwjHgZREjAalvSmzfWcp40Q+6ajTfM1GBSbgQjH7rC+vpxZpHHWeclNB2LWNYqjU/ka/zgXL2Daxj1s7ZOTQNUgmZXRBs34cBdbMmuCJnIQKKiAPOO4gXMsLKNf15lGeNXYfUQmvtT9WDYednMiehruOclhg4v/BkgvfZXT8on4vUJLxcspN37yFFOGQDTB6kw== awa@awa.local
```

We just generate an RSA SSH key (as `ssh-keygen`) but instead of a private key,
we have a "seed" to reproduce the RSA key with the Fortuna random number
generator. It's possible to use an _ed25519_ key (which smaller) but for
convenience, we will use this one. You need to do 2 operations:
- add the public key (the second line which starts with `ssh-rsa`) into
  `/home/git/.ssh/authorized_keys`
- set [./src/config.ml][] with the "seed" as below

```ocaml=
let ssh_key : string = "rsa:lShNY3l2He27hG3BBPPeyUdmP+hmZ4AppWmrytrm"
```

This key will be use by:
- the primary DNS server to fetch and push `zone.git`
- the submission SMTP server to fetch `relay.git` (and get users and passwords)
- the relay SMTP server to fetch `relay.git` and search the real destination of
  an user

Now, we can set the domain of your SMTP service into [./src/config.ml][]:
```ocaml=
let smtp_domain : string = "mirage.ptt"
```

Finally we will generate 2 "keys", one for DKIM and one for Let's encrypt:
```shell=bash
$ dd if=/dev/urandom bs=32 count=1 status=none | base64 -
GL4QB2K5Q9UBXuM4PhoHTH2MiDbz23KBxpQ3JULhEsE=
$ dd if=/dev/urandom bs=32 count=1 status=none | base64 -
rVYBPGl4PgLKO3gbkllxoyEeBkUfD525ivA+b86PTY8=
```

And set our [./src/config.ml][]:
```ocaml=
let dkim_key : string = "GL4QB2K5Q9UBXuM4PhoHTH2MiDbz23KBxpQ3JULhEsE="
let letsencrypt_account_key : string = "rVYBPGl4PgLKO3gbkllxoyEeBkUfD525ivA+b86PTY8="
```

### Configuration of your domain

The final step is the configuration of your authority/domain-name. We will make
the [zone file][zone-file] of your domain. By this way, we will describe where
is your SMTP service, who own it and some others stuffs like SPF/DKIM
information.

So we need to clone our `zone.git` and add our new domain `mirage.ptt`:
```shell=bash
mirage$ who
mirage pts/0 ...
mirage$ git clone git@localhost:zone.git
mirage$ cd zone
mirage$ cat >mirage.ptt <<EOF
> \$ORIGIN mirage.ptt.
> \$TTL 3600
> @	SOA	ns1	posttmaster	0	86400	7200	1048576	3600
> @     NS      ns1
> @     MX      10      ptt.wtf.
> @     A       147.75.X.Y
> ns1   A       147.75.X.Y
> EOF
mirage$ git add mirage.ptt
mirage$ git commit -m "mirage.ptt zone file"
mirage$ git push
```

**NOTE**: You must put your public IP address. Currently, we focus on the IPv4
address but your are free to put a `AAAA` record into your zone file.

**NOTE**: some providers provide a secondary DNS service which **must** be
added into the zone file. For instance, [Gandi.net][gandi] provides a
`ns6.gandi.net` secondary authoritative DNS server which will do the AXFR
transfer. In such case, you must add into the zone file:
```zone
@	NS	ns6.gandi.net.
```

Then, you must add a "personal" key to be able to update your primary DNS
service. We will generate the key as we did before and put it into a new file:
```shell=bash
mirage$ pwd
/home/mirage/zone
mirage$ dd if=/dev/urandom count=1 bs=32 status=none | base64 -
kzKM0mNUAUwXH6ndwwuM1cIDwIgAyadzOlbf3MHNHRI=
mirage$ cat >mirage.ptt._keys <<EOF
> personal._update.mirage.ptt. DNSKEY 0 3 163 kzKM0mNUAUwXH6ndwwuM1cIDwIgAyadzOlbf3MHNHRI=
> EOF
mirage$ git add mirage.ptt._keys
mirage$ git commit -m "setup mirage.ptt keys"
mirage$ git push
```

And we need to configure `ptt-deployer` to let it to use this key into our
[./src/config.ml][]:
```ocaml=
let dns_personal_key : string = "personal._update.mirage.ptt:SHA256:yT5V9W9tumCjKEyjHXtF18loNIX9FzJmXEXXmjESDJs="
```

### Add a new user into your SMTP service

Everything is close to be setup correctly. We missed just the last and most
important part, we want to add some users into our service.

[ptt][ptt] comes with some tools to add users with their passwords directly
into your local Git repository to the correct format expected by unikernels.
We will build and run these tools locally:
```shell=bash
mirage$ pwd
/home/mirage
mirage$ git clone https://github.com/dinosaure/ptt
mirage$ cd ptt
mirage$ opam pin add -ny .
mirage$ opam depext ptt
mirage$ opam install --deps-only -t ptt
mirage$ dune build -p ptt
mirage$ dune exec bin/adduser.exe -- <username> <password> \
  -t <your-real-email-address> -r git@localhost:relay.git
```

The last line let you to add an user under your authority. More pragmatically,
it creates a new email address `<username>@mirage.ptt` with a password. If
someone sends an email to this address, it will be redirected to
`<your-real-email-address>`.

**NOTE**: you should see some errors about `refs/heads/master` but your user
was perfectly added.

## Run our `ptt-deployer` service

It's time to run our service. First, we need to install We need to install
[Docker][docker] and configure it a bit to allow us to use `buildkit`:
```shell=bash
root$ echo '{ "features": { "buildkit": true } }" >> /etc/docker/daemon.json
```

Now we will build `ptt-deployer` with [Docker][docker], prepare the service and
run it:
```shell=bash
mirage$ pwd
/home/mirage
mirage$ sudo usermod -aG docker mirage
mirage$ cd ptt-deployer
mirage$ git rev-parse --abbrev-ref HEAD
live
mirage$ git status -s
 M src/config.ml
mirage$ git add src/config.ml
mirage$ git commit -m "Update config.ml"
mirage$ git push -u local live:live
mirage$ docker volume create infra_ptt-data
mirage$ docker build .
Successfully built dea279879d59
$ docker swarm init --advertise-addr 147.75.X.Y
$ docker run -d -p 5000:5000 --restart=always --name registry registry:2
$ docker tag dea279879d59 localhost:5000/ptt-deployer
$ docker push localhost:5000/ptt-deployer
$ docker service create --name infra_ptt-deployer -p 8080:8080 \
  --mount source=infra_ptt-data,target=/var/lib/ocurrent \
  --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock \
  --mount type=bind,source=/var/run/albatross/util/vmmd.sock,destination=/var/run/albatross/util/vmmd.sock \
  --mount type=bind,source=/home/git,destination=/git,readonly \
  --mount type=bind,source=/run/current-iptables-daemon/current-iptables-daemon.sock,destination=/var/run/current-iptables-daemon/current-iptables-daemon.sock
  localhost:5000/ptt-deployer
```

At this stage, `ptt-deployer` is available as your entry point to deploy
an unikernel. We _bootstrapped_ `ptt-deployer` and the service can
compile/deploy **itself** if `git@localhost:ptt-deployer.git~live` is
updated.

### SPF information

The last piece is the SPF information which depends on your public address.
Indeed, you must say to anybody that your SMTP submission server is located to
your public IP address. By this fact, people can verify the origin of your
emails:
```shell=bash
mirage$ pwd
/home/mirage
mirage$ cd ptt
mirage$ dune exec bin/spf.exe -- <ip-address-of-dns-primary-git> \
  personal._update.mirage.ptt:SHA256:kzKM0mNUAUwXH6ndwwuM1cIDwIgAyadzOlbf3MHNHRI= 
  mirage.ptt "v=spf1 ip4:147.75.X.Y/32 -all"
```

You can get the IP address of the primary DNS server _via_
`albatross-client-local info` which show you all unikernels and their options -
specially `--ipv4=10.0.0.X`.

The last line upgrade your primary DNS service with a new TXT record which
contains the possible source of `@mirage.ptt`'s emails. By this way, an another
service such as Google can check the origin of your emails.

About DKIM, this update is done by the unikernel itself which, at the boot
time, check DNS records and see if you have one about DKIM. If it's not the
case (at the beginning), it will update as we did, DNS records.

## Conclusion

That's all! The deployment is not perfect and we should improve it but, at
least, we ensure that everything is working together and you are able, now,
to submit an email and receive emails from others!

## Troubles

The SMTP still is experimental and, due to DNS, you probably need a delay
before to deploy everything. Indeed, the DNS service need to transfer your
authority to DNS servers and it can take a time. Then, because we asking some
Let's encrypt certificates, the SMTP stack will work only after the
propagation.

Be aware that you must add secondary DNS server if you provider give you one.

The current version of `ptt-deployer` does not ask production certificates. You
must change [./src/pipeline.ml][] to ask production certificates - it permits
to test your stack regardless the Let's encrypt limitation - so if you are
confident about your stack, you can switch to the production mode.

`dig` and `gnutls-cli` can help you to test your services:
```shell=bash
local$ dig +short mirage.ptt
147.75.X.Y
local$ gnutls-cli --starttls-proto=smtp --insecure mirage.ptt -p 25
...
local$ gnuttls-cli --insecure mirage.ptt -p 465
...
```

Finally, you are able to **submit** an email into your `mirage.ptt` authority
and people can send an email to you _via_  `<username>@mirage.ptt`. These
emails will be redirected to your real email address.

`albatross-local-client` is your friend to introspect unikernels. The provided
website too to get name of unikernels and IP addresses.

[mirage]: https://mirage.io/
[albatross]: https://github.com/roburio/albatross
[pipeline.ml]: ./src/pipeline.ml
[Equinix]: https://equinix.com/
[ASN.1]: https://en.wikipedia.org/wiki/ASN.1
[docker]: https://docs.docker.com/engine/install/debian/
[tap]: https://en.wikipedia.org/wiki/TUN/TAP
[bond]: https://wiki.debian.org/Bonding
[ptt]: https://github.com/dinosaure/ptt
[kvm]: https://fr.wikipedia.org/wiki/Kernel-based_Virtual_Machine
[mrmime]: https://github.com/mirage/mrmime
[uspf]: https://github.com/dinosaure/uspf
[ocaml-dkim]: https://github.com/dinosaure/ocaml-dkim
[spamtacus]: https://github.com/mirage/spamtacus
[colombe]: https://github.com/mirage/colombe
[ocaml-dmarc]: https://github.com/dinosaure/ocaml-dmarc
[ocaml-dns]: https://github.com/mirage/ocaml-dns
[ocurrent]: https://github.com/ocurrent/ocurrent
[current\_albatross\_deployer]: https://github.com/TheLortex/current-albatross-deployer
[xen]: https://xenproject.org/
[dns-primary-git]: https://github.com/roburio/dns-primary-git
[nsupdate]: https://linux.die.net/man/8/nsupdate
[./src/config.ml]: ./src/config.ml
[zone-file]: https://en.wikipedia.org/wiki/Zone_file
[gandi]: https://gandi.net
[./src/pipeline.ml]: ./src/pipeline.ml
