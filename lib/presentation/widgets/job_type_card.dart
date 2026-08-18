import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/job_types.dart';

/// 作业类型计数卡片：彩色圆点 + 名称/单价 + 键盘直接输入数量 + - / + 微调。
class JobTypeCard extends StatefulWidget {
  final String jobType;
  final int quantity;
  final double unitPrice;

  /// 传绝对值（键盘输入或微调后的值），范围由上层 clamp。
  final ValueChanged<int> onChanged;

  const JobTypeCard({
    super.key,
    required this.jobType,
    required this.quantity,
    required this.unitPrice,
    required this.onChanged,
  });

  @override
  State<JobTypeCard> createState() => _JobTypeCardState();
}

class _JobTypeCardState extends State<JobTypeCard> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl.text = '${widget.quantity}';
  }

  @override
  void didUpdateWidget(covariant JobTypeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当外部值变化、且用户当前没在输入时，才把文本框同步回真实值，
    // 避免输入过程中光标被跳回开头。
    if (oldWidget.quantity != widget.quantity && !_focus.hasFocus) {
      _ctrl.text = '${widget.quantity}';
    }
  }

  void _emit(String text) {
    // 空串/非数字按 0 处理；值与当前一致则不触发，避免无意义的 rebuild。
    final v = int.tryParse(text) ?? 0;
    if (v != widget.quantity) widget.onChanged(v);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = DefaultJobTypes.colorOf(widget.jobType);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.jobType,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '¥${widget.unitPrice.toStringAsFixed(2)}/车',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            _StepButton(
              icon: Icons.remove,
              onPressed: widget.quantity > 0
                  ? () => widget.onChanged(widget.quantity - 1)
                  : null,
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                  signed: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                  border: UnderlineInputBorder(),
                ),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                onChanged: _emit,
                onSubmitted: (_) => _focus.unfocus(),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              color: cs.primary,
              onPressed: () => widget.onChanged(widget.quantity + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback? onPressed;

  const _StepButton({required this.icon, this.color, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: (color ?? Theme.of(context).colorScheme.primary)
            .withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
