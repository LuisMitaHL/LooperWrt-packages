#!/usr/bin/ucode
/* ts-watchdog - keep Tailscale's policy routing rules and routing table
 * (default 52) populated on OpenWrt.
 *
 * On mwan3/netifd-heavy routers, tailscaled's table 52 routes can end up
 * wiped (its own reconcile races netlink churn, or the tun device flaps)
 * while tailscaled considers its state fine and never re-applies them.
 * The ip rules at the 52xx base are self-healed by tailscaled >= 1.102
 * (netmon.RuleDeleted handler), but table 52 routes are not.
 *
 * Strategy (dl12345/mwan3-tailscale-setup compatible: mwan3 priority bases
 * at 1100/1200 mean tailscale installs at its default 5200 base):
 *
 *   - verify the 4 policy rules per family (base+10/+30/+50/+70), re-add
 *     if missing (idempotent, NLM_F_EXCL)
 *   - derive the *desired* table 52 content from tailscale's own view:
 *     `tailscale debug netmap` (peer addresses, primary subnet routes)
 *     and `tailscale debug prefs` (RouteAll, exit node selection)
 *   - diff desired vs actual (netlink dump of the table)
 *   - re-add the missing desired routes directly via netlink (the
 *     desired set comes from tailscale's live view, not a cache, so
 *     control-plane deletions (peer left, subnet route withdrawn, exit
 *     node disabled) are never fought; known triggers of the wipe are
 *     mwan3 restarts and other netlink churn storms)
 *   - also trigger `tailscale debug force-netmap-update`, which makes
 *     tailscaled re-apply its routes only when the netmap actually
 *     changed - a re-sent identical netmap is a no-op
 *   - last-resort escalation only: a rate-limited tailscale0 down/up
 *     with a real 1 s gap, followed by directly re-adding the desired
 *     routes (a bounce flushes the table and tailscaled does not
 *     reliably re-apply its v4 routes afterwards)
 *
 * Runs under procd; logs to stderr (forwarded to syslog). */

'use strict';

import * as rtnl from 'rtnl';
import * as uci from 'uci';
import { open, popen } from 'fs';

const C = rtnl.const;
const RTM_GETRULE = C.RTM_GETRULE;
const RTM_GETROUTE = C.RTM_GETROUTE;
const RTM_GETLINK = C.RTM_GETLINK;
const RTM_NEWRULE = C.RTM_NEWRULE;
const RTM_NEWROUTE = C.RTM_NEWROUTE;
const NLM_F_DUMP = C.NLM_F_DUMP;
const NLM_F_CREATE = C.NLM_F_CREATE;
const NLM_F_REPLACE = C.NLM_F_REPLACE;
const NLM_F_EXCL = C.NLM_F_EXCL;
const AF_INET = C.AF_INET;
const AF_INET6 = C.AF_INET6;
const FR_ACT_TO_TBL = C.FR_ACT_TO_TBL;
const FR_ACT_UNREACHABLE = C.FR_ACT_UNREACHABLE;

const TS_MARK = 0x80000;
const TS_MARK_MASK = 0xff0000;
const TS_ULAGR_V6 = 'fd7a:115c:a1e0::/48';
const TS_CGNAT_V4 = '100.64.0.0/10';

const cfg = {
	interval: 30,
	table: 52,
	iface: 'tailscale0',
	rule_base: 5200,
	debug: 0
};

const state = {
	miss: 0,
	last_heal: 0,
	last_flap: 0,
	last_log: 0
};

let logf = open('/dev/stderr', 'a');

function log(lvl, msg) {
	if (logf) {
		logf.write('ts-watchdog: ' + lvl + ': ' + msg + '\n');
	}
}

/* Verbose diagnostics, off by default (uci: option debug '1'). */
function dbg(msg) {
	if (cfg.debug)
		log('debug', msg);
}

function load_config() {
	try {
		let cur = uci.cursor();
		let g = function(k, d) {
			let v = cur.get('tswatchdog', 'config', k);
			return (v == null) ? d : v;
		};
		cfg.interval = int(g('interval', cfg.interval)) || cfg.interval;
		cfg.table = int(g('table', cfg.table)) || cfg.table;
		cfg.iface = g('iface', cfg.iface);
		cfg.rule_base = int(g('rule_base', cfg.rule_base)) || cfg.rule_base;
		cfg.debug = int(g('debug', cfg.debug)) || 0;
	} catch (e) {
		log('info', 'uci config unavailable, using defaults: ' + e);
	}
}

/* ------------------------------------------------------------------ */
/* ip rules                                                            */
/* ------------------------------------------------------------------ */

function expected_rules() {
	let b = cfg.rule_base;
	let t = cfg.table;

	return [
		{ prio: b + 10, mark: true,  table: 254, action: FR_ACT_TO_TBL },       // bypass -> main
		{ prio: b + 30, mark: true,  table: 253, action: FR_ACT_TO_TBL },       // bypass -> default
		{ prio: b + 50, mark: true,  table: null, action: FR_ACT_UNREACHABLE }, // bypass -> unreachable
		{ prio: b + 70, mark: false, table: t,   action: FR_ACT_TO_TBL }        // overlay -> table 52
	];
}

function fix_rules() {
	for (let fam in [AF_INET, AF_INET6]) {
		let rules = rtnl.request(RTM_GETRULE, NLM_F_DUMP, { family: fam }) ?? [];
		let have = {};

		for (let r in rules)
			if (r.priority != null)
				have[r.priority] = true;

		for (let e in expected_rules()) {
			if (have[e.prio]) {
				dbg('rule ' + e.prio + ' present');
				continue;
			}

			dbg('rule ' + e.prio + ' MISSING, re-adding');

			let attrs = { family: fam, priority: e.prio, action: e.action };
			if (e.mark) {
				attrs.fwmark = TS_MARK;
				attrs.fwmask = TS_MARK_MASK;
			}
			if (e.table != null)
				attrs.table = e.table;

			rtnl.request(RTM_NEWRULE, NLM_F_CREATE | NLM_F_EXCL, attrs);
			let err = rtnl.error();
			if (err)
				log('warn', 'rule add prio ' + e.prio + ' failed: ' + err);
			else
				log('info', 're-added missing ip rule prio ' + e.prio);
		}
	}
}

/* ------------------------------------------------------------------ */
/* tailscale state                                                     */
/* ------------------------------------------------------------------ */

function read_json_cmd(sub) {
	let p = popen('tailscale debug ' + sub + ' 2>/dev/null');
	if (!p) {
		dbg(sub + ': popen failed');
		return null;
	}

	let out = p.read('all');
	p.close();

	if (!out) {
		dbg(sub + ': empty output');
		return null;
	}

	// Tolerate any log noise before the JSON document.
	let pos = length(split(out, '{')[0]);
	if (pos >= length(out)) {
		dbg(sub + ': no JSON document in output (' + length(out) + ' bytes)');
		return null;
	}

	try {
		let data = json(substr(out, pos));
		dbg(sub + ': parsed ok (' + length(out) + ' bytes, noise prefix ' + pos + ')');
		return data;
	} catch (e) {
		dbg(sub + ': JSON parse failed: ' + e);
		return null;
	}
}

function prefs_exit_selected(prefs) {
	let id = prefs.ExitNodeID;
	let ip = prefs.ExitNodeIP;

	if (type(id) == 'string' && length(id) > 0 && id != 'unset')
		return true;

	if (type(ip) == 'string' && length(ip) > 0 && ip != 'invalid')
		return true;

	return false;
}

/* iface_up - true when cfg.iface exists and carries IFF_UP (0x1).
 * Note: /sys/class/net/<tun>/operstate reads "unknown" for tun devices,
 * so operstate cannot be used; use the link flags via rtnl instead. */
function iface_up() {
	let links = rtnl.request(RTM_GETLINK, NLM_F_DUMP, {}) ?? [];

	for (let l in links) {
		if (l.ifname != cfg.iface)
			continue;

		return ((int(l.flags, 16) ?? l.flags) & 1) != 0;
	}

	return false;
}

/* in_cgnat("100.101.2.3") - true when the address is inside 100.64/10 */
function in_cgnat(addr) {
	let o = split(addr, '.');
	if (length(o) != 4)
		return false;

	let a = int(o[0]), b = int(o[1]);
	if (a == null || b == null)
		return false;

	return (a == 100 && b >= 64 && b < 128);
}

/* Compute the desired table 52 prefixes from tailscale's own view.
 * Mirrors net/routemanager's OS route set:
 *   - per-peer CGNAT /32s (or the coarse 100.64/10 aggregate)
 *   - the ULA aggregate /48 when any v6 peer route exists
 *   - subnet routes of peers we are primary for, when RouteAll is set
 *   - 0.0.0.0/0 and ::/0 whenever an exit node is selected (they stay
 *     installed to blackhole rather than leak, per routemanager)
 */
function desired_set(prefs, nm) {
	let want = { v4: {}, v6: {} };
	let peers = (nm.Peers != null) ? nm.Peers : [];
	let selfID = (nm.SelfNode != null) ? nm.SelfNode.ID : null;
	let have6 = false;

	for (let p in peers) {
		if (selfID != null && p.ID == selfID)
			continue;

		for (let a in (p.Addresses ?? [])) {
			if (type(a) != 'string')
				continue;

			if (in_cgnat(split(a, '/')[0]))
				want.v4[a] = true;
			else if (match(a, /:/) != null)
				have6 = true;
		}

		if (prefs.RouteAll) {
			for (let pr in (p.PrimaryRoutes ?? [])) {
				if (type(pr) != 'string')
					continue;

				if (match(pr, /:/) == null)
					want.v4[pr] = true;
				else
					have6 = true;
			}
		}
	}

	if (prefs_exit_selected(prefs)) {
		want.v4['0.0.0.0/0'] = true;
		want.v6['::/0'] = true;
	}

	if (have6)
		want.v6[TS_ULAGR_V6] = true;

	dbg('desired: peers=' + length(peers) + ' selfID=' + selfID + ' have6=' + have6 +
		' v4=[' + join(' ', keys(want.v4)) + '] v6=[' + join(' ', keys(want.v6)) + ']');

	return want;
}

/* ------------------------------------------------------------------ */
/* actual routes                                                       */
/* ------------------------------------------------------------------ */

function actual_routes() {
	let act = { v4: {}, v6: {} };

	for (let fam in [AF_INET, AF_INET6]) {
		let rs = rtnl.request(RTM_GETROUTE, NLM_F_DUMP, { family: fam }) ?? [];

		for (let r in rs) {
			if (r.table != cfg.table)
				continue;

			// unicast only (type 1); skip local/broadcast/etc if present
			if (r.type != null && r.type != 1)
				continue;

			let key = (r.dst == null) ? ((fam == AF_INET) ? '0.0.0.0/0' : '::/0') : r.dst;

			if (fam == AF_INET)
				act.v4[key] = true;
			else
				act.v6[key] = true;
		}
	}

	dbg('actual: v4=[' + join(' ', keys(act.v4)) + '] v6=[' + join(' ', keys(act.v6)) + ']');

	return act;
}

function diff(want, act) {
	let missing = { v4: [], v6: [] };
	let coarse = act.v4[TS_CGNAT_V4];

	dbg('diff: coarse=' + coarse);

	for (let k in keys(want.v4)) {
		// coarse mode: individual CGNAT /32s are replaced by the /10
		if (coarse && in_cgnat(split(k, '/')[0])) {
			dbg('diff: ' + k + ' skipped (coarse aggregate present)');
			continue;
		}

		if (!act.v4[k])
			push(missing.v4, k);
	}

	for (let k in keys(want.v6)) {
		// the /48 aggregate is what routemanager tracks; a per-peer v6
		// route missing while the aggregate is present is not an error
		if (k != TS_ULAGR_V6 && act.v6[TS_ULAGR_V6]) {
			dbg('diff: ' + k + ' skipped (ULA aggregate present)');
			continue;
		}

		if (!act.v6[k])
			push(missing.v6, k);
	}

	dbg('diff: missing v4=[' + join(' ', missing.v4) + '] v6=[' + join(' ', missing.v6) + ']');

	return missing;
}

/* ------------------------------------------------------------------ */
/* healing                                                             */
/* ------------------------------------------------------------------ */

function add_route(dst, fam) {
	rtnl.request(RTM_NEWROUTE, NLM_F_CREATE | NLM_F_REPLACE, {
		family: fam,
		// RTN_UNICAST; the rtnl mod leaves rtm_type unset, and the
		// kernel rejects RTM_NEWROUTE with EINVAL when it is 0.
		type: 1,
		table: cfg.table,
		dst: dst,
		oif: cfg.iface
	});

	let err = rtnl.error();
	if (err)
		log('warn', 'direct add ' + dst + ' failed: ' + err);
	else
		log('info', 'directly re-added ' + dst + ' to table ' + cfg.table);
}

function readd_missing(miss) {
	for (let k in miss.v4)
		add_route(k, AF_INET);

	for (let k in miss.v6)
		add_route(k, AF_INET6);
}

function heal(miss, now) {
	if (now - state.last_heal >= 60) {
		log('info', 'missing routes: ' + join(' ', miss.v4) + ' ' + join(' ', miss.v6) +
			' (streak ' + state.miss + ') - re-adding desired routes and forcing netmap update');

		/* Re-add the routes that tailscale's own view still wants.
		 * The desired set is derived from the live netmap/prefs, not a
		 * cached copy: when the control plane withdraws a route (peer
		 * left, subnet route removed, exit node disabled), it drops out
		 * of the desired set at the next netmap refresh and we stop
		 * enforcing it. force-netmap-update alone cannot restore a
		 * wiped table - tailscaled only re-applies routes when a
		 * received netmap differs from the previous one, and a re-sent
		 * identical netmap is a no-op. */
		readd_missing(miss);

		system('tailscale debug force-netmap-update >/dev/null 2>&1');
		state.last_heal = now;
	} else {
		dbg('heal: rate-limited (' + (now - state.last_heal) + 's since last)');
	}

	if (state.miss >= 5 && now - state.last_flap >= 300) {
		log('warn', 'table ' + cfg.table + ' still broken after heal attempts - bouncing ' +
			cfg.iface + ' to force full re-sync');
		system('ip link set ' + cfg.iface + ' down');
		/* A real 1 s gap is essential: ucode's sleep() is
		 * milliseconds-based in the ucode 2026.01.16 frozen for
		 * openwrt-25.12 (sleep(3) is 3 ms), so a bare sleep(1) used
		 * to make this a 0 ms down/up that raced tailscaled without
		 * forcing a resync. */
		sleep(1000);
		system('ip link set ' + cfg.iface + ' up');
		/* A bounce flushes the whole table and tailscaled does not
		 * reliably re-apply its v4 routes afterwards, so restore the
		 * desired set directly instead of trusting the resync. */
		readd_missing(miss);
		state.last_flap = now;
		state.miss = 0;
	} else if (state.miss >= 5) {
		dbg('flap rate-limited (' + (now - state.last_flap) + 's since last, min 300s)');
	}
}

/* ------------------------------------------------------------------ */
/* main loop                                                           */
/* ------------------------------------------------------------------ */

function cycle() {
	if (system('pidof tailscaled >/dev/null 2>&1') != 0) {
		dbg('cycle: tailscaled not running, skipping');
		state.miss = 0;
		return;
	}

	if (!iface_up()) {
		dbg('cycle: ' + cfg.iface + ' not present or not IFF_UP, skipping');
		state.miss = 0;
		return;
	}

	fix_rules();

	let prefs = read_json_cmd('prefs');
	let nm = read_json_cmd('netmap');
	if (prefs == null || nm == null) {
		dbg('cycle: prefs or netmap unavailable, skipping diff');
		return;
	}

	// Without a valid self node the peer set cannot be trusted; skip
	// rather than risk demanding routes tailscale intentionally omits.
	if (nm.SelfNode == null) {
		dbg('cycle: netmap has no SelfNode, skipping diff');
		return;
	}

	let want = desired_set(prefs, nm);
	let act = actual_routes();
	let miss = diff(want, act);

	if (length(miss.v4) == 0 && length(miss.v6) == 0) {
		dbg('cycle: ok, nothing missing');
		state.miss = 0;
		return;
	}

	state.miss++;
	dbg('cycle: miss streak now ' + state.miss);
	heal(miss, time());
}

load_config();

if (cfg.interval < 5)
	cfg.interval = 5;

log('info', 'started (interval=' + cfg.interval + 's table=' + cfg.table +
	' iface=' + cfg.iface + ' rule_base=' + cfg.rule_base +
	' debug=' + cfg.debug + ')');

while (true) {
	try {
		cycle();
	} catch (e) {
		log('warn', 'cycle error: ' + e);
	}

	/* ucode's sleep() is milliseconds-based in the ucode 2026.01.16
	 * frozen for openwrt-25.12 (sleep(3) is 3 ms, not the seconds the
	 * stdlib doc claims), which used to turn this loop into a busy
	 * spin - one localapi poll pair per ~200 ms, syslog flooded, and
	 * every rate limiter in the heal path useless. */
	sleep(cfg.interval * 1000);
}
