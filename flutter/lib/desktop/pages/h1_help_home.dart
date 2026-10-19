// H1 VPN: окно удалённой помощи (режим «только входящие») в стиле мини-приложения бота.
//
// Клиент видит код и пароль и одной кнопкой отправляет их в бот поддержки
// (t.me/<бот>?start=rd_<код>_<пароль>) — специалисту не нужно ничего диктовать.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

const kH1SupportBot = 'h1vpn_help_bot';
const kH1Source = 'https://github.com/by-sonic/h1-help';
const kH1Width = 360.0;

class H1Colors {
  static const bg = Color(0xFF04050A);
  static const bgGlow = Color(0xFF0D1440);
  static const surface = Color(0xD10E1122);
  static const line = Color(0x247C8EFF);
  static const lineStrong = Color(0x527C8EFF);
  static const text = Color(0xFFEEF1FF);
  static const muted = Color(0xFF8B93B8);
  static const faint = Color(0xFF5B6286);
  static const blue = Color(0xFF3D7BFF);
  static const violet = Color(0xFF6D4DFF);
  static const ok = Color(0xFF34D58A);
  static const warn = Color(0xFFF6B54A);
  static const bad = Color(0xFFFF5D6E);
}

/// Manrope — переменный шрифт: насыщенность задаётся осью wght.
TextStyle h1Text(double size,
    {double weight = 500,
    Color color = H1Colors.text,
    double? spacing,
    double? height}) {
  final index = ((weight / 100).round() - 1).clamp(0, 8);
  return TextStyle(
    fontFamily: 'Manrope',
    fontSize: size,
    fontWeight: FontWeight.values[index],
    fontVariations: [ui.FontVariation('wght', weight)],
    color: color,
    letterSpacing: spacing,
    height: height,
  );
}

/// «123 456 789» — так код легче прочитать вслух.
String h1GroupDigits(String id) {
  final digits = id.replaceAll(' ', '');
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }
  return out.toString();
}

class H1HelpHome extends StatefulWidget {
  /// Высота содержимого поменялась (статус, ошибка) — окно подгоняет размер.
  final VoidCallback? onLayoutChanged;

  const H1HelpHome({Key? key, this.onLayoutChanged}) : super(key: key);

  @override
  State<H1HelpHome> createState() => _H1HelpHomeState();
}

class _H1HelpHomeState extends State<H1HelpHome> {
  Timer? _timer;
  final _status = SvcStatus.notReady.obs;
  final _sent = false.obs;

  RxBool? get _svcStopped =>
      Get.isRegistered<RxBool>(tag: 'stop-service')
          ? Get.find<RxBool>(tag: 'stop-service')
          : null;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
    _update();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _update() async {
    try {
      final status = jsonDecode(await bind.mainGetConnectStatus())
          as Map<String, dynamic>;
      final num = status['status_num'] as int;
      final next = num == 1
          ? SvcStatus.ready
          : num == 0
              ? SvcStatus.connecting
              : SvcStatus.notReady;
      stateGlobal.svcStatus.value = next;
      if (_status.value != next) {
        _status.value = next;
        widget.onLayoutChanged?.call();
      }
      try {
        stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
      } catch (_) {}
    } catch (_) {}
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    showToast('$what скопирован');
  }

  Future<void> _sendToSupport(ServerModel model) async {
    final id = model.serverId.text.replaceAll(' ', '');
    final pass = model.serverPasswd.text.trim();
    if (id.isEmpty || pass.isEmpty || pass == '-') {
      showToast('Код ещё не готов — подождите пару секунд');
      return;
    }
    final url = 'https://t.me/$kH1SupportBot?start=rd_${id}_$pass';
    if (await canLaunchUrlString(url)) {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
      _sent.value = true;
      widget.onLayoutChanged?.call();
    } else {
      _copy('Код $id, пароль $pass', 'Код');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, _) => Container(
          width: kH1Width,
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.7, -0.4),
              radius: 1.3,
              colors: [H1Colors.bgGlow, H1Colors.bg],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statusPill(),
                    const SizedBox(height: 12),
                    _codeCard(
                      label: 'Ваш код',
                      value: h1GroupDigits(model.serverId.text),
                      onCopy: () => _copy(
                          model.serverId.text.replaceAll(' ', ''), 'Код'),
                    ),
                    const SizedBox(height: 10),
                    _codeCard(
                      label: 'Пароль',
                      value: model.serverPasswd.text,
                      onCopy: () => _copy(model.serverPasswd.text, 'Пароль'),
                      onRefresh: () => bind.mainUpdateTemporaryPassword(),
                    ),
                    const SizedBox(height: 16),
                    _sendButton(model),
                    const SizedBox(height: 12),
                    Obx(() => Text(
                          _sent.value
                              ? 'Код отправлен. Специалист подключится к вашему '
                                  'экрану — вы будете видеть всё, что он делает. '
                                  'Не закрывайте это окно.'
                              : 'Нажмите кнопку — откроется бот поддержки, и '
                                  'специалист получит код. Вы будете видеть всё, '
                                  'что он делает на экране.',
                          style: h1Text(12.5,
                              color: H1Colors.muted, height: 1.4),
                        )),
                    const SizedBox(height: 8),
                    Text(
                      'Чтобы отключить доступ, просто закройте это окно.',
                      style: h1Text(12.5,
                          weight: 600, color: H1Colors.faint, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    _footer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 170,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/h1_header.jpg',
              fit: BoxFit.cover, alignment: Alignment.topCenter),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x0004050A), Color(0x6604050A), H1Colors.bg],
                stops: [0.35, 0.7, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Image.asset('assets/h1_logo.png', height: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Удалённая помощь',
                          style: h1Text(20, weight: 800, height: 1.1)),
                      Text('Настроим VPN на вашем компьютере',
                          style: h1Text(12.5, color: H1Colors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    return Obx(() {
      final stopped = _svcStopped?.value ?? false;
      final status = _status.value;
      final (color, text) = stopped
          ? (H1Colors.bad, 'Доступ выключен')
          : switch (status) {
              SvcStatus.ready => (H1Colors.ok, 'Готово — можно подключаться'),
              SvcStatus.connecting => (H1Colors.warn, 'Подключаемся к серверу…'),
              _ => (H1Colors.bad, 'Нет связи с сервером — проверьте интернет'),
            };
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color, blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: h1Text(13, weight: 600, color: H1Colors.text))),
            if (stopped)
              InkWell(
                onTap: () => start_service(true),
                child: Text('Включить',
                    style: h1Text(13, weight: 700, color: H1Colors.blue)),
              ),
          ],
        ),
      );
    });
  }

  Widget _codeCard(
      {required String label,
      required String value,
      required VoidCallback onCopy,
      VoidCallback? onRefresh}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: H1Colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: H1Colors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: h1Text(11,
                        weight: 700, color: H1Colors.muted, spacing: 1.2)),
                const SizedBox(height: 2),
                SelectableText(
                  value.isEmpty ? '…' : value,
                  style: h1Text(26, weight: 800, spacing: 1.5),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            _iconButton(Icons.refresh_rounded, 'Новый пароль', onRefresh),
          _iconButton(Icons.copy_rounded, 'Скопировать', onCopy),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: H1Colors.muted),
        ),
      ),
    );
  }

  Widget _sendButton(ServerModel model) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [H1Colors.blue, H1Colors.violet],
        ),
        boxShadow: [
          BoxShadow(
              color: H1Colors.violet.withOpacity(0.45),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _sendToSupport(model),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.send_rounded, color: Colors.white, size: 19),
                const SizedBox(width: 10),
                Text('Отправить код в поддержку',
                    style: h1Text(15, weight: 800, color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    return Row(
      children: [
        Text('H1 VPN', style: h1Text(11, weight: 700, color: H1Colors.faint)),
        const Spacer(),
        InkWell(
          onTap: () => launchUrlString(kH1Source),
          child: Text('на основе RustDesk · исходный код',
              style: h1Text(11, color: H1Colors.faint)),
        ),
      ],
    );
  }
}
