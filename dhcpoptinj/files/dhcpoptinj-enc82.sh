#!/bin/sh

usage() {
	cat <<'EOF'
Usage: dhcpoptinj-enc82 [-c|--circuit-id TEXT] [-r|--remote-id TEXT]

Encode DHCP option 82 sub-options into hex for use with dhcpoptinj -o.

Options:
  -c, --circuit-id TEXT    Agent Circuit ID (sub-option 1)
  -r, --remote-id TEXT     Agent Remote ID (sub-option 2)
  -h, --help               Show this help

Examples:
  dhcpoptinj-enc82 -c "my-relay" -r "switch-01"
  # Output: 52:01:08:6D:79:2D:72:65:6C:61:79:02:09:73:77:69:74:63:68:2D:30:31

  dhcpoptinj-enc82 -c "Fjas"
  # Output: 52:01:04:46:6A:61:73
EOF
	exit 0
}

text_to_hex() {
	printf '%s' "$1" | od -A n -t x1 | tr -s ' \n' : | sed 's/^://;s/:$//g'
}

encode_subopt() {
	local code="$1" text="$2" hexstr nbytes
	hexstr=$(text_to_hex "$text")
	nbytes=$(printf '%s\n' "$hexstr" | tr ':' '\n' | wc -l)
	[ "$nbytes" -gt 255 ] && {
		echo "error: sub-option value too long ($nbytes > 255 bytes)" >&2
		return 1
	}
	printf '%s:%02X:%s' "$code" "$nbytes" "$hexstr"
}

main() {
	local circuit_id remote_id result

	while [ $# -gt 0 ]; do
		case "$1" in
			-c|--circuit-id) circuit_id="$2"; shift 2 ;;
			-r|--remote-id)  remote_id="$2"; shift 2 ;;
			-h|--help)       usage ;;
			*) echo "Unknown option: $1" >&2; usage ;;
		esac
	done

	[ -z "$circuit_id" ] && [ -z "$remote_id" ] && {
		echo "error: at least one of -c or -r is required" >&2
		usage
	}

	result="52"
	if [ -n "$circuit_id" ]; then
		result="$result:$(encode_subopt 01 "$circuit_id")" || return 1
	fi
	if [ -n "$remote_id" ]; then
		result="$result:$(encode_subopt 02 "$remote_id")" || return 1
	fi

	printf '%s\n' "$result"
}

main "$@"
