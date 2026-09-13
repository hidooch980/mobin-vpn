import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobin_vpn/core/countries.dart';
import 'package:mobin_vpn/core/server.dart';
import 'package:mobin_vpn/core/singbox_outbound.dart';

void main() {
  test('remark gives country, number and protocol', () {
    final s = Server.fromUri(
      'vless://11111111-1111-1111-1111-111111111111@1.2.3.4:443?security=reality&sni=a.com&pbk=KEY&sid=ab'
      '#Mobin%20%E2%9C%A6%20%F0%9F%87%A9%F0%9F%87%AA%20Germany%2003%20%C2%B7%20VLESS',
    )!;
    expect(s.countryCode, 'DE');
    expect(s.displayName, 'آلمان 03');
    expect(s.protocolLabel, 'VLESS');
    expect(flagEmoji('DE'), '🇩🇪');
  });

  test('vless reality -> sing-box outbound', () {
    final o = parseOutbound(
      'vless://11111111-1111-1111-1111-111111111111@1.2.3.4:443?security=reality&type=grpc&serviceName=g'
      '&sni=a.com&fp=qq&pbk=KEY&sid=ab&flow=xtls-rprx-vision#x',
    )!;
    expect(o['type'], 'vless');
    expect(o['server_port'], 443);
    expect(o['flow'], 'xtls-rprx-vision');
    expect(o['tls']['reality']['public_key'], 'KEY');
    expect(o['tls']['utls']['fingerprint'], 'qq');
    expect(o['transport'], {'type': 'grpc', 'service_name': 'g'});
  });

  test('ws early data, vmess, ss, hysteria2, tuic', () {
    final ws = parseOutbound('trojan://pass@h.com:443?type=ws&path=%2Fp%3Fed%3D2048&host=cdn.com#x')!;
    expect(ws['transport'], {
      'type': 'ws', 'path': '/p', 'max_early_data': 2048,
      'early_data_header_name': 'Sec-WebSocket-Protocol', 'headers': {'Host': 'cdn.com'},
    });
    final vmessJson = base64.encode(utf8.encode(jsonEncode(
        {'add': 'v.com', 'port': '8080', 'id': 'uuid', 'net': 'ws', 'path': '/w', 'tls': 'tls', 'ps': 'n'})));
    expect(parseOutbound('vmess://$vmessJson')!['transport']['path'], '/w');
    final ss = parseOutbound('ss://${base64.encode(utf8.encode('aes-256-gcm:pw'))}@s.com:8388#x')!;
    expect([ss['method'], ss['password'], ss['server_port']], ['aes-256-gcm', 'pw', 8388]);
    expect(parseOutbound('hy2://pw@h.com:443?sni=x.com&obfs=salamander&obfs-password=o')!['obfs']['password'], 'o');
    expect(parseOutbound('tuic://u:p@t.com:443?alpn=h3')!['uuid'], 'u');
    expect(parseOutbound('vless://@1.2.3.4:443'), isNull);
    expect(parseOutbound('trojan://p@h.com:443?type=kcp'), isNull);
  });

  test('real published subscription parses', () {
    final path = Platform.environment['SUB_FILE'];
    if (path == null || !File(path).existsSync()) return;
    final servers = parseSubscription(File(path).readAsStringSync());
    final outbounds = servers.where((s) => parseOutbound(s.uri) != null).length;
    final named = servers.where((s) => s.countryCode != unknownCountry).length;
    // ignore: avoid_print
    print('servers=${servers.length} singbox_ok=$outbounds with_country=$named');
    expect(servers, isNotEmpty);
    expect(outbounds / servers.length, greaterThan(0.95));
  });
}
