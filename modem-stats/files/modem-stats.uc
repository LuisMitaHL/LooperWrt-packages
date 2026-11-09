#!/usr/bin/env ucode
//
// modem-stats - Huawei HiLink modem statistics collector.
//
// Polls a Huawei HiLink modem-router (verified against the E5576-508,
// fw 11.0.1.1(H697SP3C266)) over its XML-over-HTTP API and publishes the
// collected data as:
//   * a JSON snapshot in /tmp/modem-stats.json, and
//   * a ubus object "modem-stats" (method "all" returns the snapshot,
//     "refresh" forces an immediate poll).
//
// Login is the firmware's SCRAM flow (password_type=4, EMUI webui 6.0):
//   1. GET  /api/webserver/SesTokInfo        -> SesInfo cookie + TokInfo
//   2. POST /api/user/challenge_login        -> salt, iterations, servernonce
//      + __RequestVerificationToken response header (use THIS one for the
//      authentication_login call; using the SesTokInfo token yields 125003)
//   3. POST /api/user/authentication_login   -> SessionID cookie +
//      __RequestVerificationTokenone/Tokentwo headers (use TokenOne for all
//      subsequent calls)
//
// The HMAC construction is Huawei's non-RFC SCRAM variant: the client
// signature is hmac(auth_message, stored_key) (message first), and the
// server signature is hmac(auth_message, hmac("Server Key", salted_pw)).
//
// Session keep-alive: POST /api/user/heartbeat every poll cycle, and a full
// re-login on any 125002 (not logged in) or 125003 (wrong session token).
//
// Pure ucode; HTTP over ucode-mod-socket. No subprocesses at runtime.

'use strict';

const fs = require('fs');
const socket = require('socket');
const uci = require('uci');
const ubus = require('ubus');
const digest = require('digest');

const SNAPFILE = '/tmp/modem-stats.json';

// ---------------------------------------------------------------- config

let cfg_host = '192.168.8.1';
let cfg_password = '';
let cfg_interval = 30;

function load_config() {
	// optional confdir override (mostly for testing; production uses /etc/config)
	const confdir = getenv('MODEM_STATS_UCI_DIR');
	const ctx = (confdir != null && confdir != '') ? uci.cursor(confdir) : uci.cursor();
	cfg_host = ctx.get('modem-stats', 'config', 'host') || cfg_host;
	cfg_password = ctx.get('modem-stats', 'config', 'password') || '';
	const iv = +ctx.get('modem-stats', 'config', 'interval');
	if (iv >= 5)
		cfg_interval = iv;
}

// ------------------------------------------------------------------ http

function find_from(s, needle, from) {
	// ucode index() ignores its start-offset arg; scan manually.
	if (from < 0)
		from = 0;
	const n = length(needle);
	for (let i = from; i <= length(s) - n; i++)
		if (substr(s, i, n) == needle)
			return i;
	return -1;
}

function http_request(method, path, body, headers) {
	headers = headers || {};
	const s = socket.create(socket.AF_INET, socket.SOCK_STREAM, 0);
	if (s == null)
		return null;

	if (!s.connect(getenv('MS_PROXY') || cfg_host, +(getenv('MS_PROXY_PORT') || 80))) {
		s.close();
		return null;
	}

	let req = method + ' ' + path + ' HTTP/1.1\r\n' +
		'Host: ' + cfg_host + '\r\n' +
		'User-Agent: modem-stats/1.0\r\n' +
		'Connection: close\r\n';

	for (let k in headers)
		req += k + ': ' + headers[k] + '\r\n';

	if (body != null) {
		req += 'Content-Type: application/xml\r\n';
		req += 'Content-Length: ' + length(body) + '\r\n';
	}
	req += '\r\n';
	if (body != null)
		req += body;

	s.send(req);

	let buf = '';
	while (1) {
		const pr = socket.poll(3000, s);
		// poll returns [ [socket, revents], ... ] or null on error
		if (pr == null || length(pr) == 0)
			break;
		const revents = pr[0][1];
		if (!(revents & socket.POLLIN))
			break;
		const chunk = s.recv(4096);
		if (chunk == null || length(chunk) == 0)
			break;
		buf += chunk;
	}
	s.close();

	const se = index(buf, '\r\n\r\n');
	if (se < 0)
		return null;

	const head = substr(buf, 0, se);
	let data = substr(buf, se + 4);

	// handle chunked transfer encoding
	if (match(lc(head), /transfer-encoding: chunked/)) {
		let out = '';
		let pos = 0;
		while (pos < length(data)) {
			const nl = find_from(data, '\r\n', pos);
			if (nl < 0)
				break;
			const sz = parseInt(substr(data, pos, nl - pos), 16);
			if (!sz)
				break;
			out += substr(data, nl + 2, sz);
			pos = nl + 2 + sz + 2;
		}
		data = out;
	}

	const sm = match(head, /^HTTP\/1\.[01] (\d+)/);
	const status = sm ? +sm[1] : 0;
	return { status: status, body: data, headers: head, lheaders: lc(head) };
}

function header_get(headers, name) {
	// headers: raw header block; name: lowercase header name (lookup is case-insensitive).
	// note: ucode's index() takes no start offset, so scan manually.
	const needle = lc(name) + ':';
	const lh = lc(headers);
	let pos = -1;
	let scan = 0;
	while (1) {
		const f = find_from(lh, needle, scan);
		if (f < 0)
			break;
		// must be at line start
		if (f == 0 || substr(lh, f - 1, 1) == '
') {
			pos = f;
			break;
		}
		scan = f + 1;
	}
	if (pos < 0)
		return null;
	let eol = find_from(headers, '
', pos);
	if (eol < 0)
		eol = length(headers);
	let val = trim(substr(headers, pos + length(needle), eol - pos - length(needle)));
	while (length(val) > 0 && substr(val, length(val) - 1, 1) == '')
		val = substr(val, 0, length(val) - 1);
	return val;
}


function xml_get(xml, tag) {
	const open = '<' + tag + '>';
	const close = '</' + tag + '>';
	const a = index(xml, open);
	if (a < 0)
		return null;
	const b = find_from(xml, close, a);
	if (b < 0)
		return null;
	return substr(xml, a + length(open), b - a - length(open));
}

// ------------------------------------------------------------------ auth
//
// digest.sha256() returns a 64-char hex STRING (not raw bytes), and the
// digest module has no hmac(), so HMAC-SHA256/PBKDF2 are implemented here
// in pure ucode on top of digest.sha256 (validated against Python's
// hashlib.pbkdf2_hmac / hmac - byte-exact match).

const HEXD = '0123456789abcdef';

function hexdec_fast(h) {
	let out = '';
	for (let i = 0; i < length(h); i += 2)
		out += chr(index(HEXD, substr(h, i, 1)) * 16 + index(HEXD, substr(h, i + 1, 1)));
	return out;
}

function hexenc(b) {
	let o = '';
	for (let i = 0; i < length(b); i++)
		o += sprintf('%02x', ord(substr(b, i, 1)));
	return o;
}

function xor_str(a, b) {
	let out = '';
	for (let i = 0; i < length(a); i++)
		out += chr(ord(substr(a, i, 1)) ^ ord(substr(b, i, 1)));
	return out;
}

function hexdec(h) {
	let out = '';
	for (let i = 0; i < length(h); i += 2)
		out += chr(ord(substr(h, i, 1)) * 16 + index(HEXD, substr(h, i + 1, 1)));
	return out;
}

function hmac_sha256(key, msg) {
	let k = key;
	if (length(k) > 64)
		k = hexdec_fast(digest.sha256(k));
	while (length(k) < 64)
		k += chr(0);
	let ipad = '';
	let opad = '';
	for (let i = 0; i < 64; i++) {
		ipad += chr(ord(substr(k, i, 1)) ^ 0x36);
		opad += chr(ord(substr(k, i, 1)) ^ 0x5c);
	}
	return hexdec_fast(digest.sha256(opad + hexdec_fast(digest.sha256(ipad + msg))));
}

function xml_err_code(body) {
	const m = match(body, /<code>(\d+)<\/code>/);
	return m ? m[1] : null;
}

// ----------------------------------------------------------------- SCRAM
//
// Huawei's SCRAM variant (verified against the device's own
// /lib/emui-jquery.js, SCRAMJS v1.0.1): unlike RFC 5802, the HMAC
// argument order is swapped -- the constant/user data is the KEY:
//   clientKey  = hmac("Client Key",  saltedPassword)
//   serverKey  = hmac("Server Key",  saltedPassword)
//   storedKey  = sha256(clientKey)
//   clientSig  = hmac(authMessage,   storedKey)
//   serverSig  = hmac(authMessage,   serverKey)
//   clientProof = clientKey XOR clientSig   (hex lowercase)
// saltedPassword = PBKDF2-SHA256(password, salt, iterations, 32 bytes).

const state = {
	cookie: null,
	token: null,
	logged_in: false,
	snapshot: {},
	slow_counter: 0,
	ubus_conn: null
};

let nonce_ctr = 0;
function nonce_hex() {
	// 64 hex chars of randomness (32 bytes); digest.sha256 already returns hex
	let out = '';
	for (let i = 0; i < 8; i++)
		out += digest.sha256(sprintf('%s.%d.%d', time(), nonce_ctr++, i));
	return substr(out, 0, 64);
}

function pbkdf2_sha256(password, salt, iterations) {
	// single block (32 bytes = 1 block for SHA-256)
	let u = hmac_sha256(password, salt + chr(0) + chr(0) + chr(0) + chr(1));
	let acc = u;
	for (let i = 1; i < iterations; i++) {
		u = hmac_sha256(password, u);
		acc = xor_str(acc, u);
	}
	return acc;
}

function scram_login() {
	// 1. session + token
	const s = http_request('GET', '/api/webserver/SesTokInfo', null, {});
	if (s == null || s.status != 200)
		return false;
	const sesinfo = xml_get(s.body, 'SesInfo');
	const tokinfon = xml_get(s.body, 'TokInfo');
	if (sesinfo == null || tokinfon == null)
		return false;

	const firstnonce = nonce_hex();
	const H0 = { 'Cookie': sesinfo, '__RequestVerificationToken': tokinfon };

	// 2. challenge
	const cbody = '<?xml version="1.0" encoding="UTF-8"?>' +
		'<request><username>admin</username>' +
		'<firstnonce>' + firstnonce + '</firstnonce>' +
		'<mode>1</mode></request>';
	const ch = http_request('POST', '/api/user/challenge_login', cbody, H0);
	if (ch == null || ch.status != 200 || xml_err_code(ch.body) != null)
		return false;
	const salt = xml_get(ch.body, 'salt');
	const servernonce = xml_get(ch.body, 'servernonce');
	const iters = +(xml_get(ch.body, 'iterations') || '1000');
	const ctoken = header_get(ch.headers, '__requestverificationtoken');
	if (salt == null || servernonce == null || ctoken == null)
		return false;

	// authMessage = firstnonce,servernonce,finalnonce (finalnonce = servernonce)
	const authmsg = firstnonce + ',' + servernonce + ',' + servernonce;
	const sp = pbkdf2_sha256(cfg_password, hexdec_fast(salt), iters);

	const clientkey = hmac_sha256('Client Key', sp);
	const storedkey = hexdec_fast(digest.sha256(clientkey));
	const clientsig = hmac_sha256(authmsg, storedkey);
	const clientproof = hexenc(xor_str(clientkey, clientsig));

	const serverkey = hmac_sha256('Server Key', sp);
	const serverproof = hexenc(hmac_sha256(authmsg, serverkey));

	// 3. authentication
	const abody = '<?xml version="1.0" encoding="UTF-8"?>' +
		'<request><clientproof>' + clientproof + '</clientproof>' +
		'<finalnonce>' + servernonce + '</finalnonce></request>';
	const au = http_request('POST', '/api/user/authentication_login', abody,
		{ 'Cookie': sesinfo, '__RequestVerificationToken': ctoken });
	if (au == null || au.status != 200 || xml_err_code(au.body) != null)
		return false;

	const serversig = xml_get(au.body, 'serversignature');
	if (serversig == null || serversig != serverproof)
		return false;

	const newcookie = header_get(au.headers, 'set-cookie');
	const tokenlist = header_get(au.headers, '__requestverificationtoken');
	if (newcookie == null || tokenlist == null)
		return false;

	state.cookie = substr(newcookie, 0, index(newcookie, ';') >= 0
		? index(newcookie, ';') : length(newcookie));
	state.token = tokenlist;
	state.logged_in = true;
	return true;
}

// ----------------------------------------------------------------- state


function session_get(path) {
	if (!state.logged_in && !scram_login())
		return null;

	let r = http_request('GET', path, null,
		{ 'Cookie': state.cookie, '__RequestVerificationToken': state.token });

	if (r == null)
		return null;

	const code = xml_err_code(r.body);
	if (code == '125002' || code == '125003') {
		state.logged_in = false;
		if (!scram_login())
			return null;
		r = http_request('GET', path, null,
			{ 'Cookie': state.cookie, '__RequestVerificationToken': state.token });
	}

	return r;
}

// --------------------------------------------------------------- polling

// Endpoints polled every cycle (cheap single GETs, all verified live).
const EP_FAST = [
	'/api/device/signal',
	'/api/monitoring/status',
	'/api/monitoring/traffic-statistics',
	'/api/monitoring/check-notifications',
	'/api/sms/sms-count'
];

// Endpoints polled every 10th cycle (slow-changing identity/config data).
const EP_SLOW = [
	'/api/device/information',
	'/api/net/current-plmn',
	'/api/dialup/mobile-dataswitch',
	'/api/wlan/basic-settings',
	'/api/wlan/host-list',
	'/api/pin/status',
	'/api/monitoring/start_date',
	'/api/global/module-switch',
	'/api/dialup/connection',
	'/api/net/net-mode-list'
];



function xml_to_map(xml) {
	const map = {};
	let pos = 0;
	while (1) {
		const a = find_from(xml, '<', pos);
		if (a < 0)
			break;
		const b = find_from(xml, '>', a);
		if (b < 0)
			break;
		const tag = substr(xml, a + 1, b - a - 1);
		// skip declarations, wrappers, closing and self-closing tags
		const c0 = substr(tag, 0, 1);
		const cN = substr(tag, length(tag) - 1, 1);
		if (length(tag) < 1 || c0 == '?' || c0 == '/' || cN == '/') {
			pos = b + 1;
			continue;
		}
		let tagname = (index(tag, ' ') > 0) ? substr(tag, 0, index(tag, ' ')) : tag;
		// skip wrapper elements (response/request): don't store them, just advance
		if (tagname == 'response' || tagname == 'request') {
			const wclose = '</' + tagname + '>';
			const wc = find_from(xml, wclose, b);
			if (wc < 0)
				break;
			pos = b + 1;
			continue;
		}
		const closing = '</' + tagname + '>';
		const c = find_from(xml, closing, b);
		if (c < 0)
			break;
		map[tagname] = substr(xml, b + 1, c - b - 1);
		pos = c + length(closing);
	}
	return map;
}

function snapkey(path) {
	// '/api/monitoring/status' -> 'monitoring/status'; '/api/pin/status' -> 'pin/status'
	// (both would collapse to 'status' with plain basename and clobber each other)
	let k = path;
	if (substr(k, 0, 5) == '/api/')
		k = substr(k, 5);
	return k;
}

function pick(map, key) {
	return (map != null && key in map) ? map[key] : null;
}

function poll_once() {
	const snap = { time: time(), host: cfg_host };

	// heartbeat: keep the HiLink session alive (POST without token use is
	// fine; it neither consumes the token nor needs rights)
	http_request('POST', '/api/user/heartbeat', null,
		{ 'Cookie': state.cookie, '__RequestVerificationToken': state.token });

	for (let path in EP_FAST) {
		const r = session_get(path);
		if (r == null || r.status != 200 || xml_err_code(r.body) != null)
			continue;
		snap[snapkey(path)] = xml_to_map(r.body);
	}

	state.slow_counter++;
	if (state.slow_counter >= 10) {
		state.slow_counter = 0;
		for (let path in EP_SLOW) {
			const r = session_get(path);
			if (r == null || r.status != 200 || xml_err_code(r.body) != null)
				continue;
			snap[snapkey(path)] = xml_to_map(r.body);
		}
		// merge into last snapshot so the slow data survives in the file
		for (let k in state.snapshot)
			if (!(k in snap))
				snap[k] = state.snapshot[k];
	}
	else {
		// carry over slow data from the previous snapshot
		for (let k in state.snapshot) {
			if (!(k in snap))
				snap[k] = state.snapshot[k];
		}
	}

	// convenience top-level shortcuts (battery etc. from monitoring/status)
	const st = pick(snap, 'monitoring/status');
	if (st != null) {
		snap.battery = {
			percent: +pick(st, 'BatteryPercent') || null,
			level: +pick(st, 'BatteryLevel') || null,
			status: pick(st, 'BatteryStatus'),
			hvdcp_online: pick(st, 'hvdcp_online')
		};
		snap.wifi_users = +pick(st, 'CurrentWifiUser') || null;
		snap.signal_icon = +pick(st, 'SignalIcon') || null;
		snap.connection_status = pick(st, 'ConnectionStatus');
	}

	state.snapshot = snap;

	const f = fs.open(SNAPFILE, 'w');
	if (f != null) {
		f.write(sprintf('%J\n', snap));
		f.close();
	}
}

// ------------------------------------------------------------------ main

load_config();

if (!cfg_password) {
	warn('modem-stats: no password configured (uci modem-stats.config.password)\n');
	exit(1);
}

const conn = ubus.connect();
if (conn != null) {
	conn.publish('modem-stats', {
		all: {
			call: function(req) {
				conn.reply(req, state.snapshot);
			}
		},
		refresh: {
			call: function(req) {
				poll_once();
				conn.reply(req, state.snapshot);
			}
		}
	});
}

while (1) {
	poll_once();
	sleep(cfg_interval);
}
