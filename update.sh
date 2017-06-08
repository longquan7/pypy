#!/bin/bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

pipVersion="$(curl -fsSL 'https://pypi.org/pypi/pip/json' | jq -r .info.version)"

for version in "${versions[@]}"; do
	case "$version" in
		3) pypy='pypy3' ;;
		2) pypy='pypy2' ;;
		*) echo >&2 "error: unknown pypy variant $version"; exit 1 ;;
	esac

	# <td class="name"><a class="execute" href="/pypy/pypy/downloads/pypy-2.4.0-linux64.tar.bz2">pypy-2.4.0-linux64.tar.bz2</a></td>
	# <td class="name"><a class="execute" href="/pypy/pypy/downloads/pypy3-2.4.0-linux64.tar.bz2">pypy3-2.4.0-linux64.tar.bz2</a></td>
	IFS=$'\n'
	tryVersions=( $(
		curl -fsSL 'https://bitbucket.org/pypy/pypy/downloads/' \
			| grep -E "$pypy"'-v([0-9.]+(-alpha[0-9]*)?)-linux64.tar.bz2' \
			| sed -r 's/^.*'"$pypy"'-v([0-9.]+(-alpha[0-9]*)?)-linux64.tar.bz2.*$/\1/' \
			| sort -rV
	) )
	unset IFS

	fullVersion=
	sha256sum=
	for tryVersion in "${tryVersions[@]}"; do
		# <p>pypy2.7-5.4.0 sha256:</p>
		# <pre class="literal-block">
		# ...
		# bdfea513d59dcd580970cb6f79f3a250d00191fd46b68133d5327e924ca845f8  pypy2-v5.4.0-linux64.tar.bz2
		# ...
		# </pre>
		if \
			sha256sum="$(
				curl -fsSL 'http://pypy.org/download.html' \
					| grep -m1 -E '[a-f0-9]{64}  '"$pypy-v$tryVersion"'-linux64.tar.bz2' \
					| cut -d' ' -f1
			)" \
			&& [ -n "$sha256sum" ] \
		; then
			fullVersion="$tryVersion"
			break
		fi
	done
	if [ -z "$fullVersion" ]; then
		echo >&2 "error: cannot find suitable release for '$version'"
		exit 1
	fi

	(
		set -x
		sed -ri '
			s/^(ENV PYPY_VERSION) .*/\1 '"$fullVersion"'/;
			s/^(ENV PYPY_SHA256SUM) .*/\1 '"$sha256sum"'/;
			s/^(ENV PYTHON_PIP_VERSION) .*/\1 '"$pipVersion"'/;
		' "$version"{,/slim}/Dockerfile
		sed -ri 's/^(FROM pypy):.*/\1:'"$version"'/' "$version/onbuild/Dockerfile"
	)
done
