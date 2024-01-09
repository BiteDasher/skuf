#!/bin/bash
if [ ! -r ./tune.crypt ]; then
    echo "Error: file 'tune.crypt' does not exists or missing permissions" >&2
    exit 1
fi

if [ -z "$(cat ./tune.crypt)" ]; then
	echo "Error: file 'tune.crypt' is empty" >&2
	exit 1
fi

if [ ! -f "./skuf_src/init(untuned)" ]; then
    echo "Error: file 'skuf_src/init(untuned)' does not exists" >&2
    exit 1
fi

if [ ! -f "./skuf_src/kinit(untuned)" ]; then
    echo "Error: file 'skuf_src/kinit(untuned)' does not exists" >&2
    exit 1
fi

> ./.tune_crypt_pattern_enc
> ./.tune_crypt_pattern_dec

[ -f ./skuf_src/init ]  || cp -a "./skuf_src/init(untuned)" "./skuf_src/init"
[ -f ./skuf_src/kinit ] || cp -a "./skuf_src/kinit(untuned)" "./skuf_src/kinit"

while read -r pair; do
    from="${pair%% *}"
    to="${pair##* }"
    if [ -z "$from" ] || [ -z "$to" ]; then
        echo "Missing pair!" >&2
        rm -f ./skuf_src/{init,kinit}
        exit 1
    fi
    echo "$from -> $to"
    cat <<EOF >> ./.tune_crypt_pattern_enc
    sambaoptsx="\${sambaoptsx//$from/^}" # SKUF_ENC_TUNE
    sambaoptsx="\${sambaoptsx//$to/$from}" # SKUF_ENC_TUNE
    sambaoptsx="\${sambaoptsx//^/$to}" # SKUF_ENC_TUNE
EOF

    cat <<EOF >> ./.tune_crypt_pattern_dec
        _sambaopts="\${_sambaopts//$to/^}" # SKUF_DEC_TUNE
        _sambaopts="\${_sambaopts//$from/$to}" # SKUF_DEC_TUNE
        _sambaopts="\${_sambaopts//^/$from}" # SKUF_DEC_TUNE
EOF
done < ./tune.crypt

sed -i '/# SKUF_ENC_TUNE #/r .tune_crypt_pattern_enc' ./skuf_src/kinit
sed -i '/# SKUF_DEC_TUNE #/r .tune_crypt_pattern_dec' ./skuf_src/init

rm ./.tune_crypt_pattern_enc
rm ./.tune_crypt_pattern_dec

echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
