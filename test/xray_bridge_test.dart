import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobin_vpn/core/singbox_outbound.dart';
import 'package:mobin_vpn/core/xray_bridge.dart';

void main() {
  test('vless xhttp reality -> Xray outbound', () {
    const link = 'vless://11111111-1111-1111-1111-111111111111@1.2.3.4:443?type=xhttp&security=reality'
        '&sni=a.com&fp=firefox&pbk=KEY&sid=ab&path=%2Fx&mode=packet-up&host=h.com#x';
    expect(isXhttpLink(link), isTrue);
    expect(parseOutbound(link), isNull); // sing-box 1.12 cannot dial it
    final o = xrayOutbound(link)!;
    expect(o['protocol'], 'vless');
    expect(o['settings']['vnext'][0]['users'][0]['encryption'], 'none');
    final stream = o['streamSettings'] as Map;
    expect(stream['network'], 'xhttp');
    expect(stream['xhttpSettings'], {'path': '/x', 'mode': 'packet-up', 'host': 'h.com'});
    expect(stream['realitySettings']['publicKey'], 'KEY');
    expect(stream['realitySettings']['fingerprint'], 'firefox');
  });

  test('trojan and vmess xhttp with tls; non-xhttp links are ignored', () {
    final t = xrayOutbound('trojan://pw@t.com:443?type=xhttp&sni=s.com&alpn=h2#t')!;
    expect(t['settings']['servers'][0]['password'], 'pw');
    expect(t['streamSettings']['tlsSettings']['serverName'], 's.com');
    expect(t['streamSettings']['tlsSettings']['alpn'], ['h2']);
    final vmess = base64.encode(utf8.encode(jsonEncode(
        {'add': 'v.com', 'port': '443', 'id': 'uuid', 'net': 'xhttp', 'path': '/v', 'tls': 'tls', 'ps': 'n'})));
    final v = xrayOutbound('vmess://$vmess')!;
    expect([v['protocol'], v['streamSettings']['xhttpSettings']['path']], ['vmess', '/v']);
    expect(xrayOutbound('vless://11111111-1111-1111-1111-111111111111@1.2.3.4:443?type=ws'), isNull);
    expect(xrayOutbound('vless://u@1.2.3.4:443?type=xhttp&security=reality'), isNull); // no public key
  });
}
