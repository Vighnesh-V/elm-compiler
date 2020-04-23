elmd make --optimize --simplify="opt" --output=elm.js src/Main.elm
elm make --optimize  --output=elm.og.js src/Main.elm
./optimize.sh elm.og
(Old bytes - New bytes)/old bytes
