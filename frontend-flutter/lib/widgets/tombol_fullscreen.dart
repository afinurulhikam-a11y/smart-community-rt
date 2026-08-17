import 'package:flutter/material.dart';
import '../core/services/fullscreen_service.dart';
import '../core/theme/warna_konteks.dart';

/// Tombol untuk beralih antara mode normal dan mode layar penuh (fullscreen) di peramban web.
class TombolFullscreen extends StatefulWidget {
  final double size;
  final EdgeInsetsGeometry? padding;

  const TombolFullscreen({
    super.key,
    this.size = 20,
    this.padding,
  });

  @override
  State<TombolFullscreen> createState() => _TombolFullscreenState();
}

class _TombolFullscreenState extends State<TombolFullscreen> {
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _isFullscreen = FullscreenService.isFullscreen;
    FullscreenService.addListener(_onFullscreenChanged);
  }

  @override
  void dispose() {
    FullscreenService.removeListener(_onFullscreenChanged);
    super.dispose();
  }

  void _onFullscreenChanged() {
    if (mounted) {
      setState(() {
        _isFullscreen = FullscreenService.isFullscreen;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        await FullscreenService.toggleFullscreen();
        if (mounted) {
          setState(() {
            _isFullscreen = FullscreenService.isFullscreen;
          });
        }
      },
      tooltip: _isFullscreen ? 'Keluar layar penuh (Esc)' : 'Layar penuh',
      padding: widget.padding,
      icon: Icon(
        _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
        color: context.teksKedua,
        size: widget.size,
      ),
    );
  }
}
