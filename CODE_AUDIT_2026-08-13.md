# 2026-08-13 深度代码复核与修复记录

## 本轮额外发现并修复

1. **Hive 测试 Adapter 注册顺序错误**
   - `WorkRecord` 的 `typeId=0`
   - `ShiftType` 的 `typeId=1`
   - 原 widget test 顺序相反，干净测试环境可能直接触发 Hive adapter 冲突。

2. **历史日期筛选边界错误**
   - “今天”原先从当前时刻开始，早于当前时刻的当天记录会被漏掉。
   - “近7天”原先同样会漏掉首日凌晨记录。
   - “上月”结束时间原先是上月最后一天 00:00，几乎整天数据都会被漏掉。
   - 现已统一使用自然日 00:00:00 ~ 23:59:59.999999。

3. **月报最后一天统计边界错误**
   - 月报结束时间原先为最后一天 00:00:00，导致月底当天大部分记录不参与统计。
   - 已修复为当月最后一天结束时刻。

4. **历史金额排序未使用真实单价**
   - 原代码 `amount({})` 永远拿空价格表计算，金额排序实际上失效。
   - 已让 `historyRecordsProvider` 监听 `unitPricesProvider` 并使用真实单价。

5. **删除/编辑/恢复后的首页当前日期记录刷新缺口**
   - 历史批量删除、单条删除、历史编辑、JSON 恢复、示例数据恢复后，原先部分路径没有刷新 `selectedDateRecordProvider`。
   - 已全部补齐。

6. **深色模式残留硬编码灰色文字**
   - 清理页面中 `Colors.grey` / `grey.shade500/600` 作为正文文字颜色的用法。
   - 改为 Material 3 `colorScheme.onSurfaceVariant`，避免深色背景下对比度不足。

## 已复核项目

- Provider 依赖链与主要写入路径
- Hive Adapter typeId
- 日期范围边界
- 月报统计边界
- 金额排序
- 深色模式文字颜色
- 导入后刷新
- 编辑后刷新
- 删除后刷新
- JSON 恢复后刷新
- 清空数据后刷新
- 示例数据写入后刷新
- ThemeData / Material 3 兼容写法
- TODO / FIXME / UnimplementedError
- 相对 import
- Android launcher / splash 资源路径

## 验证限制

当前执行环境没有 Flutter/Dart SDK，因此无法在此环境实际执行 `flutter analyze`、`flutter test` 或 `flutter build apk`。本轮完成的是源码级、资源级和逻辑级深度静态复核；交付到 Flutter 构建环境后应执行完整 CI 构建。
