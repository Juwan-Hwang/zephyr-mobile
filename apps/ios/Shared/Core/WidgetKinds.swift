// 小组件 / 控制的 kind 常量：App（主动 reload）与 ZephyrWidgets（声明）共用，避免字符串散落。

enum WidgetKinds {
    static let status = "app.zephyr.mobile.widget.status"
    static let usage = "app.zephyr.mobile.widget.usage"
    static let scenes = "app.zephyr.mobile.widget.scenes"
    static let lockScreen = "app.zephyr.mobile.widget.lockscreen"
    static let connectionControl = "app.zephyr.mobile.control.connection"
}
