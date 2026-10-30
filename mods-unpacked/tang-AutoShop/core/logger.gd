extends Reference

const LOG_NAME = "tang-AutoShop"
const PREFIX = "[AutoShop]"


static func info(message):
	# 依据：本机 addons/mod_loader/api/log.gd:info；进入游戏日志和加载器日志。
	ModLoaderLog.info(PREFIX + " INFO " + str(message), LOG_NAME)
	_write("INFO " + str(message))


static func warning(message):
	ModLoaderLog.warning(PREFIX + " WARN " + str(message), LOG_NAME)
	_write("WARN " + str(message))


static func error(message):
	ModLoaderLog.error(PREFIX + " ERROR " + str(message), LOG_NAME)
	_write("ERROR " + str(message))


static func _write(message):
	# 原生 stdout 可能延迟写盘；单独关闭日志文件让测试时能立即看到动作结果。
	var directory = Directory.new()
	if not directory.dir_exists("user://logs"):
		directory.make_dir_recursive("user://logs")
	var file = File.new()
	var path = "user://logs/autoshop.log"
	var mode = File.READ_WRITE if file.file_exists(path) else File.WRITE
	if file.open(path, mode) == OK:
		file.seek_end()
		file.store_line(PREFIX + " " + message)
		file.close()
