#!/usr/bin/ucode
/* ts-watchdog cycle - ONE-SHOT watchdog cycle for Tailscale's policy
 * routing rules and routing table (default 52) on OpenWrt.
 *
 * Runs once per invocation; a busybox-sh supervisor (ts-watchdog) loops
 * it on the configured interval under procd. One-shot on purpose:
 * a long-lived interpreter accumulating state across cycles turned out
 * to be fragile (any internal failure takes down all future cycles and
 * resets every rate limiter), while a per-cycle process contains any
 * failure - it is logged, retried next interval, and costs a few ms of
 * interpreter startup against the ~0.5 s tailscale fork.
 *
 * On mwan3/netifd-heavy routers, tailscaled's table 52 routes can end up
 * wiped (its own reconcile races netlink churn, or the tun device flaps)
 * while tailscaled considers its state fine and never re-applies them.
 * The ip rules at the 52xx base are self-healed by tailscaled >= 1.102
 * (netmon.RuleDeleted handler), but table 52 routes are not. During such
 * churn storms tailscaled's reconcile can also wipe freshly re-added
 * routes again; convergence is by repeated heals and the flap escalation
 * below.
 *
 * Strategy (dl12345/mwan3-tailscale-setup compatible: mwan3 priority bases
 * at 1100/1200 mean tailscale installs at its default 5200 base):
 *
 *   - verify the 4 policy rules per family (base+10/+30/+50/+70), re-add
 *     if missing (idempotent, NLM_F_EXCL)
 *   - derive the *desired* table 52 content from tailscale's own view:
 *     `tailscale status --json` (peer addresses, primary subnet routes,
 *     exit node selection) - a stable CLI surface; no `tailscale debug`
 *     endpoints
 *   - diff desired vs actual (netlink dump of the table)
 *   - re-add the missing desired routes directly via netlink (the
 *     desired set comes from tailscale's live view, not a cache, so
 *     control-plane deletions (peer left, subnet route withdrawn, exit
 *     node disabled) are never fought)
 *   - also trigger `tailscale debug force-netmap-update`, which makes
 *     tailscaled re-apply its routes only when the netmap actually
 *     changed - a re-sent identical netmap is a no-op (the only debug
 *     command left in the script; there is no stable equivalent)
 *   - last-resort escalation only: a rate-limited tailscale0 down/up
 *     with a real 1 s gap, followed by directly re-adding the desired
 *     routes (a bounce flushes the table and tailscaled does not
 *     reliably re-apply its v4 routes afterwards)
 *
 * CPU budget: this script is built for CPU-limited routers. The cheap
 * path of a cycle is forkless (procfs/sysfs reads and two small netlink
 * dumps) and compares the actual table 52 content against the snapshot
 * from the previous cycle; the expensive path (one `tailscale status
 * --json` fork, ~0.5 s, 59 KB parse) only runs when the snapshot or the
 * rules changed, when the previous cycle found missing routes, or every
 * `refresh` cycles as a staleness bound. In a healthy steady state that
 * is one status fork per refresh*interval seconds instead of per
 * interval.
 *
 * Cross-cycle state (miss streak, heal/flap rate limiters, table
 * snapshot, cycle counter) lives in /tmp/tswatchdog.state so the
 * one-shot stays stateless and rate limiters survive supervisor
 * restarts. /tmp is tmpfs: state resets on reboot, which just means the
 * first cycle after boot does a full check.
 *
 * Logs via logger(1) into syslog (daemon facility). One fork per logged
 * line; healthy cycles log nothing. */

'use strict';

import * as rtnl from 'rtnl';
import * as uci from 'uci';
import { open, popen, lsdir, readfile, rename } from 'fs';

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
/* Tailscale's resolver addresses are always routed to tailscale0 -
 * observed installed with CorpDNS off, so treated as unconditional.
 * fd7a:115c:a1e0::53 is the v6 counterpart of quad-100 (belongs to no
 * peer; verified against a live netmap). */
const TS_QUAD100_V4 = '100.100.100.100/32';
const TS_RESOLVER_V6 = 'fd7a:115c:a1e0::53/128';

const STATE_FILE = '/tmp/tswatchdog.state';

const cfg = {
	table: 52,
	iface: 'tailscale0',
	rule_base: 5200,
	accept_routes: 1,
	refresh: 20,
	debug: 0
};

/* Cross-cycle state; persisted to STATE_FILE as JSON. */
let state = {
	miss: 0,
	last_heal: 0,
	last_flap: 0,
	cycle: 0,
	snap: null
};

function log(lvl, msg) {
	/* strip anything that would break the shell quoting */
	let clean = replace(replace(msg, '"', "'"), '`', "'");
	let pri = (lvl == 'warn') ? 'warning' : lvl;
	system('logger -t ts-watchdog -p daemon.' + pri + " '" + clean + "'");
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
		cfg.table = int(g('table', cfg.table)) || cfg.table;
		cfg.iface = g('iface', cfg.iface);
		cfg.rule_base = int(g('rule_base', cfg.rule_base)) || cfg.rule_base;
		cfg.accept_routes = int(g('accept_routes', cfg.accept_routes));
		cfg.accept_routes = (cfg.accept_routes == null) ? 1 : cfg.accept_routes;
		cfg.refresh = int(g('refresh', cfg.refresh)) || cfg.refresh;
		if (cfg.refresh < 1)
			cfg.refresh = 1;
		cfg.debug = int(g('debug', cfg.debug)) || 0;
	} catch (e) {
		log('info', 'uci config unavailable, using defaults: ' + e);
	}
}

function load_state() {
	try {
		let raw = readfile(STATE_FILE);
		if (raw == null || raw == '')
			return;

		let d = json(raw);
		state.miss = int(d.miss) ?? 0;
		state.last_heal = int(d.last_heal) ?? 0;
		state.last_flap = int(d.last_flap) ?? 0;
		state.cycle = int(d.cycle) ?? 0;
		state.snap = (type(d.snap) == 'string') ? d.snap : null;
	} catch (e) {
		/* unreadable state: start fresh */
		state = { miss: 0, last_heal: 0, last_flap: 0, cycle: 0, snap: null };
	}
}

function save_state() {
	try {
		/* this ucode build's json() only parses; serialize via %J */
		let blob = sprintf('%J', {
			miss: state.miss,
			last_heal: state.last_heal,
			last_flap: state.last_flap,
			cycle: state.cycle,
			snap: state.snap
		});
		let f = open(STATE_FILE + '.tmp', 'w');
		if (f == null)
			return;
		f.write(blob);
		f.close();
		rename(STATE_FILE + '.tmp', STATE_FILE);
	} catch (e) {
		dbg('save state: ' + e);
	}
}

/* tailscaled_running - pure-ucode /proc scan for a process named
 * "tailscaled", no fork. */
function tailscaled_running() {
	let dirs = lsdir('/proc') ?? [];

	for (let e in dirs) {
		/* this ucode build returns plain name strings; tolerate
		 * {name,...} objects from other versions */
		let name = (type(e) == 'object') ? e.name : e;
		if (name == null || !match(name, /^[0-9]+$/))
			continue;

		let f = open('/proc/' + name + '/comm', 'r');
		if (f == null)
			continue;

		let comm = f.read('all');
		f.close();

		if (comm != null && trim(comm) == 'tailscaled')
			return true;
	}

	return false;
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

/* fix_rules - re-add missing policy rules; returns how many were added
 * (a nonzero count hints at a netlink churn event and forces the
 * expensive check this cycle). */
function fix_rules() {
	let readded = 0;

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
			else {
				log('info', 're-added missing ip rule prio ' + e.prio);
				readded++;
			}
		}
	}

	return readded;
}

/* ------------------------------------------------------------------ */
/* tailscale state                                                     */
/* ------------------------------------------------------------------ */

function read_ts_status() {
	let p = popen('tailscale status --json 2>/dev/null');
	if (!p) {
		dbg('status: popen failed');
		return null;
	}

	let out = p.read('all');
	p.close();

	if (!out) {
		dbg('status: empty output');
		return null;
	}

	// Tolerate any log noise before the JSON document.
	let pos = length(split(out, '{')[0]);
	if (pos >= length(out)) {
		dbg('status: no JSON document in output (' + length(out) + ' bytes)');
		return null;
	}

	try {
		let data = json(substr(out, pos));
		dbg('status: parsed ok (' + length(out) + ' bytes, noise prefix ' + pos + ')');
		return data;
	} catch (e) {
		dbg('status: JSON parse failed: ' + e);
		return null;
	}
}

/* exit_node_selected - true when an exit node is in use. The top-level
 * ExitNodeStatus is documented nil when unused; fall back to the
 * per-peer ExitNode flags for builds without it. */
function exit_node_selected(st) {
	if (st.ExitNodeStatus != null)
		return true;

	if (st.Self != null && st.Self.ExitNode)
		return true;

	for (let k, p in (st.Peer ?? {}))
		if (p.ExitNode)
			return true;

	return false;
}

/* iface_up - true when cfg.iface exists and carries IFF_UP (0x1).
 * Note: /sys/class/net/<tun>/operstate reads "unknown" for tun devices,
 * so operstate cannot be used; the flags file carries the real bit. */
function iface_up() {
	let f = open('/sys/class/net/' + cfg.iface + '/flags', 'r');
	if (f != null) {
		let s = f.read('all');
		f.close();

		let m = match(s ?? '', /0x([0-9a-fA-F]+)/);
		if (m != null)
			return ((int(m[1], 16) ?? 0) & 1) != 0;

		return false;
	}

	/* sysfs unavailable: fall back to a link dump */
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

/* Compute the desired table 52 prefixes from tailscale's own view
 * (`tailscale status --json`). Mirrors net/routemanager's OS route set:
 *   - per-peer CGNAT /32s (or the coarse 100.64/10 aggregate)
 *   - the ULA aggregate /48 when any v6 peer route exists (per-peer v6
 *     /128s are not installed by tailscaled; v6 peer traffic rides the
 *     aggregate)
 *   - subnet routes of peers we are primary for, when accept-routes is
 *     on (uci option accept_routes mirrors the --accept-routes pref)
 *   - 0.0.0.0/0 and ::/0 whenever an exit node is selected (they stay
 *     installed to blackhole rather than leak, per routemanager)
 *   - the resolver routes quad-100 and fd7a:115c:a1e0::53
 */
function desired_set(st) {
	let want = { v4: {}, v6: {} };
	let peers = st.Peer ?? {};
	let have6 = false;
	let npeers = 0;

	for (let k, p in peers) {
		// key-expired peers get their routes dropped by tailscaled;
		// never demand them
		if (p.Expired) {
			dbg('desired: peer ' + p.HostName + ' expired, skipping');
			continue;
		}

		npeers++;

		for (let ip in (p.TailscaleIPs ?? [])) {
			if (type(ip) != 'string')
				continue;

			if (in_cgnat(ip))
				want.v4[ip + '/32'] = true;
			else if (match(ip, /:/) != null)
				have6 = true;
		}

		if (cfg.accept_routes) {
			for (let pr in (p.PrimaryRoutes ?? [])) {
				if (type(pr) != 'string')
					continue;

				if (match(pr, /:/) == null)
					want.v4[pr] = true;
				else {
					want.v6[pr] = true;
					have6 = true;
				}
			}
		}
	}

	if (exit_node_selected(st)) {
		want.v4['0.0.0.0/0'] = true;
		want.v6['::/0'] = true;
	}

	if (have6)
		want.v6[TS_ULAGR_V6] = true;

	want.v4[TS_QUAD100_V4] = true;
	want.v6[TS_RESOLVER_V6] = true;

	dbg('desired: peers=' + npeers + ' have6=' + have6 +
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

/* snapshot - stable fingerprint of the actual table content, for the
 * cheap change-detection pass (prefix sets only, no metric/ordering
 * noise). */
function snapshot(act) {
	return join(' ', sort(keys(act.v4))) + '|' + join(' ', sort(keys(act.v6)));
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
		 * The desired set is derived from the live status, not a
		 * cached copy: when the control plane withdraws a route (peer
		 * left, subnet route removed, exit node disabled), it drops out
		 * of the desired set at the next status refresh and we stop
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
/* cycle                                                               */
/* ------------------------------------------------------------------ */

function run_cycle() {
	state.cycle++;

	if (!tailscaled_running()) {
		dbg('cycle: tailscaled not running, skipping');
		state.miss = 0;
		return;
	}

	if (!iface_up()) {
		dbg('cycle: ' + cfg.iface + ' not present or not IFF_UP, skipping');
		state.miss = 0;
		return;
	}

	let rules_readded = fix_rules();

	/* cheap path: forkless table fingerprint against the last cycle.
	 * The expensive status fetch runs when the table or the rules
	 * changed, while a heal is still pending (miss > 0 - never let the
	 * cheap path stall the escalation), or every cfg.refresh cycles as
	 * a staleness bound (a peer joining adds desired routes without
	 * touching the table). */
	let act = actual_routes();
	let snap = snapshot(act);

	let full = (state.snap == null) ||
		(state.snap != snap) ||
		(rules_readded > 0) ||
		(state.miss > 0) ||
		((state.cycle % cfg.refresh) == 0);

	if (!full) {
		dbg('cycle: cheap pass (table unchanged), no status fetch');
		state.snap = snap;
		return;
	}

	let st = read_ts_status();
	if (st == null) {
		dbg('cycle: status unavailable, skipping diff');
		state.snap = snap;
		return;
	}

	// Without a valid self node the peer set cannot be trusted; skip
	// rather than risk demanding routes tailscale intentionally omits.
	if (st.Self == null) {
		dbg('cycle: status has no Self, skipping diff');
		state.snap = snap;
		return;
	}

	let want = desired_set(st);
	let miss = diff(want, act);

	state.snap = snap;

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
load_state();

let rc = 0;

try {
	run_cycle();
} catch (e) {
	log('warn', 'cycle error: ' + e);
	rc = 1;
}

save_state();

/* exit code lets the supervisor distinguish clean cycles from internal
 * errors (still retried either way - one-shot contains all failures) */
exit(rc);
