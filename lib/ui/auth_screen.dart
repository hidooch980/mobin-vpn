import 'package:flutter/material.dart';

import '../core/account.dart';
import '../core/engine.dart';
import 'aurora_background.dart';
import 'glass.dart';
import 'style.dart';

/// Sign in / sign up. Shown before the app when accounts are enabled and nobody is signed in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.account});

  final Account account;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signUp = false, _busy = false, _hidden = true;
  String? _message;
  bool _messageIsError = true;
  final _name = TextEditingController(), _email = TextEditingController(), _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim(), password = _password.text;
    if (!email.contains('@') || password.length < 6 || (_signUp && _name.text.trim().isEmpty)) {
      setState(() {
        _messageIsError = true;
        _message = _signUp ? 'نام، ایمیل و رمز (دست‌کم ۶ کاراکتر) را وارد کنید.' : 'ایمیل و رمز (دست‌کم ۶ کاراکتر) را وارد کنید.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = _signUp
        ? await widget.account.signUp(_name.text, email, password)
        : await widget.account.signIn(email, password);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result == 'confirm') {
        _messageIsError = false;
        _message = 'ثبت‌نام انجام شد. لینک تأیید به $email فرستاده شد؛ بعد از تأیید، وارد شوید.';
        _signUp = false;
      } else {
        _messageIsError = true;
        _message = result;
      }
    });
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _messageIsError = true;
        _message = 'اول ایمیل خود را بنویسید، بعد «فراموشی رمز» را بزنید.';
      });
      return;
    }
    setState(() => _busy = true);
    final result = await widget.account.resetPassword(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _messageIsError = result != null;
      _message = result ?? 'لینک تغییر رمز به $email فرستاده شد.';
    });
  }

  InputDecoration _field(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Palette.muted),
        prefixIcon: Icon(icon, color: Palette.muted),
        suffixIcon: suffix,
        filled: true,
        fillColor: Palette.fill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Palette.accent, width: 1.6)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        colors: Palette.forState(VpnState.disconnected),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(colors: [Palette.accent, Palette.forState(VpnState.connected)[2]]),
                          boxShadow: [BoxShadow(color: Palette.accent.withValues(alpha: 0.4), blurRadius: 30)],
                        ),
                        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 42),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Mobin VPN', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Palette.text)),
                    Text(_signUp ? 'ساخت حساب جدید' : 'به حساب خود وارد شوید',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Palette.muted)),
                    const SizedBox(height: 22),
                    Glass(
                      radius: 26,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Tabs(signUp: _signUp, onChanged: (v) => setState(() {
                                _signUp = v;
                                _message = null;
                              })),
                          const SizedBox(height: 16),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            child: _signUp
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TextField(
                                      controller: _name,
                                      textInputAction: TextInputAction.next,
                                      style: TextStyle(color: Palette.text),
                                      decoration: _field('نام و نام خانوادگی', Icons.person_rounded),
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            style: TextStyle(color: Palette.text),
                            decoration: _field('ایمیل', Icons.alternate_email_rounded),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            obscureText: _hidden,
                            textDirection: TextDirection.ltr,
                            onSubmitted: (_) => _submit(),
                            autofillHints: const [AutofillHints.password],
                            style: TextStyle(color: Palette.text),
                            decoration: _field(
                              'رمز عبور',
                              Icons.lock_rounded,
                              suffix: IconButton(
                                tooltip: _hidden ? 'نمایش رمز' : 'پنهان کردن رمز',
                                onPressed: () => setState(() => _hidden = !_hidden),
                                icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Palette.muted),
                              ),
                            ),
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: 12),
                            Text(_message!,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.7,
                                  color: _messageIsError ? Palette.forDelay(9999) : Palette.forDelay(1),
                                )),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: Palette.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _busy
                                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                : Text(_signUp ? 'ثبت‌نام' : 'ورود', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                          if (!_signUp)
                            TextButton(
                              onPressed: _busy ? null : _forgot,
                              child: Text('رمز را فراموش کرده‌ام', style: TextStyle(color: Palette.muted)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('هر حساب روی یک دستگاه فعال می‌شود.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Palette.muted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.signUp, required this.onChanged});

  final bool signUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool value) {
      final selected = signUp == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Palette.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : Palette.muted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Palette.fill, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [tab('ورود', false), tab('ثبت‌نام', true)]),
    );
  }
}

/// Shown when the account is turned off in the panel or bound to another device.
class AccountBlockedScreen extends StatelessWidget {
  const AccountBlockedScreen({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final disabled = account.status == AccountStatus.disabled;
    return Scaffold(
      body: AuroraBackground(
        colors: Palette.forState(VpnState.connecting),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Glass(
                  radius: 26,
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(disabled ? Icons.block_rounded : Icons.devices_other_rounded, size: 56, color: Palette.forDelay(9999)),
                      const SizedBox(height: 12),
                      Text(disabled ? 'حساب شما غیرفعال است' : 'این حساب روی دستگاه دیگری فعال است',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Palette.text)),
                      const SizedBox(height: 8),
                      Text(
                        disabled
                            ? 'مدیر دسترسی این حساب را قطع کرده است. برای فعال شدن با او تماس بگیرید.'
                            : 'هر حساب فقط روی یک دستگاه کار می‌کند. از مدیر بخواهید دستگاه قبلی را آزاد کند، یا با حساب دیگری وارد شوید.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, height: 1.8, color: Palette.muted),
                      ),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: account.refreshStatus,
                            style: FilledButton.styleFrom(backgroundColor: Palette.accent, padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: const Text('بررسی دوباره'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: account.signOut,
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: Text('خروج از حساب', style: TextStyle(color: Palette.text)),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
