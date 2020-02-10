# Deployer

This repository contains an [OCurrent][] pipeline for deploying the other
pipelines we use. When a new commit is pushed to the `live` branch of a source
repository, it builds a new Docker image for the project and upgrades the
service to that version.

The [pipeline.ml][] deploys some [MirageOS][] unikernels, e.g.

```ocaml
mirage, "mirage-www", [
  unikernel "Dockerfile" ~target:"hvt"
    ["EXTRA_FLAGS=--tls=true"] ["master", "www"];
  unikernel "Dockerfile" ~target:"xen"
    ["EXTRA_FLAGS=--tls=true"] []; (* (no deployments) *)
];
```

This builds each branch and PR of <https://github.com/mirage/mirage-www> for
both `hvt` and `xen` targets. For the `master` branch, the `hvt` unikernel is
deployed as the `www` [Albatross][] service.

## How to deploy from scratch `ocurrent-deployer`?

The ritual to deploy `ocurrent-deployer` can depend on your machine but let's
start with an [Equinix][]'s `t1.small.x86` machine with Debian 10. It provides
for us a machine on **147.75.X.Y** (this is our IPv4 address).

### Network topology

As the deployement of any virtual operating systems, we need to make a _bridge_
on the host system. By this way, we are able to plug to it virtual [tap][]
interfaces and connect our unikernels.

To clear a bit our network topology, we will make a bridge `br1` which
corresponds to our **private network** (192.168.1.2/24) and we will use
`iptables` and its `nat` table to allow/deny protocols between our unikernels
and internet.

Equinix's machines use a [_bond_][bond] interface and we will configure
bridging and link our `bond0` with our new `br0` interface. We need to install
some tools and edit `/etc/network/interfaces`:
```sh
# apt update
# apt upgrade -y
# apt install bridge-utils
```

On the `/etc/network/interfaces`, we must add:
```
auto br0
iface br0 inet static
  bridge_ports bond0
  bridge_stp off
  bridge_fd 0
  bridge_maxwait 0

auto br1
iface br1 inet static
  address 192.168.1.2
  netmask 255.255.255.0
  broadcast 192.168.1.255
  bridge_ports none
  bridge_stp off
  bridge_fd 0
  bridge_maxwait 0
```

Then, we must move our public address IP from `bond0` to `br0`:
```
auto bond0
iface bond0 inet manual
#    address 147.75.X.Y
#    netmask 255.255.255.254
#    gateway 147.75.X.Z
...

auto br0
iface br0 inet static
   address 147.75.X.Y
   netmask 255.255.255.254
   gateway 147.75.X.Z
```

Now, you can reboot the server and an `ip show addr` will show our bridges.

#### Firewall

We finally need to configure a bit `iptables` to allow our unikernels to
communicate with internet, at least. Indeed, depending on what you want and
how you want to orchestrate unikernels, `iptables` is required to configure
the network topology on your host system.

At least, and according to our network topology, we must allow
_port forwarding_ with:
```sh
# sysctl net.ipv4.ip_forward=1
```

Then, we must allow `FORWARD` for `br0` and `br1`:
```sh
# iptables -A FORWARD -o br0 -j ACCEPT
# iptables -A FORWARD -i br0 -j ACCEPT
# iptables -A FORWARD -o br1 -j ACCEPT
# iptables -A FORWARD -i br1 -j ACCEPT
```

And finally we need to allow our private IP address of our unikernel to
communicate with internet _via_ our public IP address. For such purpose,
we need to add these rules:
```sh
# iptables -t nat -A POSTROUTING -o br1 -j MASQUERADE
# iptables -t nat -A POSTROUTING -o br0 -j MASQUERADE
```

### Our `mirage` user

We can create a new user `mirage` and install tools to compile/deploy
unikernels now.
```sh
# adduser mirage
# usermod -aG sudo mirage
# usermod -aG kvm mirage
# su mirage
$ cd
$ sudo apt install build-essential binutils unzip bubblewrap git opam
$ opam init
$ opam switch create 4.12.0
$ git clone https://github.com/roburio/albatross
$ cd albatross
$ opam pin add -y .
```

### Albatross

[Albatross][] is a _daemon_ which handle our unikernels. It does the ritual
to create [tap][] interfaces (and other devices) required for your unikernels
_via_ an [ASN.1][] protocol. We will build it and install it to our host
system:
```
$ pwd
/home/mirage/albatross/
$ dune build
$ dune subst
$ ./packaging/debian/create_package.sh
$ sudo dpkg -i albatross.deb
$ cd packaging/Linux/
$ ./install.sh
$ opam install solo5-bindings-hvt
$ sudo $(which solo5-hvt) /var/lib/albatross
$ sudo $(which solo5-elftool) /var/lib/albatross
$ sudo usermod -aG albatross mirage
```

At this stage, `albatross_daemon` can be run as a _daemon_ _via_ `systemd`.

### `ocurrent-deployer`

`ocurrent-deployer` is a _service_ which will watch some Git repositories. One
of them is `ocurrent-deployer` itself. Other Git repositories are your
unikernels. Any update on these repositories will notify `ocurrent-deployer`
to run the _pipeline_ which compiles/deploys your unikernels.

So we must make a Git user:
```sh
$ sudo adduser git
$ su git
$ cd
$ mkdir .ssh && chmod 700 .ssh
$ touch .ssh/authorized_keys && chmod 600 .ssh/authorized_keys
$ mkdir occurent-deployer.git
$ cd ocurrent-deployer.git
$ git init --bare
$ exit
```

You should save your `id_rsa.pub` into `/home/git/.ssh/authorized_keys` to
allow you to push/pull local Git repositories (_via_ `ssh-copy-id`). We must
synchronize our local Git repository with `mirage/ocurrent-deployer`:
```sh
$ who
mirage pts/0 ...
$ git clone --recursive https://github.com/mirage/ocurrent-deployer
$ cd ocurrent-deployer
$ git remote add local git@localhost:ocurrent-deployer.git
$ git checkout -b live
$ git push -u local live:live
```

Only the `live` branch matters for our deployement purpose. Now, we can build
and launch `ocurrent-deployer`. We need to install [Docker][]. Then, we do:
```sh
$ sudo usermod -aG docker mirage
$ cd ocurrent-deployer
$ docker volume create infra_ocurrent-data
$ docker build .
$ docker swarm init --advertise-addr 147.75.X.Y
$ docker run -d -p 5000:5000 --restart=always --name registry registry:2
$ docker tag <hash> localhost:5000/ocurrent-deployer
$ docker push localhost:5000/ocurrent-deployer
$ docker service create --name infra_ocurrent-deployer -p 8080:8080 \
  --mount source=infra_ocurrent-data,target=/var/lib/ocurrent \
  --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock \
  --mount type=bind,source=/var/run/albatross/util/vmmd.sock,destination=/var/run/albatross/util/vmmd.sock \
  --mount type=bind,source=/home/git,destination=/git,readonly \
  localhost:5000/ocurrent-deployer
```

At this stage, `ocurrent-deployer` is available as your entry point to deploy
an unikernel. We _bootstrapped_ `ocurrent-deployer` and the service can
compile/deploy **itself** if `git@localhost:ocurrent-deployer.git~live` is
updated. Now, only [pipeline.ml][] matters for us to deploy our unikernel.

### A simple DNS resolver

At first, we will replicate locally `mirage/dns-resolver` into our server to be
able to do some hot-fix without an access to the `mirage` organization. Then,
we need to update `ocurrent-deployer` (locally) to add our unikernel into
the _pipeline_:
```
$ su git
$ cd 
$ mkdir dns-resolver.git
$ cd dns-resolver.git
$ git init --bare
$ exit
$ who
mirage pts/0 ...
$ git clone https://github.com/mirage/dns-resolver.git
$ cd dns-resolver
$ git remote add local git@localhost:dns-resolver.git
$ git checkout -b live
$ git push -u local live:live
```

Into the `dns-resolver` repository, you can find a `Dockerfile` which
describes how to compile an unikernel. This is what `ocurrent-deployer` will
use to compile the unikernel.

Now, we need to update `ocurrent-deployer` and its [pipeline.ml][] to add our
new DNS resolver:
```diff
diff --git a/src/pipeline.ml b/src/pipeline.ml
index 5db17ce..ed8b992 100644
--- a/src/pipeline.ml
+++ b/src/pipeline.ml
@@ -89,7 +89,11 @@ let v () =
 
   let mirage_unikernels =
     let unikernels =
-      [ ]
+      [ unikernel "Dockerfile" ~name:"dns-resolver"
+          ~git:(git_local_bare "/git/dns-resolver.git")
+          ~target:"hvt"
+          ~build_args:
+            [ "EXTRA_FLAGS=--ipv4=192.168.1.3/24 --ipv4-gateway=192.168.1.2" ]
+      [ ("live", "dns-resolver") ] ]
     in
     let build (build_info, deploys, git, name) =
       Build_unikernel.repo ~git ~name [ (build_info, deploys) ]
```

Now, you just need to commit & push to the local repository and
`ocurrent-deployer` will deploy your unikernel! The compilation (and logs) is
available on a website: http://147.75.X.Y:8080/. It shows the _pipeline_.

When the unikernel is deployed, you can see logs from it with Albatross:
```sh
$ albatross-client-local console dns-resolver
```

And finally, you can use this DNS resolver as your main DNS resolver:
```sh
$ sudo apt install dnsutils
$ dig +short google.com @192.168.1.3
172.217.168.238
```

[OCurrent]: https://github.com/ocurrent/ocurrent
[MirageOS]: https://mirage.io/
[Albatross]: https://github.com/roburio/albatross
[pipeline.ml]: ./src/pipeline.ml
[Equinix]: https://equinix.com/
[ASN.1]: https://en.wikipedia.org/wiki/ASN.1
[Docker]: https://docs.docker.com/engine/install/debian/
[tap]: https://en.wikipedia.org/wiki/TUN/TAP
[bond]: https://wiki.debian.org/Bonding
