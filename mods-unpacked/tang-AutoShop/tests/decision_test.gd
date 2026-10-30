extends SceneTree

const Decision = preload("res://mods-unpacked/tang-AutoShop/core/decision.gd")
const Config = preload("res://mods-unpacked/tang-AutoShop/core/config.gd")
var failures = 0
var checks = 0


func _init():
	var config = Config.DEFAULTS.duplicate(true)
	config.whitelist = ["target"]
	var state = {
		"gold": 100, "currency": 100, "hp_shop": false, "reroll_cost": 5,
		"auto_rerolls": 0, "reroll_blocked": false,
		"items": [{"slot": 0, "active": true, "id": "target", "price": 20, "is_item": true, "catalog_valid": true}]
	}
	check("命中并买得起", state, config, "buy")
	var s = state.duplicate(true)
	s.gold = 15
	s.currency = 15
	check("买不起目标仍刷新", s, config, "reroll")
	s = state.duplicate(true)
	s.gold = 60
	s.currency = 60
	s.items[0].price = 50
	var c = config.duplicate(true)
	c.keep_gold = 20
	check("保留金额阻止购买但可刷新", s, c, "reroll")
	s = state.duplicate(true)
	s.items = []
	s.reroll_cost = 35
	c = config.duplicate(true)
	c.max_reroll_cost = 30
	check("刷新单价上限", s, c, "stop", "reroll_cost")
	c = config.duplicate(true)
	c.whitelist = []
	check("空白名单零动作", state, c, "stop", "empty_whitelist")
	s = state.duplicate(true)
	s.items[0].is_item = false
	check("武器和非道具排除", s, config, "reroll")
	c = config.duplicate(true)
	c.max_rerolls = 5
	s = state.duplicate(true)
	s.items = []
	s.auto_rerolls = 5
	check("刷新次数上限", s, c, "stop", "max_rerolls")
	check("两格且空槽安全", state_with_slots(state), config, "buy")
	s.auto_rerolls = 100
	check("负一上限不限制", s, config, "reroll")
	s.gold = 4
	check("钱不够刷新", s, config, "stop", "insufficient_gold")
	s = state.duplicate(true)
	s.gold = 20
	s.currency = 20
	check("金币刚好等于价格", s, config, "buy")
	s.items[0].is_item = false
	check("消耗品箱子排除", s, config, "reroll")
	s = state.duplicate(true)
	s.items[0].catalog_valid = false
	check("失效ID不买", s, config, "reroll")
	s = state.duplicate(true)
	s.items = []
	s.reroll_blocked = true
	check("全锁定不刷新", s, config, "stop", "all_locked")
	c = config.duplicate(true)
	c.max_item_price = 10
	check("单件价格上限", state, c, "reroll")
	c.enabled = false
	check("总开关关闭", state, c, "stop", "disabled")
	s = state.duplicate(true)
	s.hp_shop = true
	s.currency = 20
	check("HP商店保留1最大生命", s, config, "reroll")
	s.currency = 21
	check("HP商店正常购买", s, config, "buy")
	var before = JSON.print(state)
	Decision.decide(state, config)
	expect("决策不改变输入", before == JSON.print(state))
	var validated = Config.sanitize({"max_rerolls": -1, "max_reroll_cost": -1, "whitelist": [], "keep_gold": -2, "enabled": "true", "buy_weapons": true})
	expect("配置负一保留", validated.config.max_rerolls == -1 and validated.config.max_reroll_cost == -1)
	expect("非法值回退且类型禁买", validated.config.keep_gold == 0 and validated.config.enabled == true and validated.config.buy_weapons == false)
	expect("空白名单仍为空", validated.config.whitelist.empty())
	print("DECISION_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func state_with_slots(state):
	var s = state.duplicate(true)
	s.items.append({"slot": 1, "active": false})
	return s


func check(name, state, config, action, reason = ""):
	var result = Decision.decide(state, config)
	expect(name, result.action == action and (reason.empty() or result.get("reason", "") == reason))


func expect(name, passed):
	checks += 1
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + name)
