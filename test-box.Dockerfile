# Throwaway Ubuntu box to test setup.sh over real ssh.
#
#   docker build -t setup-test -f test-box.Dockerfile .
#   docker run -d --name setup-test -p 2222:22 -v "$PWD":/home/dev/dotfiles:ro setup-test
#   ssh dev@localhost -p 2222        # password: dev
#   dev$ bash ~/dotfiles/setup.sh    # pick components at the menu
#
# Reset: docker rm -f setup-test, then docker run again (fresh box each time)
FROM ubuntu:24.04
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server sudo ca-certificates curl && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd && \
    useradd -m -s /bin/bash dev && echo 'dev:dev' | chpasswd && \
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
