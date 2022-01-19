FROM ocaml/opam:debian-10-ocaml-4.12@sha256:946f3314ce32f4a1f5ac6f285283a1cf40da54b16b1f4122c26ce120403ff557 AS build
RUN sudo apt-get update && sudo apt-get install libev-dev m4 pkg-config libsqlite3-dev libgmp-dev libssl-dev capnproto graphviz -y --no-install-recommends
RUN cd ~/opam-repository && git pull origin -q master && git reset --hard f569100d0045c2959ab9af0a04fef6f04f882e5e && opam update
COPY --chown=opam \
	ocurrent/current_docker.opam \
	ocurrent/current_github.opam \
	ocurrent/current_git.opam \
	ocurrent/current.opam \
	ocurrent/current_rpc.opam \
	ocurrent/current_slack.opam \
	ocurrent/current_web.opam \
	/src/ocurrent/
COPY --chown=opam \
        ocluster/*.opam \
        /src/ocluster/
WORKDIR /src
RUN opam pin add -yn current_docker.dev "./ocurrent" && \
    opam pin add -yn current_github.dev "./ocurrent" && \
    opam pin add -yn current_git.dev "./ocurrent" && \
    opam pin add -yn current.dev "./ocurrent" && \
    opam pin add -yn current_rpc.dev "./ocurrent" && \
    opam pin add -yn current_slack.dev "./ocurrent" && \
    opam pin add -yn current_web.dev "./ocurrent" && \
    opam pin add -yn ocluster-api.dev "./ocluster"
COPY --chown=opam current-albatross-deployer/current-albatross-deployer.opam /src/current-albatross-deployer/
RUN opam pin add -yn current-albatross-deployer.dev "./current-albatross-deployer"
RUN opam depext -ui current-albatross-deployer.dev
COPY --chown=opam deployer.opam /src/
RUN opam pin -yn add .
RUN opam depext -ui deployer
ADD --chown=opam . .
RUN opam config exec -- dune build ./_build/install/default/bin/ocurrent-deployer

FROM ocaml/opam:debian-10-ocaml-4.12@sha256:946f3314ce32f4a1f5ac6f285283a1cf40da54b16b1f4122c26ce120403ff557 AS build-albatross
RUN sudo apt-get update && sudo apt-get install libgmp-dev pkg-config libnl-3-dev libnl-route-3-dev libseccomp-dev -y --no-install-recommends
RUN cd ~/opam-repository && git pull origin -q master && git reset --hard f569100d0045c2959ab9af0a04fef6f04f882e5e && opam update
RUN opam install albatross.1.3.0 solo5-bindings-hvt

FROM debian:10
RUN apt-get update && apt-get install libev4 openssh-client curl gnupg2 dumb-init git graphviz libsqlite3-dev ca-certificates netbase rsync -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb [arch=amd64] https://download.docker.com/linux/debian buster stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce -y --no-install-recommends
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/ocurrent-deployer"]
COPY --from=build /src/_build/install/default/bin/ocurrent-deployer /usr/local/bin/
COPY --from=build-albatross /home/opam/.opam/4.12/bin/albatross-client-local /usr/local/bin/
COPY --from=build-albatross /home/opam/.opam/4.12/bin/solo5-elftool /var/lib/albatross/
