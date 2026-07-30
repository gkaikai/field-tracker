/// 骨架屏组件 — 带 shimmer 动画
library;
import 'package:flutter/material.dart';

/// 单行骨架屏 — 带 shimmer 渐变动画
class FTSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const FTSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.borderRadius = 6,
  });

  @override
  State<FTSkeleton> createState() => _FTSkeletonState();
}

class _FTSkeletonState extends State<FTSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1 + _animation.value * 1.5, 0),
              end: Alignment(0 + _animation.value * 1.5, 0),
              colors: [
                Colors.grey.shade200,
                Colors.grey.shade100,
                Colors.grey.shade50,
                Colors.grey.shade100,
                Colors.grey.shade200,
              ],
              stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// 骨架屏列表项
class FTSkeletonList extends StatefulWidget {
  final int itemCount;
  final bool hasAvatar;

  const FTSkeletonList({
    super.key,
    this.itemCount = 4,
    this.hasAvatar = true,
  });

  @override
  State<FTSkeletonList> createState() => _FTSkeletonListState();
}

class _FTSkeletonListState extends State<FTSkeletonList> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(widget.itemCount, (i) => _buildItem()),
    );
  }

  Widget _buildItem() {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              if (widget.hasAvatar)
                _shimmerBox(width: 40, height: 40, shape: BoxShape.circle),
              if (widget.hasAvatar) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(width: 160, height: 12),
                    const SizedBox(height: 8),
                    _shimmerBox(width: 100, height: 10),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBox({double width = 40, double height = 40, BoxShape shape = BoxShape.rectangle}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(6) : null,
        gradient: LinearGradient(
          begin: Alignment(-1 + _animation.value * 1.5, 0),
          end: Alignment(0 + _animation.value * 1.5, 0),
          colors: [
            Colors.grey.shade200,
            Colors.grey.shade100,
            Colors.grey.shade50,
            Colors.grey.shade100,
            Colors.grey.shade200,
          ],
          stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
        ),
      ),
    );
  }
}
