import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/responsive_helper.dart';

/// Search field with typewriter hint — state is local so home list
/// does not rebuild every tick (major scroll/hover perf win).
class HomeTypewriterSearchField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showClear;
  final VoidCallback onClear;
  final List<String> hintNames;

  const HomeTypewriterSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.showClear,
    required this.onClear,
    required this.hintNames,
  });

  @override
  State<HomeTypewriterSearchField> createState() =>
      _HomeTypewriterSearchFieldState();
}

class _HomeTypewriterSearchFieldState extends State<HomeTypewriterSearchField> {
  final math.Random _random = math.Random();
  Timer? _timer;
  String _target = '';
  String _visible = '';
  bool _deleting = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    _pickNext();
    _startTypewriterTimer();
  }

  @override
  void didUpdateWidget(covariant HomeTypewriterSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
    if (widget.hintNames.isNotEmpty && _target.isEmpty) {
      _pickNext();
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (widget.controller.text.trim().isEmpty) {
      _startTypewriterTimer();
    }
  }

  void _startTypewriterTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 85), (_) => _tick());
  }

  void _pickNext() {
    final names = widget.hintNames;
    if (names.isEmpty) {
      _target = '';
      _visible = '';
      _index = 0;
      _deleting = false;
      return;
    }
    String next = names[_random.nextInt(names.length)];
    if (names.length > 1) {
      var guard = 0;
      while (next == _target && guard < 8) {
        next = names[_random.nextInt(names.length)];
        guard++;
      }
    }
    _target = next;
    _deleting = false;
    _index = 0;
    _visible = '';
  }

  void _tick() {
    if (!mounted) return;
    if (widget.focusNode.hasFocus) return;
    if (widget.controller.text.trim().isNotEmpty) return;
    if (_target.isEmpty) {
      _pickNext();
      if (_target.isEmpty) return;
    }

    if (_deleting) {
      if (_index > 0) {
        _index--;
        setState(() => _visible = _target.substring(0, _index));
      } else {
        _pickNext();
        _startTypewriterTimer();
        setState(() {});
      }
      return;
    }

    if (_index < _target.length) {
      _index++;
      setState(() => _visible = _target.substring(0, _index));
      return;
    }

    _timer?.cancel();
    _timer = null;
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      _deleting = true;
      _startTypewriterTimer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final small = ResponsiveHelper.isSmallMobile(context);
    final hint =
        _visible.isEmpty ? 'Search for ' : 'Search for $_visible';
    final maxW = ResponsiveHelper.isMobile(context) ? double.infinity : 520.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, small ? 16 : 36, 16, small ? 10 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontSize: small ? 14 : 17,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: small ? 13 : 16,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.white,
                  size: small ? 18 : 22,
                ),
                suffixIcon: widget.showClear
                    ? IconButton(
                        icon: Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                          size: small ? 16 : 18,
                        ),
                        onPressed: widget.onClear,
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  vertical: small ? 10 : 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
