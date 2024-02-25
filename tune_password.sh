#!/bin/bash
if [ ! -r ./tune.password ]; then
    echo "Error: file 'tune.password' does not exists or missing permissions" >&2
    exit 1
fi

if [ -z "$(cat ./tune.password)" ]; then
	echo "Error: file 'tune.password' is empty" >&2
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

read -r data <./tune.password
iter="${data%% *}"

if [ -z "$iter" ]; then
    echo "Missing iter!" >&2
    exit 1
fi

case "$iter" in
    ''|*[!0-9]*)
        echo "iter containts something other than number!" >&2
        exit 1
    ;;
    *)
        :
    ;;
esac

password="${data#* }"

if [ -z "$password" ]; then
    echo "Missing password!" >&2
    exit 1
fi

: > ./.tune_password_pattern_enc
: > ./.tune_password_pattern_dec

[ -f ./skuf_src/init ]  || cp -a "./skuf_src/init(untuned)" "./skuf_src/init"
[ -f ./skuf_src/kinit ] || cp -a "./skuf_src/kinit(untuned)" "./skuf_src/kinit"

cat <<EOF > ./.tune_password_pattern_enc
    sambaoptsx="\$(echo -n "\$sambaoptsx" | openssl enc -e -aes-256-cbc -salt -iter $iter -base64 -A -k '$password' -in - -out -)" # SKUF_OPENSSL_ENC_RM #
EOF

cat <<EOF > ./.tune_password_pattern_dec
        if _sambaopts="\$(echo -n "\$_sambaopts" | openssl enc -d -aes-256-cbc -salt -iter $iter -base64 -A -k '$password' -in - -out -)"; then # SKUF_OPENSSL_DEC_RM #
EOF

sed -i "/# SKUF_OPENSSL_ENC_RM #/d" ./skuf_src/kinit
sed -i "/# SKUF_OPENSSL_DEC_RM #/d" ./skuf_src/init
sed -i "/# SKUF_OPENSSL_ENC #/r .tune_password_pattern_enc" ./skuf_src/kinit
sed -i "/# SKUF_OPENSSL_DEC #/r .tune_password_pattern_dec" ./skuf_src/init

rm ./.tune_password_pattern_enc
rm ./.tune_password_pattern_dec

echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
