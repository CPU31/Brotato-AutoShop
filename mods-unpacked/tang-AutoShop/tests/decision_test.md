# 自动测试

`decision_test.gd` 使用 Godot 3.x 运行。将包内 mods-unpacked 层级放到一个空 Godot 3 项目中，然后运行该脚本。它不读取或修改真实存档，不需要游戏原始代码。

```text
godot --no-window --path <空测试项目目录> -s res://mods-unpacked/tang-AutoShop/tests/decision_test.gd
```

通过标志：`DECISION_TEST_RESULT checks=22 failures=0`，并且日志无 SCRIPT ERROR。该脚本覆盖任务书原用例，并增加无限制、精确余额、HP 货币、失效 ID、全锁定、非法配置与输入不可变检查。

开发时另用独立测试桩运行真实 runner.gd：购买入口一次、有限次数停止、金币恰好花完、演练零副作用、停止令牌取消延迟续跑、空白名单、全部未加载目标、忙碌重试等 9 项检查。输出：`RUNNER_TEST_RESULT checks=9 failures=0`。测试桩留在开发工作区，不属于游戏资源。

自动测试无法代替真实游戏测试。图标、原生购买信号、扣款、入包和 Steam 加载另做了实机验证，范围及限制见验收记录。
