// The activity indicator: the Xagent X, spinning. The sprite sheets in
// assets/whale/ (one still, three loops) are gone with the whale mascot; the X
// is drawn vector from `brand_glyph.g.dart` and rotates at a speed that eases
// toward the level's target. One X a screen: the chat page's pet still takes the
// place the whale used to.

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../shell/brand_glyph.g.dart';

/// DeepSeek 官方蓝。浅色玻璃上约 3.9–4.3:1(图形的 3:1 线以上)。
const deepSeekBlue = Color(0xFF4D6BFE);

/// 深色模式的提亮版:同色相,OKLCH(0.70, 0.15, 270),在深色页面和玻璃
/// (#14171E–#343944)上 4.2–6:1。只给图形用,文字仍用 onSurface。
const deepSeekBlueDark = Color(0xFF7A98FB);

/// 按亮度取活动指示器的默认颜色。
Color whaleColorFor(Brightness brightness) =>
    brightness == Brightness.dark ? deepSeekBlueDark : deepSeekBlue;

/// The X indicator. Spins whenever it runs; the speed and the still state
/// follow the level, exactly as the whale tail did:
///
/// | [level] | 什么时候 | 速度 |
/// |---|---|---|
/// | 0 | 等你确认 / 回答 | 0.3× |
/// | 1 | 在跑工具、等首字(没有字在流) | 0.5× |
/// | 2 | 慢慢吐字 | 1× |
/// | 3 | 正常速度 | 1× |
/// | 4 | 飞快 | 1× |
///
/// - 速度不跳:每一帧朝目标速度缓过去(时间常数约 0.35 秒)。
/// - [still] 时(空状态的品牌图形)画静止的 X,没有计时器;系统关闭动画时也是。
/// - 旋转以 X 的中心为轴,在它的正方形盒子里转。
class WhaleTail extends StatefulWidget {
  const WhaleTail({super.key, this.level = 1, required this.color, this.height = 20, this.still = false});

  final int level;

  final Color color;

  /// The side of the square the X spins in.
  final double height;

  /// 不动:静止的 X,没有计时器。
  final bool still;

  @override
  State<WhaleTail> createState() => WhaleTailState();
}

class WhaleTailState extends State<WhaleTail> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _repaint = ValueNotifier<int>(0);

  /// 速度追向目标的时间常数(秒)。
  static const _ease = 0.35;

  /// The rotation angle, in radians; it grows with the eased rate.
  double _angle = 0;

  /// The eased rate (a multiple of the level's target); it creeps toward the
  /// target instead of jumping.
  double _rate = 0;

  /// Whether the OS asked for animations to be reduced (cached from the
  /// MediaQuery; the original whale tail did the same).
  bool _reduced = false;

  Duration _last = Duration.zero;

  static double rateOf(int level) => switch (level) {
    <= 0 => 0.3,
    1 => 0.5,
    _ => 1.0,
  };

  /// One full turn takes [turnSeconds]; the eased rate multiplies it.
  static const turnSeconds = 2.4;

  @override
  void initState() {
    super.initState();
    _rate = rateOf(widget.level);
    if (_moving) _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(WhaleTail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  bool get _moving => !widget.still && !_reduced;

  /// Ticks whenever it moves.
  void _sync() {
    final moving = _moving;
    if (moving && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!moving && _ticker.isActive) {
      _ticker.stop();
      _repaint.value++;
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    final target = rateOf(widget.level);
    _rate += (target - _rate) * (1 - math.exp(-dt / _ease));
    _angle = (_angle + (2 * math.pi / turnSeconds) * dt * _rate) % (2 * math.pi);
    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    final size = Size.square(widget.height);
    return ExcludeSemantics(
      child: SizedBox.fromSize(
        size: size,
        child: CustomPaint(
          painter: _XPainter(angle: _angle, color: widget.color, repaint: _repaint),
        ),
      ),
    );
  }

  /// The current eased speed multiple, for tests.
  @visibleForTesting
  double get rate => _rate;

  /// The current rotation angle (radians), for tests: it keeps growing while
  /// the indicator runs, even at the slowest level.
  @visibleForTesting
  double get angle => _angle;
}

class _XPainter extends CustomPainter {
  _XPainter({required this.angle, required this.color, required Listenable repaint}) : super(repaint: repaint);

  final double angle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    // The brand X's ink box (357 × 280) fitted into the square: width-bounded,
    // centred, so it keeps equal margin on every side as it spins.
    final scale = size.width / 357;
    canvas.translate(-357 / 2 * scale, -280 / 2 * scale);
    canvas.scale(scale);
    BrandGlyph.paint(canvas, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_XPainter old) => old.angle != angle || old.color != color;
}
