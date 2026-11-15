// 全局的路由观察者：页面靠它知道「自己是不是被别的页面盖住了」。
//
// 目前只有会话页订阅：被别的页面（详情、抽屉里打开的页面、图片查看、各种
// bottom sheet）盖住时把输入框的 focus 丢掉。不丢的话，Flutter 在 pop 回来时
// 会把焦点还给输入框，Android 于是又弹出键盘——用户看到的就是「返回会话页键盘
// 自己弹起来」。

import 'package:flutter/widgets.dart';

final RouteObserver<ModalRoute<dynamic>> appRouteObserver = RouteObserver<ModalRoute<dynamic>>();
