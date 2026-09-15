import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobin_vpn/core/outline.dart';
import 'package:mobin_vpn/core/singbox_outbound.dart';

void main() {
  test('ssconf JSON response -> SIP002 ss link', () {
    final link = OutlineKeys.ssFromResponse(
      jsonEncode({'server': '1.2.3.4', 'server_port': 8443, 'password': 'p@ss:w', 'method': 'chacha20-ietf-poly1305'}),
      name: 'My Outline',
    )!;
    expect(link, startsWith('ss://'));
    expect(link, endsWith('#My%20Outline'));
    final o = parseOutbound(link)!;
    expect([o['server'], o['server_port'], o['method'], o['password']], ['1.2.3.4', 8443, 'chacha20-ietf-poly1305', 'p@ss:w']);
  });

  test('ssconf ss:// line response, IPv6 and invalid bodies', () {
    expect(OutlineKeys.ssFromResponse('ss://YWVzLTI1Ni1nY206cHc@s.com:8388\n', name: 'x'), 'ss://YWVzLTI1Ni1nY206cHc@s.com:8388#x');
    final v6 = OutlineKeys.ssFromResponse(
        jsonEncode({'server': '2001:db8::1', 'server_port': 443, 'password': 'pw', 'method': 'aes-256-gcm'}))!;
    expect(v6, contains('@[2001:db8::1]:443'));
    expect(OutlineKeys.ssFromResponse('{"server":"a.com","server_port":0,"password":"p","method":"m"}'), isNull);
    expect(OutlineKeys.ssFromResponse('<html>'), isNull);
    expect(OutlineKeys.isDynamic('ssconf://keys.example.com/abc#k'), isTrue);
  });
}
