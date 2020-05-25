#!/bin/bash
npm install
./node_modules/coffee-script/bin/coffee ./node_modules/lua-distiller/bin/lua-distiller.coffee -i src/assrt.lua -x mp.options,mp.utils,bit -o scripts/assrt.lua
rm -rf scripts/assrt
mkdir scripts/assrt
cp src/assrt.js scripts/assrt/main.js 
cp src/modules.js/* scripts/assrt/
