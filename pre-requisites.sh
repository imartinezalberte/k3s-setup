#!/bin/bash

sudo apt install -y bridge-utils \
                    cpu-checker \
                    libvirt-clients \
                    libvirt-daemon \
                    qemu \
                    qemu-kvm

kvm-ok

