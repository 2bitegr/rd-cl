import 'package:flutter/material.dart';
import 'exantas_theme.dart';

/// Modal bottom sheet with drag handle, radius 16 and keyboard-safe padding.
Future<T?> showExSheet<T>(
        {required BuildContext context,
        required WidgetBuilder builder,
        bool scrollable = true}) =>
    showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        builder: (ctx) {
          final body = Padding(
              padding: EdgeInsets.fromLTRB(ExantasTokens.gutter, 0,
                  ExantasTokens.gutter, ExantasTokens.gutter + MediaQuery.viewInsetsOf(ctx).bottom),
              child: builder(ctx));
          return SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                key: const ValueKey('ex-sheet-handle'),
                width: 32,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: ExantasTokens.space3),
                decoration: BoxDecoration(
                    color: ctx.ex.border,
                    borderRadius:
                        BorderRadius.circular(ExantasTokens.radiusPill))),
            Flexible(
                child: scrollable ? SingleChildScrollView(child: body) : body),
          ]));
        });
