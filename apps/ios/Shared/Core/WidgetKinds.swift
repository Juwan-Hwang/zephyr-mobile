// 小组件 / 控制的 kind 常量：App（主动 reload）与 ZephyrWidgets（声明）共用，避免字符串散落。

enum WidgetKinds {
    static let status = "com.juwanh.zephyr.widget.status"
    static let usage = "com.juwanh.zephyr.widget.usage"
    static let scenes = "com.juwanh.zephyr.widget.scenes"
    static let lockScreen = "com.juwanh.zephyr.widget.lockscreen"
    static let connectionControl = "com.juwanh.zephyr.control.connection"
}
