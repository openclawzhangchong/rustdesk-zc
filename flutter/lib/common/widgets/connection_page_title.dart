import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:get/get.dart';

import '../../common.dart';

Widget getConnectionPageTitle(BuildContext context, bool isWeb) {
  return Row(
    children: [
      Expanded(
          child: Row(
        children: [
          AutoSizeText(
            translate('Control Remote Desktop'),
            maxLines: 1,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.merge(TextStyle(height: 1)),
          ).marginOnly(right: 4),
          Tooltip(
            waitDuration: Duration(milliseconds: 300),
            message: translate(isWeb ? "web_id_input_tip" : "id_input_tip"),
            child: Icon(
              Icons.help_outline_outlined,
              size: 16,
              color: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.color
                  ?.withOpacity(0.5),
            ),
          ),
          // 产品版本号显著上首页（用户要求）：桌面主窗口标题旁的版本徽标
          Tooltip(
            waitDuration: Duration(milliseconds: 300),
            message: '${translate('Product Version')}: $kZcProductVersion',
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: MyTheme.accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: MyTheme.accent.withOpacity(0.35)),
              ),
              child: Text(
                kZcProductVersion,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: MyTheme.accent),
              ),
            ),
          ).marginOnly(left: 6),
        ],
      )),
    ],
  );
}
