#!/bin/bash
set -e

umask 022

rm -rf deb-build
mkdir -p deb-build/DEBIAN
mkdir -p "deb-build$PREFIX/bin"

cp DEBIAN/control deb-build/DEBIAN/control
cp DEBIAN/install deb-build/DEBIAN/install
cp main.sh "deb-build$PREFIX/bin/ttdm"
chmod 755 "deb-build$PREFIX/bin/ttdm"

chmod 755 deb-build/DEBIAN
chmod 644 deb-build/DEBIAN/control

dpkg-deb --build deb-build ttdm_1.0.0_all.deb
echo "✅ Paquet Termux créé : ttdm_1.0.0_all.deb"
