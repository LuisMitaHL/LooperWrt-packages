#!/bin/sh

PROG_NAME="${0##*/}"

usage() {
	cat <<EOF
Usage: $PROG_NAME {start|stop|reload|help}

  start   Generate and apply nftables isolation rules
  stop    Remove all isolation rules
  reload  Re-generate and re-apply isolation rules
  help    Show this help message
EOF
}

_is_enabled() {
	local val
	config_get_bool val settings enabled 1
	[ "$val" = "1" ]
}

_get_ifname() {
	local section="$1"
	local ifname

	config_get ifname "$section" ifname
	[ -n "$ifname" ] && [ -d "/sys/class/net/$ifname" ] && {
		echo "$ifname"
		return 0
	}

	ifname="${section#wifi_}"
	ifname="${ifname//_/-}"
	[ -d "/sys/class/net/$ifname" ] && {
		echo "$ifname"
		return 0
	}

	ifname="${section//_/-}"
	[ -d "/sys/class/net/$ifname" ] && {
		echo "$ifname"
		return 0
	}

	return 1
}

_find_isolated() {
	local section="$1"
	local isolated
	local ifname

	config_get isolated "$section" isolate
	[ "$isolated" != "1" ] && return

	ifname="$(_get_ifname "$section")"
	[ -z "$ifname" ] && {
		logger -t ap-isolation "Warning: interface for section '$section' not found, skipping"
		return
	}

	[ -n "$IFACES" ] && IFACES="$IFACES, "
	IFACES="${IFACES}\"$ifname\""
}

collect_ifaces() {
	IFACES=""
	config_foreach _find_isolated wifi-iface
}

_remove_rules() {
	nft delete table bridge ap_isolation 2>/dev/null
}

_generate_rules() {
	local ifaces="$1"
	local vlan_id="$2"
	local gw_ip="$3"
	local ipv6_enabled="$4"
	local gw_mac="$5"
	local vlan

	[ -z "$ifaces" ] && return 1

	vlan=""
	[ -n "$vlan_id" ] && [ "$vlan_id" != "0" ] && vlan="vlan id ${vlan_id}"

	cat <<EOF
table bridge ap_isolation {
	set wlan {
		type ifname
		elements = { ${ifaces} }
	}

	chain forward {
		type filter hook forward priority filter; policy accept;

EOF

	if [ -n "$gw_ip" ] && [ -n "$gw_mac" ]; then
		cat <<EOF
		iifname @wlan ${vlan} arp operation request arp daddr ip ${gw_ip} counter accept
		iifname @wlan ${vlan} arp operation reply ether daddr ${gw_mac} counter accept
		iifname @wlan ${vlan} ether type arp counter drop
		iifname @wlan ${vlan} ether type vlan vlan type arp counter drop

		oifname @wlan ${vlan} arp operation reply ether saddr ${gw_mac} counter accept
		oifname @wlan ${vlan} arp operation request ether saddr ${gw_mac} counter accept
		oifname @wlan ${vlan} ether type arp counter drop
		oifname @wlan ${vlan} ether type vlan vlan type arp counter drop
EOF
	elif [ -n "$gw_ip" ]; then
		cat <<EOF
		iifname @wlan ${vlan} arp operation request arp daddr ip ${gw_ip} counter accept
		iifname @wlan ${vlan} arp operation reply counter accept
		iifname @wlan ${vlan} ether type arp counter drop
		iifname @wlan ${vlan} ether type vlan vlan type arp counter drop
EOF
	fi

	cat <<EOF
		iifname @wlan ${vlan} ip protocol udp udp sport 68 udp dport 67 counter accept
		oifname @wlan ${vlan} ip protocol udp udp sport 67 udp dport 68 counter accept
EOF

	if [ "$ipv6_enabled" = "1" ]; then
		cat <<EOF
		iifname @wlan ${vlan} ip6 nexthdr icmpv6 icmpv6 type nd-router-solicit counter accept
		oifname @wlan ${vlan} ip6 nexthdr icmpv6 icmpv6 type nd-router-advert counter accept
		oifname @wlan ${vlan} ip6 nexthdr icmpv6 icmpv6 type nd-redirect counter accept
		iifname @wlan ${vlan} ip6 nexthdr icmpv6 icmpv6 type nd-neighbor-solicit counter accept
		oifname @wlan ${vlan} ip6 nexthdr icmpv6 icmpv6 type nd-neighbor-solicit counter accept
		iifname @wlan ${vlan} ip6 nexthdr icmpv6 icmpv6 type nd-neighbor-advert counter accept
		oifname @wlan ${vlan} ip6 nexthdr icmpv6 icmpv6 type nd-neighbor-advert counter accept
		iifname @wlan ${vlan} ip6 nexthdr udp udp sport 546 udp dport 547 counter accept
		oifname @wlan ${vlan} ip6 nexthdr udp udp sport 547 udp dport 546 counter accept
EOF
	fi

	cat <<EOF
		iifname @wlan ${vlan} ether daddr ff:ff:ff:ff:ff:ff counter drop
		iifname @wlan ${vlan} ether daddr & 01:00:00:00:00:00 == 01:00:00:00:00:00 counter drop
		oifname @wlan ${vlan} ether daddr ff:ff:ff:ff:ff:ff counter drop
		oifname @wlan ${vlan} ether daddr & 01:00:00:00:00:00 == 01:00:00:00:00:00 counter drop
	}
}
EOF
}

_apply() {
	local tmpfile

	rm -f /tmp/ap-isolation.nft
	_generate_rules "$1" "$2" "$3" "$4" "$5" > /tmp/ap-isolation.nft || return 1

	nft delete table bridge ap_isolation 2>/dev/null
	nft -f /tmp/ap-isolation.nft 2>&1 || {
		local rc=$?
		rm -f /tmp/ap-isolation.nft
		logger -t ap-isolation "Error: nft -f failed with status $rc"
		return $rc
	}
	rm -f /tmp/ap-isolation.nft
}

do_start() {
	[ "$(command -v nft)" ] || {
		logger -t ap-isolation "nftables not available, skipping"
		return 1
	}

	. /lib/functions.sh

	config_load ap-isolation
	_is_enabled || {
		_remove_rules
		logger -t ap-isolation "disabled by config, rules removed"
		return 0
	}

	local vlan_id gw_ip gw_mac ipv6_enabled
	config_get vlan_id settings vlan_id
	config_get gw_ip settings gateway_ip
	config_get gw_mac settings gateway_mac
	config_get_bool ipv6_enabled settings ipv6_enabled 0

	config_load wireless
	collect_ifaces
	[ -z "$IFACES" ] && {
		_remove_rules
		logger -t ap-isolation "no isolated interfaces found, rules removed"
		return 0
	}

	_apply "$IFACES" "$vlan_id" "$gw_ip" "$ipv6_enabled" "$gw_mac" || {
		logger -t ap-isolation "Error: failed to apply rules"
		return 1
	}

	logger -t ap-isolation "rules applied for interfaces: ${IFACES}"
}

do_stop() {
	_remove_rules
	logger -t ap-isolation "rules removed"
}

do_reload() {
	do_start
}

case "${1:-help}" in
	start) do_start ;;
	stop) do_stop ;;
	reload) do_reload ;;
	help|--help|-h) usage ;;
	*)
		echo "Unknown command: $1"
		usage
		exit 1
		;;
esac
