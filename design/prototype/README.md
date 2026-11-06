# Zephyr Mobile 前端原型

浏览器打开 `index.html`，左侧可以切换 25 个章节。任一章节加 `?s=<id>.light` 或 `.xl` 可以查看浅色和大字体效果。

- 改页面：编辑 `pages.css` / `pages.html` / `pages.js`，然后运行 `python3 build.py`。它以 `index.v5.html` 为底稿生成 `index.html`。
- 测试：`python3 itest.py`（交互）和 `python3 ptest.py`（节点、规则页），需要 playwright。
- 截图：`python3 shoot.py <章节,...>`，输出到 `shots/`。演示视频：`python3 record3.py`。
- 案例说明：`Zephyr-Mobile-Case-Study.pdf`；演示：`Zephyr-Mobile-Demo.mp4`。
- 设计规范与规模方案：`../notes/`。

原型里的数据都是生成的，计时只反映浏览器内的表现，不代表真机性能。
